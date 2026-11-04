using System.Globalization;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Events;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;
using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Network;
using TheKrystalShip.KGSM.Engine.Operations;
using TheKrystalShip.KGSM.Engine.Status;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>
/// The source's half of a transfer. A manifest taken under a token locks the instance: the lock is placed
/// first, autostart is switched off, and only then is the instance measured, so nothing can start it
/// between the check and the lock. A part streams the instance's bytes while the lock holds and the
/// instance stays stopped; the commit removes the instance, its backups and the images nothing else uses.
/// </summary>
public sealed partial class TransferExportService(OperationHost host)
{
    private const string TreePartId = "tree";

    /// <summary>The manifest of a stopped instance.</summary>
    /// <param name="instance">The instance.</param>
    /// <param name="token">The transfer's token. With one, the instance is locked under it; without, the manifest is a read, refused while any transfer holds the instance.</param>
    /// <param name="cancellationToken">Cancellation of the command.</param>
    public async Task<TransferManifest> ManifestAsync(InstanceDescription instance, string? token, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        Guards.Online(instance, "export");
        if (token is not null && !TransferLock.IsValidToken(token))
            throw OperationException.Invalid("a lock token is 1 to 128 characters of letters, digits and _ . : @ -");

        using IDisposable held = host.Locks.AcquireInstance(instance.Id);
        var locking = new TransferLocking(host);

        string? holder = TransferLock.Holder(instance.Layout);
        if (holder is not null && !string.Equals(holder, token, StringComparison.Ordinal))
            throw new TransferLockedException(instance.Id, "export");

        bool placed = token is not null && await locking.TakeAsync(instance, token, cancellationToken).ConfigureAwait(false);
        try
        {
            // Measured after the lock, so the lock is what keeps the instance stopped.
            await RequireStoppedAsync(instance, cancellationToken).ConfigureAwait(false);

            return await BuildManifestAsync(instance, config, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception)
        {
            if (placed)
            {
                try
                {
                    await locking.ReleaseAsync(instance, token, CancellationToken.None).ConfigureAwait(false);
                }
                catch (EngineException ex)
                {
                    host.Logger("transfer").LogError(ex, "The lock on {Id} could not be released after a refused manifest; 'kgsm instance unlock {Id}' releases it", instance.Id, instance.Id);
                }
            }

            throw;
        }
    }

    /// <summary>Streams one part to <paramref name="destination"/>. The instance must be locked under the token and stopped.</summary>
    public async Task PartAsync(InstanceDescription instance, string partId, string token, Stream destination, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        Guards.Online(instance, "export");
        RequireHolder(instance, token);
        await RequireStoppedAsync(instance, cancellationToken).ConfigureAwait(false);

        if (partId == TreePartId)
        {
            IReadOnlyList<TreeMember> members = TransferTree.Of(host.Paths, instance, config, CustomBlueprintFile(config.Blueprint, out _));
            await TreeArchive.WriteAsync(TreeArchive.Enumerate(members), destination, cancellationToken).ConfigureAwait(false);
            return;
        }

        Match match = ImagePart().Match(partId);
        if (!match.Success || config.Runtime != BlueprintRuntime.Container)
            throw OperationException.NotFound($"'{instance.Id}' has no part '{partId}'");

        int index = int.Parse(match.Groups["n"].Value, CultureInfo.InvariantCulture);
        IReadOnlyList<string> references = await host.Images.ReferencedByAsync(instance.Layout.ComposeFile, instance.WorkingDirectory, cancellationToken).ConfigureAwait(false);
        if (index < 1 || index > references.Count)
            throw OperationException.NotFound($"'{instance.Id}' has no part '{partId}'");

        await using var sealing = new ImageStream.Writer(destination);
        await host.Images.SaveAsync(references[index - 1], sealing, cancellationToken).ConfigureAwait(false);
        await sealing.CompleteAsync(cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Removes the instance as an uninstall does, together with its backups and the images no other instance
    /// uses. Only the holder of the lock may commit, and only while the instance is stopped.
    /// </summary>
    public async Task<ExportCommitReport> CommitAsync(InstanceDescription instance, string token, CancellationToken cancellationToken)
    {
        InstanceConfig config = Guards.Config(instance);
        Guards.Online(instance, "export");
        RequireHolder(instance, token);
        await RequireStoppedAsync(instance, cancellationToken).ConfigureAwait(false);

        IReadOnlyList<string> unshared = await UnsharedImagesAsync(instance, config, cancellationToken).ConfigureAwait(false);

        UninstallReport removed = await new UninstallService(host)
            .UninstallAsync(instance, force: true, purgeBackups: true, token, cancellationToken).ConfigureAwait(false);

        var imagesRemoved = new List<string>();
        foreach (string reference in unshared)
        {
            if (await host.Images.RemoveAsync(reference, cancellationToken).ConfigureAwait(false)) imagesRemoved.Add(reference);
            else host.Logger("transfer").LogWarning("The image {Reference} of the exported {Id} could not be removed", reference, instance.Id);
        }

        host.Events.Append(new Exported { InstanceName = instance.Id });
        return new ExportCommitReport { Instance = instance.Id, BackupsRemoved = removed.BackupsRemoved, ImagesRemoved = imagesRemoved };
    }

    private void RequireHolder(InstanceDescription instance, string token)
    {
        string? holder = TransferLock.Holder(instance.Layout);
        if (holder is null || !string.Equals(holder, token, StringComparison.Ordinal))
            throw new TransferLockedException(instance.Id, "export");
    }

    private async Task RequireStoppedAsync(InstanceDescription instance, CancellationToken cancellationToken)
    {
        InstanceProcess process = await host.MeasureAsync(instance, cancellationToken).ConfigureAwait(false);
        if (process.State == RunState.Running)
            throw new OperationException(ErrorCodes.Running, $"'{instance.Id}' is running; it must stay stopped to be transferred", ExitCodes.InstanceRunning);
        if (process.State == RunState.Unknown)
            throw OperationException.Refused($"whether '{instance.Id}' is running cannot be measured ({process.Detail ?? "no answer"})");
    }

    private async Task<TransferManifest> BuildManifestAsync(InstanceDescription instance, InstanceConfig config, CancellationToken cancellationToken)
    {
        TransferLockRecord? lockRecord = TransferLock.Holder(instance.Layout) is null ? null : TransferLock.Read(instance.Layout);
        bool autostart = lockRecord?.Autostart
            ?? await new TransferLocking(host).ReadAutostartAsync(config, instance.Id, cancellationToken).ConfigureAwait(false);

        string? customFile = CustomBlueprintFile(config.Blueprint, out string? resolved);
        string sha = resolved is not null ? Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(resolved))) : string.Empty;

        IReadOnlyList<string> requirements = host.Blueprints.Read(config.Blueprint)?.Blueprint is { } blueprint
            ? BlueprintRequirementRules.IdsFor(blueprint)
            : [];

        IReadOnlyList<TreeMember> members = TransferTree.Of(host.Paths, instance, config, customFile);
        (long bytes, long files) = TreeArchive.Measure(members);
        var parts = new List<TransferPart>
        {
            new() { Id = TreePartId, Kind = TransferPartKind.Tree, Bytes = bytes, Files = files },
        };

        if (config.Runtime == BlueprintRuntime.Container)
        {
            IReadOnlyList<string> references = await host.Images.ReferencedByAsync(instance.Layout.ComposeFile, instance.WorkingDirectory, cancellationToken).ConfigureAwait(false);
            for (int i = 0; i < references.Count; i++)
            {
                ImageInfo image = await host.Images.InspectAsync(references[i], cancellationToken).ConfigureAwait(false)
                    ?? throw OperationException.NotFound($"the image {references[i]} of '{instance.Id}' is not on this host");
                parts.Add(new TransferPart
                {
                    Id = $"image-{i + 1}",
                    Kind = TransferPartKind.Image,
                    Bytes = image.Size,
                    Ref = references[i],
                    ImageId = image.Chain,
                });
            }
        }

        return new TransferManifest
        {
            SchemaVersion = SchemaVersions.TransferManifest,
            EngineVersion = host.EngineVersion,
            Instance = new TransferInstance
            {
                Id = instance.Id,
                Blueprint = config.Blueprint,
                Runtime = config.Runtime,
                DisplayName = config.DisplayName.Length == 0 || config.DisplayName == instance.Id ? null : config.DisplayName,
                Autostart = autostart,
                HasRun = InstanceHistory.HasRun(instance.Layout),
                Library = instance.Library?.Name ?? "unregistered",
                Ports = PortSpecs.Parse(config.Ports),
            },
            Blueprint = new TransferBlueprint { Name = config.Blueprint, Custom = customFile is not null, Sha256 = sha },
            Requirements = requirements,
            Parts = parts,
        };
    }

    /// <summary>The blueprint file when it is the person's own, else null; <paramref name="resolved"/> is the file either way.</summary>
    private string? CustomBlueprintFile(string name, out string? resolved)
    {
        resolved = null;
        if (!BlueprintParser.IsValidName(name)) return null;

        BlueprintResolution resolution = host.Blueprints.Find(name);
        resolved = resolution.Resolved;
        return resolution.Tier == BlueprintTier.User ? resolution.Resolved : null;
    }

    /// <summary>
    /// The references this instance uses that no other instance does, so removing the instance removes the
    /// images nobody else runs. When another instance's images cannot be resolved nothing is removed: an
    /// image that might be in use stays.
    /// </summary>
    private async Task<IReadOnlyList<string>> UnsharedImagesAsync(InstanceDescription instance, InstanceConfig config, CancellationToken cancellationToken)
    {
        if (config.Runtime != BlueprintRuntime.Container) return [];

        IReadOnlyList<string> mine;
        try
        {
            mine = await host.Images.ReferencedByAsync(instance.Layout.ComposeFile, instance.WorkingDirectory, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationException ex)
        {
            host.Logger("transfer").LogWarning("The images of {Id} cannot be resolved ({Problem}); none is removed", instance.Id, ex.Message);
            return [];
        }

        var others = new HashSet<string>(StringComparer.Ordinal);
        foreach (InstanceDescription other in host.Instances.List())
        {
            if (other.Id == instance.Id || other.Config is not { Runtime: BlueprintRuntime.Container }) continue;
            try
            {
                others.UnionWith(await host.Images.ReferencedByAsync(other.Layout.ComposeFile, other.WorkingDirectory, cancellationToken).ConfigureAwait(false));
            }
            catch (OperationException ex)
            {
                host.Logger("transfer").LogWarning("The images of {Id} cannot be resolved ({Problem}); none is removed", other.Id, ex.Message);
                return [];
            }
        }

        return [.. mine.Where(reference => !others.Contains(reference))];
    }

    [GeneratedRegex("^image-(?<n>[0-9]+)$")]
    private static partial Regex ImagePart();
}
