using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>One key of the instance config: its JSON name, its type, how to read it as text and whether <c>config set</c> may change it.</summary>
public sealed record InstanceConfigKey(
    string Name, string Type, Func<InstanceConfig, string?> Read, bool Settable, Func<InstanceConfig, string, InstanceConfig>? Write = null);

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
        Fixed("name", "string", c => c.Name),
        Text("displayName", c => c.DisplayName, (c, v) => c with { DisplayName = v }),
        Fixed("blueprint", "string", c => c.Blueprint),
        Fixed("runtime", "string", c => c.Runtime == BlueprintRuntime.Native ? "native" : "container"),
        Fixed("installDatetime", "datetime", c => c.InstallDatetime?.ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture)),
        Fixed("installNonce", "string", c => c.InstallNonce),
        Fixed("backupsDirectory", "string", c => c.BackupsDirectory),
        Fixed("platform", "string", c => c.Platform),
        Bool("autoUpdateBeforeStart", c => c.AutoUpdateBeforeStart, (c, v) => c with { AutoUpdateBeforeStart = v }),
        Text("cpuPriority", c => c.CpuPriority, (c, v) => c with { CpuPriority = v }),
        Int("memoryCapMb", c => c.MemoryCapMb, (c, v) => c with { MemoryCapMb = v }),
        Text("maintenanceWindows", c => c.MaintenanceWindows, (c, v) => c with { MaintenanceWindows = v }),
        Fixed("maintenanceWindowsAuthor", "string", c => c.MaintenanceWindowsAuthor),
        Fixed("maintenanceWindowsAuthorName", "string", c => c.MaintenanceWindowsAuthorName),
        Text("timezone", c => c.Timezone, (c, v) => c with { Timezone = v }),
        Int("backupRetention", c => c.BackupRetention, (c, v) => c with { BackupRetention = v }),
        Text("announceLeadMinutes", c => c.AnnounceLeadMinutes, (c, v) => c with { AnnounceLeadMinutes = v }),
        Text("announceMaintenanceMessage", c => c.AnnounceMaintenanceMessage, (c, v) => c with { AnnounceMaintenanceMessage = v }),
        Text("announceMaintenanceCancelledMessage", c => c.AnnounceMaintenanceCancelledMessage, (c, v) => c with { AnnounceMaintenanceCancelledMessage = v }),
        Bool("crashRestart", c => c.CrashRestart, (c, v) => c with { CrashRestart = v }),
        Int("crashMaxRestarts", c => c.CrashMaxRestarts, (c, v) => c with { CrashMaxRestarts = v }),
        Text("startupSuccessRegex", c => c.StartupSuccessRegex, (c, v) => c with { StartupSuccessRegex = v }),
        Text("playerJoinedRegex", c => c.PlayerJoinedRegex, (c, v) => c with { PlayerJoinedRegex = v }),
        Text("playerLeftRegex", c => c.PlayerLeftRegex, (c, v) => c with { PlayerLeftRegex = v }),
        new("rconPort", "int", c => c.RconPort?.ToString(CultureInfo.InvariantCulture), true,
            (c, v) => c with { RconPort = v.Length == 0 ? null : int.Parse(v, CultureInfo.InvariantCulture) }),
        Text("rconPassword", c => c.RconPassword, (c, v) => c with { RconPassword = v }),
        Int("rconPollIntervalSeconds", c => c.RconPollIntervalSeconds, (c, v) => c with { RconPollIntervalSeconds = v }),
        Text("rconPlayersCommand", c => c.RconPlayersCommand, (c, v) => c with { RconPlayersCommand = v }),
        Text("rconPlayersRegex", c => c.RconPlayersRegex, (c, v) => c with { RconPlayersRegex = v }),
        Text("levelName", c => c.LevelName, (c, v) => c with { LevelName = v }),
        Fixed("executableFile", "string", c => c.ExecutableFile),
        Fixed("executableSubdirectory", "string", c => c.ExecutableSubdirectory),
        Text("executableArguments", c => c.ExecutableArguments, (c, v) => c with { ExecutableArguments = v }),
        Fixed("steamAppId", "int", c => c.SteamAppId.ToString(CultureInfo.InvariantCulture)),
        Fixed("clientSteamAppId", "int", c => c.ClientSteamAppId.ToString(CultureInfo.InvariantCulture)),
        Text("steamcmdArguments", c => c.SteamcmdArguments, (c, v) => c with { SteamcmdArguments = v }),
        Fixed("isSteamAccountRequired", "bool", c => Format(c.IsSteamAccountRequired)),
        Fixed("ports", "string", c => c.Ports),
        Fixed("enableFirewallManagement", "bool", c => Format(c.EnableFirewallManagement)),
        Bool("enablePortForwarding", c => c.EnablePortForwarding, (c, v) => c with { EnablePortForwarding = v }),
        Int("downloadTimeoutSeconds", c => c.DownloadTimeoutSeconds, (c, v) => c with { DownloadTimeoutSeconds = v }),
        Text("stopCommand", c => c.StopCommand, (c, v) => c with { StopCommand = v }),
        Text("saveCommand", c => c.SaveCommand, (c, v) => c with { SaveCommand = v }),
        Int("saveCommandTimeoutSeconds", c => c.SaveCommandTimeoutSeconds, (c, v) => c with { SaveCommandTimeoutSeconds = v }),
        Int("stopCommandTimeoutSeconds", c => c.StopCommandTimeoutSeconds, (c, v) => c with { StopCommandTimeoutSeconds = v }),
        Text("kickCommand", c => c.KickCommand, (c, v) => c with { KickCommand = v }),
        Text("banCommand", c => c.BanCommand, (c, v) => c with { BanCommand = v }),
        Text("unbanCommand", c => c.UnbanCommand, (c, v) => c with { UnbanCommand = v }),
        Text("broadcastCommand", c => c.BroadcastCommand, (c, v) => c with { BroadcastCommand = v }),
        Bool("compressBackups", c => c.CompressBackups, (c, v) => c with { CompressBackups = v }),
        Fixed("note", "string", c => c.Note),
        Fixed("noteUpdatedBy", "string", c => c.NoteUpdatedBy),
        Fixed("noteUpdatedAt", "datetime", c => c.NoteUpdatedAt?.ToString("yyyy-MM-ddTHH:mm:sszzz", CultureInfo.InvariantCulture)),
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

    private static InstanceConfigKey Fixed(string name, string type, Func<InstanceConfig, string?> read) =>
        new(name, type, read, false);

    private static InstanceConfigKey Text(string name, Func<InstanceConfig, string?> read, Func<InstanceConfig, string, InstanceConfig> write) =>
        new(name, "string", read, true, write);

    private static InstanceConfigKey Int(string name, Func<InstanceConfig, int> read, Func<InstanceConfig, int, InstanceConfig> write) =>
        new(name, "int", c => read(c).ToString(CultureInfo.InvariantCulture), true,
            (c, v) => write(c, int.Parse(v, CultureInfo.InvariantCulture)));

    private static InstanceConfigKey Bool(string name, Func<InstanceConfig, bool> read, Func<InstanceConfig, bool, InstanceConfig> write) =>
        new(name, "bool", c => Format(read(c)), true, (c, v) => write(c, v == "true"));

    private static string Format(bool value) => value ? "true" : "false";
}
