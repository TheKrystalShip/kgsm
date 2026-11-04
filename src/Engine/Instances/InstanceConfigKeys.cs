using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>One key of the instance config: its JSON name, its type, how to read it as text and whether <c>config set</c> may change it.</summary>
public sealed record InstanceConfigKey(string Name, string Type, Func<InstanceConfig, string?> Read, bool Settable);

/// <summary>
/// Every key of the instance config, in the order the file declares them. The table is explicit because
/// the engine reads its types without reflection.
/// </summary>
/// <remarks>
/// A key is <b>protected</b> (not settable) when changing it by hand corrupts the instance or desyncs it
/// from something the engine owns: identity and structure (<c>name</c>, <c>blueprint</c>, <c>runtime</c>,
/// <c>platform</c>, the install datetime and nonce, the Steam ids, the ports, the maintenance-window
/// authors, which the engine writes with the windows themselves), the one stored path, every executable
/// path key, and the firewall switch, which has a flow of its own.
/// </remarks>
public static class InstanceConfigKeys
{
    public static IReadOnlyList<InstanceConfigKey> All { get; } =
    [
        Text("name", c => c.Name, settable: false),
        Text("displayName", c => c.DisplayName),
        Text("blueprint", c => c.Blueprint, settable: false),
        Text("runtime", c => c.Runtime == BlueprintRuntime.Native ? "native" : "container", settable: false),
        new("installDatetime", "datetime", c => c.InstallDatetime?.ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture), false),
        Text("installNonce", c => c.InstallNonce, settable: false),
        Text("backupsDirectory", c => c.BackupsDirectory, settable: false),
        Text("platform", c => c.Platform, settable: false),
        Bool("autoUpdateBeforeStart", c => c.AutoUpdateBeforeStart),
        Text("cpuPriority", c => c.CpuPriority),
        Int("memoryCapMb", c => c.MemoryCapMb),
        Text("maintenanceWindows", c => c.MaintenanceWindows),
        Text("maintenanceWindowsAuthor", c => c.MaintenanceWindowsAuthor, settable: false),
        Text("maintenanceWindowsAuthorName", c => c.MaintenanceWindowsAuthorName, settable: false),
        Text("timezone", c => c.Timezone),
        Int("backupRetention", c => c.BackupRetention),
        Text("announceLeadMinutes", c => c.AnnounceLeadMinutes),
        Text("announceMaintenanceMessage", c => c.AnnounceMaintenanceMessage),
        Text("announceMaintenanceCancelledMessage", c => c.AnnounceMaintenanceCancelledMessage),
        Bool("crashRestart", c => c.CrashRestart),
        Int("crashMaxRestarts", c => c.CrashMaxRestarts),
        Text("startupSuccessRegex", c => c.StartupSuccessRegex),
        Text("playerJoinedRegex", c => c.PlayerJoinedRegex),
        Text("playerLeftRegex", c => c.PlayerLeftRegex),
        new("rconPort", "int", c => c.RconPort?.ToString(CultureInfo.InvariantCulture), true),
        Text("rconPassword", c => c.RconPassword),
        Int("rconPollIntervalSeconds", c => c.RconPollIntervalSeconds),
        Text("rconPlayersCommand", c => c.RconPlayersCommand),
        Text("rconPlayersRegex", c => c.RconPlayersRegex),
        Text("levelName", c => c.LevelName),
        Text("executableFile", c => c.ExecutableFile, settable: false),
        Text("executableSubdirectory", c => c.ExecutableSubdirectory, settable: false),
        Text("executableArguments", c => c.ExecutableArguments),
        new("steamAppId", "int", c => c.SteamAppId.ToString(CultureInfo.InvariantCulture), false),
        new("clientSteamAppId", "int", c => c.ClientSteamAppId.ToString(CultureInfo.InvariantCulture), false),
        Text("steamcmdArguments", c => c.SteamcmdArguments),
        new("isSteamAccountRequired", "bool", c => Format(c.IsSteamAccountRequired), false),
        Text("ports", c => c.Ports, settable: false),
        new("enableFirewallManagement", "bool", c => Format(c.EnableFirewallManagement), false),
        Bool("enablePortForwarding", c => c.EnablePortForwarding),
        Int("downloadTimeoutSeconds", c => c.DownloadTimeoutSeconds),
        Text("stopCommand", c => c.StopCommand),
        Text("saveCommand", c => c.SaveCommand),
        Int("saveCommandTimeoutSeconds", c => c.SaveCommandTimeoutSeconds),
        Int("stopCommandTimeoutSeconds", c => c.StopCommandTimeoutSeconds),
        Text("kickCommand", c => c.KickCommand),
        Text("banCommand", c => c.BanCommand),
        Text("unbanCommand", c => c.UnbanCommand),
        Text("broadcastCommand", c => c.BroadcastCommand),
        Bool("compressBackups", c => c.CompressBackups),
    ];

    /// <summary>The key by its JSON name, or null when the config has none by that name.</summary>
    public static InstanceConfigKey? Find(string name) =>
        All.FirstOrDefault(k => string.Equals(k.Name, name, StringComparison.Ordinal));

    /// <summary>Every key of a config rendered as an entry.</summary>
    public static IReadOnlyList<ConfigEntry> Entries(InstanceConfig config) =>
        [.. All.Select(k => Entry(k, config))];

    public static ConfigEntry Entry(InstanceConfigKey key, InstanceConfig config) => new()
    {
        Key = key.Name,
        Type = key.Type,
        Value = key.Read(config),
        Settable = key.Settable,
    };

    private static InstanceConfigKey Text(string name, Func<InstanceConfig, string?> read, bool settable = true) =>
        new(name, "string", read, settable);

    private static InstanceConfigKey Int(string name, Func<InstanceConfig, int> read) =>
        new(name, "int", c => read(c).ToString(CultureInfo.InvariantCulture), true);

    private static InstanceConfigKey Bool(string name, Func<InstanceConfig, bool> read) =>
        new(name, "bool", c => Format(read(c)), true);

    private static string Format(bool value) => value ? "true" : "false";
}
