namespace TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

/// <summary>
/// One maintenance window: a schedule plus the ordered set of tasks that run when it fires.
/// An instance holds a list of them, packed into its <c>maintenance_windows</c> config value.
/// </summary>
/// <remarks>
/// <para>
/// <b>A window's id is its schedule expression.</b> <c>weekly.sun@04:00</c> identifies it for
/// postpone, skip and announcement bookkeeping — unique within an instance, stable across edits to
/// the task set, and stored nowhere because it is derived. Editing the schedule produces a
/// <i>different</i> window, which is what makes anything announced about the old one retractable.
/// </para>
/// <para>
/// <b>Validity is per window.</b> A window that could not be read carries <see cref="IsValid"/>
/// <c>false</c> and the <see cref="Error"/> saying why, and it is returned alongside the windows
/// that did read — one unreadable window disables itself and nothing else. An invalid window has no
/// next fire, and the two facts together are what tell it apart from a window that is simply not due.
/// </para>
/// </remarks>
public sealed record class MaintenanceWindow
{
    private MaintenanceWindow(string id, string expression)
    {
        Id = id;
        Expression = expression;
    }

    /// <summary>
    /// The window's identity — its schedule expression in canonical form (lower-case, times
    /// zero-padded to <c>HH:MM</c>). An invalid window carries the schedule text as written, so it
    /// can still be named in a message.
    /// </summary>
    public string Id { get; private init; }

    /// <summary>The window exactly as it appears in the packed value, trimmed of surrounding space.</summary>
    public string Expression { get; private init; }

    /// <summary>
    /// Which schedule kind this window carries. An invalid window still answers, because the
    /// discriminator is the presence of <c>@</c> and that survives whatever else went wrong.
    /// </summary>
    public MaintenanceScheduleKind Kind { get; private init; }

    /// <summary>How often the appointment comes round. Null on an interval window.</summary>
    public AppointmentCadence? Cadence { get; private init; }

    /// <summary>The appointment's time of day, read in the instance's timezone. Null on an interval window.</summary>
    public TimeOnly? TimeOfDay { get; private init; }

    /// <summary>The day a <see cref="AppointmentCadence.Weekly"/> appointment falls on. Null otherwise.</summary>
    public DayOfWeek? DayOfWeek { get; private init; }

    /// <summary>
    /// The day a <see cref="AppointmentCadence.Monthly"/> appointment falls on, as written (1–31).
    /// A month shorter than this fires on its last day. Null on any other cadence.
    /// </summary>
    public int? DayOfMonth { get; private init; }

    /// <summary>The span between fires. Null on an appointment window.</summary>
    public TimeSpan? Interval { get; private init; }

    /// <summary>The interval as written, paired with <see cref="IntervalUnit"/>. Null on an appointment window.</summary>
    public long? IntervalCount { get; private init; }

    /// <summary>The unit the interval was written in. Null on an appointment window.</summary>
    public IntervalUnit? IntervalUnit { get; private init; }

    /// <summary>
    /// The tasks this window runs, in canonical order (<c>backup</c> → <c>update</c> → <c>restart</c>)
    /// with duplicates collapsed. Empty on an invalid window.
    /// </summary>
    public IReadOnlyList<MaintenanceTask> Tasks { get; private init; } = [];

    /// <summary>Whether the window was read successfully and will fire.</summary>
    public bool IsValid { get; private init; }

    /// <summary>What stopped the window being read, naming the offending text. Null when <see cref="IsValid"/>.</summary>
    public string? Error { get; private init; }

    /// <summary>Whether this window runs <paramref name="task"/>.</summary>
    /// <param name="task">The task to look for.</param>
    /// <returns><c>true</c> when the task is in <see cref="Tasks"/>.</returns>
    public bool Runs(MaintenanceTask task) => Tasks.Contains(task);

    /// <summary>
    /// The window in canonical form — <c>&lt;schedule&gt;/&lt;tasks&gt;</c>, tasks in canonical
    /// order. An invalid window renders as the text it was written with, since nothing was
    /// understood well enough to rewrite it.
    /// </summary>
    /// <returns>A single window expression, suitable for packing back into <c>maintenance_windows</c>.</returns>
    public string ToExpression() =>
        IsValid ? $"{Id}/{string.Join(",", Tasks.Select(t => t.ToToken()))}" : Expression;

    /// <inheritdoc/>
    public override string ToString() => ToExpression();

    internal static MaintenanceWindow Appointment(
        string id,
        string expression,
        AppointmentCadence cadence,
        TimeOnly timeOfDay,
        DayOfWeek? dayOfWeek,
        int? dayOfMonth,
        IReadOnlyList<MaintenanceTask> tasks) =>
        new(id, expression)
        {
            Kind = MaintenanceScheduleKind.Appointment,
            Cadence = cadence,
            TimeOfDay = timeOfDay,
            DayOfWeek = dayOfWeek,
            DayOfMonth = dayOfMonth,
            Tasks = tasks,
            IsValid = true,
        };

    internal static MaintenanceWindow IntervalWindow(
        string id,
        string expression,
        long count,
        IntervalUnit unit,
        TimeSpan interval,
        IReadOnlyList<MaintenanceTask> tasks) =>
        new(id, expression)
        {
            Kind = MaintenanceScheduleKind.Interval,
            Interval = interval,
            IntervalCount = count,
            IntervalUnit = unit,
            Tasks = tasks,
            IsValid = true,
        };

    internal static MaintenanceWindow Invalid(string id, string expression, string error) =>
        new(id, expression)
        {
            Kind = expression.Contains('@') ? MaintenanceScheduleKind.Appointment : MaintenanceScheduleKind.Interval,
            IsValid = false,
            Error = error,
        };

    internal MaintenanceWindow AsDuplicate(string error) =>
        this with { IsValid = false, Error = error, Tasks = [] };
}
