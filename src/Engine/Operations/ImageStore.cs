using System.Diagnostics;
using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Reports;

namespace TheKrystalShip.KGSM.Engine.Operations;

/// <summary>An image the container runtime holds.</summary>
/// <param name="Id">The id the runtime itself knows the image by, which names it in a removal or a tag. It differs between two runtimes holding the same image, because the runtime's image store decides what it digests.</param>
/// <param name="Size">The room the image takes once loaded.</param>
/// <param name="Chain">
/// The digest of the image's layer chain: the same on any host and in any image store, so it is what a transfer
/// compares. It covers every byte of the image's file system.
/// </param>
public sealed record ImageInfo(string Id, long Size, string Chain);

/// <summary>
/// What a transfer asks of the container runtime: the images an instance's compose file uses, what the
/// runtime holds, and the stream that moves one image between hosts. A test supplies its own.
/// </summary>
public interface IImageStore
{
    /// <summary>The image references a compose file resolves to, sorted and unique.</summary>
    /// <exception cref="OperationException">The runtime cannot resolve the file.</exception>
    Task<IReadOnlyList<string>> ReferencedByAsync(string composeFile, string workingDirectory, CancellationToken cancellationToken);

    /// <summary>The image behind a reference or a runtime id; null when the runtime does not hold it.</summary>
    /// <exception cref="OperationException">The runtime cannot be asked.</exception>
    Task<ImageInfo?> InspectAsync(string reference, CancellationToken cancellationToken);

    /// <summary>Writes the image to <paramref name="destination"/> as the runtime saves it.</summary>
    /// <exception cref="OperationException">The runtime failed; what was written is not an image.</exception>
    Task SaveAsync(string reference, Stream destination, CancellationToken cancellationToken);

    /// <summary>Reads an image the runtime saved from <paramref name="source"/> and loads it.</summary>
    /// <exception cref="OperationException">The runtime refused the stream.</exception>
    Task LoadAsync(Stream source, CancellationToken cancellationToken);

    /// <summary>Puts a reference on an image that is already held.</summary>
    Task TagAsync(string imageId, string reference, CancellationToken cancellationToken);

    /// <summary>Removes an image by its runtime id or a reference; false when the runtime would not.</summary>
    Task<bool> RemoveAsync(string idOrReference, CancellationToken cancellationToken);

    /// <summary>The free bytes where the runtime keeps its images; null when that cannot be measured.</summary>
    Task<long?> FreeBytesAsync(CancellationToken cancellationToken);
}

/// <summary>The images of a host through the <c>docker</c> command line.</summary>
public sealed class DockerImages(IProcessRunner runner) : IImageStore
{
    public async Task<IReadOnlyList<string>> ReferencedByAsync(string composeFile, string workingDirectory, CancellationToken cancellationToken)
    {
        ProcessResult result = await runner.RunAsync(
            new ProcessCall("docker", ["compose", "-f", composeFile, "config", "--images"], workingDirectory), cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded) throw new OperationException(ErrorCodes.Failed, $"the container runtime cannot resolve the images of {composeFile}: {Reason(result)}");

        string[] images = [.. result.Output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)];
        if (images.Length == 0) throw new OperationException(ErrorCodes.Failed, $"{composeFile} names no image");
        return images;
    }

    public async Task<ImageInfo?> InspectAsync(string reference, CancellationToken cancellationToken)
    {
        ProcessResult result = await runner.RunAsync(
            new ProcessCall("docker", ["image", "inspect", "--format", "{{.Id}} {{.Size}} {{join .RootFS.Layers \",\"}}", reference]), cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded)
        {
            if (result.Error.Contains("No such image", StringComparison.OrdinalIgnoreCase)) return null;
            throw new OperationException(ErrorCodes.Failed, $"the container runtime cannot be asked about {reference}: {Reason(result)}");
        }

        string[] fields = result.Output.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length is < 2 or > 3 || !long.TryParse(fields[1], NumberStyles.None, CultureInfo.InvariantCulture, out long size))
            throw new OperationException(ErrorCodes.Failed, $"the container runtime answered something unreadable about {reference}: {result.Output.Trim()}");
        return new ImageInfo(fields[0], size, ChainOf(fields.Length == 3 ? fields[2].Split(',') : []));
    }

    public async Task SaveAsync(string reference, Stream destination, CancellationToken cancellationToken)
    {
        ProcessStartInfo start = Start(["save", reference]);
        start.RedirectStandardOutput = true;

        using Process process = Launch(start);
        Task<string> error = process.StandardError.ReadToEndAsync(cancellationToken);
        try
        {
            await process.StandardOutput.BaseStream.CopyToAsync(destination, 81920, cancellationToken).ConfigureAwait(false);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            Kill(process);
            throw;
        }
        catch (IOException)
        {
            // The reader went away; the runtime is stopped rather than left writing into nothing.
            Kill(process);
            throw;
        }

        if (process.ExitCode != 0)
            throw new OperationException(ErrorCodes.Failed, $"docker save {reference} failed: {Trim(await error.ConfigureAwait(false))}");
    }

    public async Task LoadAsync(Stream source, CancellationToken cancellationToken)
    {
        ProcessStartInfo start = Start(["load"]);
        start.RedirectStandardInput = true;
        start.RedirectStandardOutput = true;

        using Process process = Launch(start);
        Task<string> output = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> error = process.StandardError.ReadToEndAsync(cancellationToken);
        try
        {
            try
            {
                await source.CopyToAsync(process.StandardInput.BaseStream, 81920, cancellationToken).ConfigureAwait(false);
            }
            finally
            {
                try { process.StandardInput.Close(); } catch (IOException) { }
            }

            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            Kill(process);
            throw;
        }
        catch (IOException)
        {
            // The runtime stopped reading: it has already said why.
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }

        await output.ConfigureAwait(false);
        if (process.ExitCode != 0)
            throw new OperationException(ErrorCodes.Failed, $"docker load failed: {Trim(await error.ConfigureAwait(false))}");
    }

    public async Task TagAsync(string imageId, string reference, CancellationToken cancellationToken)
    {
        ProcessResult result = await runner.RunAsync(new ProcessCall("docker", ["tag", imageId, reference]), cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded) throw new OperationException(ErrorCodes.Failed, $"docker tag {reference} failed: {Reason(result)}");
    }

    public async Task<bool> RemoveAsync(string idOrReference, CancellationToken cancellationToken)
    {
        ProcessResult result = await runner.RunAsync(new ProcessCall("docker", ["rmi", idOrReference]), cancellationToken).ConfigureAwait(false);
        return result.Succeeded;
    }

    public async Task<long?> FreeBytesAsync(CancellationToken cancellationToken)
    {
        ProcessResult result = await runner.RunAsync(
            new ProcessCall("docker", ["info", "--format", "{{.DockerRootDir}}"]), cancellationToken).ConfigureAwait(false);
        if (!result.Succeeded) return null;

        string? root = result.Output.Trim();
        // The runtime's own directory is often readable by its owner only; its parent answers for the same disk.
        while (!string.IsNullOrEmpty(root) && root != "/")
        {
            try
            {
                return new DriveInfo(root).AvailableFreeSpace;
            }
            catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException)
            {
                root = Path.GetDirectoryName(root);
            }
        }

        return null;
    }

    /// <summary>The digest of a layer chain: the layers' own digests, in order, one per line.</summary>
    public static string ChainOf(IEnumerable<string> layers) =>
        "chain:sha256:" + Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(string.Join('\n', layers))));

    private static ProcessStartInfo Start(string[] arguments)
    {
        var start = new ProcessStartInfo("docker") { UseShellExecute = false, RedirectStandardError = true };
        foreach (string argument in arguments) start.ArgumentList.Add(argument);
        return start;
    }

    private static Process Launch(ProcessStartInfo start)
    {
        try
        {
            return Process.Start(start) ?? throw new OperationException(ErrorCodes.Failed, "docker could not be started");
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            throw new OperationException(ErrorCodes.Failed, $"docker could not be started: {ex.Message}", inner: ex);
        }
    }

    private static void Kill(Process process)
    {
        try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
    }

    private static string Reason(ProcessResult result) => result.ErrorTail() is { Length: > 0 } tail ? tail : $"exit {result.ExitCode}";

    private static string Trim(string text) => string.Join(" | ", text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).TakeLast(3));
}
