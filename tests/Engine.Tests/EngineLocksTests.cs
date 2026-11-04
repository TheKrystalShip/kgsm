using TheKrystalShip.KGSM.Engine.Locks;

namespace TheKrystalShip.KGSM.Engine.Tests;

public class EngineLocksTests
{
    private static EngineLocks NewLocks() => new(Sandbox.Create().Paths);

    [Fact]
    public void AHeldInstanceLock_FailsFast_WithABusyError()
    {
        EngineLocks locks = NewLocks();
        using IDisposable held = locks.AcquireInstance("factorio-1");

        var busy = Assert.Throws<EngineBusyException>(() => locks.AcquireInstance("factorio-1"));

        Assert.Equal("busy", busy.Code);
        Assert.Equal("factorio-1", busy.LockName);
    }

    [Fact]
    public void ADisposedLock_CanBeTakenAgain()
    {
        EngineLocks locks = NewLocks();
        locks.AcquireInstance("a").Dispose();

        using IDisposable again = locks.AcquireInstance("a");
    }

    [Fact]
    public void DifferentInstances_LockIndependently()
    {
        EngineLocks locks = NewLocks();

        using IDisposable one = locks.AcquireInstance("one");
        using IDisposable two = locks.AcquireInstance("two");
    }

    [Fact]
    public void TheGlobalLock_IsExclusive_AndIndependentOfInstanceLocks()
    {
        EngineLocks locks = NewLocks();
        using IDisposable global = locks.AcquireGlobal();
        using IDisposable instance = locks.AcquireInstance("one");

        Assert.Throws<EngineBusyException>(() => locks.AcquireGlobal());
    }

    [Fact]
    public void TwoEnginesOverOneDirectory_ExcludeEachOther()
    {
        var sandbox = Sandbox.Create();
        using IDisposable held = new EngineLocks(sandbox.Paths).AcquireGlobal();

        Assert.Throws<EngineBusyException>(() => new EngineLocks(sandbox.Paths).AcquireGlobal());
    }

    [Theory]
    [InlineData("")]
    [InlineData("../escape")]
    [InlineData("a/b")]
    [InlineData(".hidden")]
    public void AnInvalidInstanceId_IsRefused_BeforeAnyFileIsMade(string id)
    {
        Assert.Throws<ArgumentException>(() => NewLocks().AcquireInstance(id));
    }
}
