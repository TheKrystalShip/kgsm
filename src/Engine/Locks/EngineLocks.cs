using TheKrystalShip.KGSM.Engine.Instances;
using TheKrystalShip.KGSM.Engine.Paths;

namespace TheKrystalShip.KGSM.Engine.Locks;

/// <summary>
/// The engine's locks. A write on one instance takes that instance's lock, so different servers install,
/// back up and update at once; a write on shared state (the registries, libraries, blueprints, settings)
/// takes the global lock. A held lock fails fast with <see cref="EngineBusyException"/>; nothing waits.
/// </summary>
/// <remarks>
/// A lock is an exclusive open of a file in the locks directory, which the kernel releases when the
/// holder disposes the handle or exits, so a crashed command never leaves a lock behind.
/// </remarks>
public sealed class EngineLocks(string locksDirectory)
{
    public const string GlobalName = "global";

    public EngineLocks(EnginePaths paths) : this(paths.LocksDirectory)
    {
    }

    /// <summary>Takes the lock for shared state.</summary>
    /// <exception cref="EngineBusyException">Another process or another caller holds it.</exception>
    public IDisposable AcquireGlobal() => Acquire(GlobalName, "global.lock");

    /// <summary>Takes one instance's lock.</summary>
    /// <exception cref="ArgumentException">The id is not a valid instance id.</exception>
    /// <exception cref="EngineBusyException">Another process or another caller holds it.</exception>
    public IDisposable AcquireInstance(string instanceId)
    {
        if (!InstanceIds.IsValid(instanceId))
            throw new ArgumentException($"'{instanceId}' is not a valid instance id.", nameof(instanceId));

        return Acquire(instanceId, $"instance-{instanceId}.lock");
    }

    private IDisposable Acquire(string name, string fileName)
    {
        Directory.CreateDirectory(locksDirectory);
        string path = Path.Combine(locksDirectory, fileName);

        try
        {
            return new Held(new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, bufferSize: 1));
        }
        catch (IOException)
        {
            throw new EngineBusyException(name);
        }
    }

    private sealed class Held(FileStream stream) : IDisposable
    {
        public void Dispose() => stream.Dispose();
    }
}
