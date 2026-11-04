namespace TheKrystalShip.KGSM.Engine.Contracts;

/// <summary>
/// The <c>schemaVersion</c> each file the engine writes carries. A reader refuses a file whose version
/// differs from the one it knows rather than misreading it.
/// </summary>
public static class SchemaVersions
{
    public const int InstanceConfig = 1;

    public const int InstanceRegistry = 1;

    public const int LibraryRegistry = 1;

    public const int LibraryMarker = 1;

    public const int BackupManifest = 1;

    public const int TransferManifest = 1;

    public const int TransferLock = 1;

    public const int ImportStage = 1;

    /// <summary>The <c>schema_version</c> a blueprint file declares.</summary>
    public const int Blueprint = 1;
}
