using TheKrystalShip.KGSM.Engine.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Blueprints;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Placeholders;
using TheKrystalShip.KGSM.Engine.Settings;

namespace TheKrystalShip.KGSM.Engine.Instances;

/// <summary>Builds the config a fresh instance starts with: the blueprint's values, then the host's defaults.</summary>
public static class InstanceConfigFactory
{
    /// <exception cref="PlaceholderException">The blueprint's launch arguments name a value an instance does not have.</exception>
    public static InstanceConfig Create(
        Blueprint blueprint, EngineSettings settings, string id, string displayName, string backupsDirectory,
        DateTimeOffset installedAt, string installNonce)
    {
        ArgumentNullException.ThrowIfNull(blueprint);
        ArgumentNullException.ThrowIfNull(settings);

        NativeBlueprint? native = blueprint.Native;
        bool container = blueprint.Runtime == BlueprintRuntime.Container;
        InstancesSettings defaults = settings.Instances;

        return new InstanceConfig
        {
            SchemaVersion = SchemaVersions.InstanceConfig,
            Name = id,
            DisplayName = displayName,
            Blueprint = blueprint.Name,
            Runtime = blueprint.Runtime,
            InstallDatetime = installedAt,
            InstallNonce = installNonce,
            BackupsDirectory = backupsDirectory,
            Platform = native is { Platform.Length: > 0 } ? native.Platform : "linux",
            AutoUpdateBeforeStart = defaults.AutoUpdateBeforeStart,
            CpuPriority = "normal",
            MemoryCapMb = 0,
            MaintenanceWindows = defaults.MaintenanceWindows,
            Timezone = string.Empty,
            BackupRetention = 3,
            AnnounceLeadMinutes = defaults.AnnounceLeadMinutes,
            AnnounceMaintenanceMessage = defaults.AnnounceMaintenanceMessage,
            AnnounceMaintenanceCancelledMessage = defaults.AnnounceMaintenanceCancelledMessage,
            CrashRestart = true,
            CrashMaxRestarts = 5,
            StartupSuccessRegex = native?.StartupSuccessRegex ?? string.Empty,
            PlayerJoinedRegex = blueprint.PlayerJoinedRegex,
            PlayerLeftRegex = blueprint.PlayerLeftRegex,
            RconPort = blueprint.RconPort,
            RconPassword = blueprint.RconPassword,
            RconPollIntervalSeconds = blueprint.RconPollIntervalSeconds ?? 10,
            RconPlayersCommand = blueprint.RconPlayersCommand,
            RconPlayersRegex = blueprint.RconPlayersRegex,
            LevelName = native is { LevelName.Length: > 0 } ? native.LevelName : "default",
            ExecutableFile = native?.ExecutableFile ?? string.Empty,
            ExecutableSubdirectory = native?.ExecutableSubdirectory ?? string.Empty,
            ExecutableArguments = native is null
                ? string.Empty
                : LaunchArguments.FromBlueprint(native.ExecutableArguments, InstancePlaceholders.Keys),
            SteamAppId = native?.SteamAppId ?? 0,
            ClientSteamAppId = native?.ClientSteamAppId ?? 0,
            SteamcmdArguments = native?.SteamcmdArguments ?? string.Empty,
            IsSteamAccountRequired = native?.IsSteamAccountRequired ?? false,
            Ports = container ? ComposePorts.Derive(blueprint.Container!.Compose) : native?.Ports ?? string.Empty,
            EnableFirewallManagement = defaults.EnableFirewallManagement,
            EnablePortForwarding = defaults.EnablePortForwarding,
            DownloadTimeoutSeconds = settings.Downloads.TimeoutSeconds,
            StopCommand = native?.StopCommand ?? string.Empty,
            SaveCommand = native?.SaveCommand ?? string.Empty,
            SaveCommandTimeoutSeconds = defaults.SaveCommandTimeoutSeconds,
            StopCommandTimeoutSeconds = defaults.StopCommandTimeoutSeconds,
            KickCommand = blueprint.KickCommand,
            BanCommand = blueprint.BanCommand,
            UnbanCommand = blueprint.UnbanCommand,
            BroadcastCommand = blueprint.BroadcastCommand,
            CompressBackups = settings.Backups.Compress,
        };
    }
}
