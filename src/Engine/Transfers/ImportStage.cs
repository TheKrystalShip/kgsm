using TheKrystalShip.KGSM.Engine.Contracts;
using TheKrystalShip.KGSM.Engine.Contracts.Libraries;
using TheKrystalShip.KGSM.Engine.Contracts.Transfers;

namespace TheKrystalShip.KGSM.Engine.Transfers;

/// <summary>
/// A staged import: a directory below the library it will land in, holding the manifest as it arrived,
/// the record of what the host held before the import began, one directory for the extracted tree and a
/// marker for each part that arrived whole.
/// </summary>
internal sealed record ImportStage(string Directory, LibraryRecord Library)
{
    /// <summary>The directory below a library root where staged imports live.</summary>
    public const string DirectoryName = ".kgsm-import";

    public string Id => System.IO.Path.GetFileName(Directory);

    public string ManifestFile => System.IO.Path.Combine(Directory, "manifest.json");

    public string MetaFile => System.IO.Path.Combine(Directory, "meta.json");

    public string TreeDirectory => System.IO.Path.Combine(Directory, "tree");

    public string PartsDirectory => System.IO.Path.Combine(Directory, "parts");

    /// <summary>The marker of a part that was extracted or loaded and checked.</summary>
    public string DoneMarker(string partId) => System.IO.Path.Combine(PartsDirectory, partId + ".done");

    public static string StagingRoot(LibraryRecord library) => System.IO.Path.Combine(library.Path, DirectoryName);

    public TransferManifest ReadManifest() =>
        ContractFile.Read(ManifestFile, EngineJsonContext.Default.TransferManifest, SchemaVersions.TransferManifest, m => m.SchemaVersion);

    public ImportStageMeta ReadMeta() =>
        ContractFile.Read(MetaFile, EngineJsonContext.Default.ImportStageMeta, SchemaVersions.ImportStage, m => m.SchemaVersion);

    public void Remove()
    {
        if (System.IO.Directory.Exists(Directory)) System.IO.Directory.Delete(Directory, recursive: true);
        string root = System.IO.Path.GetDirectoryName(Directory)!;
        if (System.IO.Directory.Exists(root) && !System.IO.Directory.EnumerateFileSystemEntries(root).Any()) System.IO.Directory.Delete(root);
    }
}
