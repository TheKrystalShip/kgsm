using System.Text.Json;
using System.Text.Json.Serialization.Metadata;

namespace TheKrystalShip.KGSM.Engine;

/// <summary>
/// Reads and writes the JSON files the engine owns through registered types. A reader checks the file's
/// <c>schemaVersion</c> before it reads the rest, so a file of a version it does not know is refused
/// rather than misread.
/// </summary>
internal static class ContractFile
{
    /// <summary>The one field read before the rest.</summary>
    internal sealed record SchemaProbe(int? SchemaVersion);

    /// <summary>Reads a file that must exist.</summary>
    /// <exception cref="UnsupportedSchemaVersionException">The version is absent or not <paramref name="expectedVersion"/>.</exception>
    /// <exception cref="EngineFormatException">The file is not JSON of the expected shape.</exception>
    public static T Read<T>(string path, JsonTypeInfo<T> typeInfo, int expectedVersion, Func<T, int> versionOf)
        where T : class
    {
        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new EngineFormatException(path, "the file cannot be read", ex);
        }

        try
        {
            SchemaProbe? probe = JsonSerializer.Deserialize(bytes, InternalJsonContext.Default.SchemaProbe);
            if (probe?.SchemaVersion != expectedVersion)
                throw new UnsupportedSchemaVersionException(path, probe?.SchemaVersion, expectedVersion);

            T value = JsonSerializer.Deserialize(bytes, typeInfo)
                ?? throw new EngineFormatException(path, "the file holds null");
            return versionOf(value) == expectedVersion
                ? value
                : throw new UnsupportedSchemaVersionException(path, versionOf(value), expectedVersion);
        }
        catch (JsonException ex)
        {
            throw new EngineFormatException(path, ex.Message, ex);
        }
    }

    /// <summary>Reads a file, or returns null when it does not exist.</summary>
    public static T? ReadIfExists<T>(string path, JsonTypeInfo<T> typeInfo, int expectedVersion, Func<T, int> versionOf)
        where T : class =>
        File.Exists(path) ? Read(path, typeInfo, expectedVersion, versionOf) : null;

    /// <summary>
    /// Writes a file whole: the content is staged beside it and renamed into place, so a reader sees the old
    /// file or the new one and never a partial.
    /// </summary>
    public static void Write<T>(string path, T value, JsonTypeInfo<T> typeInfo) =>
        WriteBytes(path, JsonSerializer.SerializeToUtf8Bytes(value, typeInfo));

    /// <summary>Writes already-serialized content the way <see cref="Write{T}"/> does.</summary>
    public static void WriteBytes(string path, byte[] content)
    {
        string directory = Path.GetDirectoryName(Path.GetFullPath(path))!;
        Directory.CreateDirectory(directory);

        string staged = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(staged, content);
            File.Move(staged, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(staged)) File.Delete(staged);
        }
    }
}
