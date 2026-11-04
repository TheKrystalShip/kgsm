using System.Text;

namespace TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

/// <summary>
/// Reads an instance's packed <c>maintenance_windows</c> value into windows, and packs windows back
/// into that value. This is the ecosystem's one implementation of the grammar and its one validator:
/// the API refuses a bad expression with the error this produces, and the scheduler fires on what
/// this returns, so the two cannot disagree about what an expression means.
/// </summary>
/// <remarks>
/// <para>
/// The grammar:
/// </para>
/// <code>
/// maintenance_windows := &lt;window&gt; [ ";" &lt;window&gt; ]*
/// &lt;window&gt;            := &lt;schedule&gt; "/" &lt;tasks&gt;
/// &lt;schedule&gt;          := &lt;appointment&gt; | &lt;interval&gt;
/// &lt;appointment&gt;       := "daily" "@" HH:MM
///                      | "weekly" "." &lt;dow&gt; "@" HH:MM
///                      | "monthly" "." &lt;dom&gt; "@" HH:MM
/// &lt;interval&gt;          := &lt;n&gt; &lt;unit&gt;                       ; 10m .. 30d
/// &lt;dow&gt;               := sun|mon|tue|wed|thu|fri|sat
/// &lt;dom&gt;               := 1..31                            ; clamped to the month's last day
/// &lt;unit&gt;              := m|h|d
/// &lt;tasks&gt;             := &lt;task&gt; [ "," &lt;task&gt; ]*
/// &lt;task&gt;              := backup | update | restart
/// </code>
/// <para>
/// The presence of <c>@</c> is the discriminator between the two schedule kinds. An empty value
/// means no maintenance — an absent window is off, and there is no token that spells "off".
/// </para>
/// <para>
/// <b>Bad input is data, never an exception.</b> Nothing here throws for anything a person can type;
/// a window that cannot be read comes back invalid, carrying the error, beside the windows that
/// read fine.
/// </para>
/// </remarks>
public static class MaintenanceWindowParser
{
    private const char WindowSeparator = ';';
    private const char TaskSeparator = ',';
    private const char ScheduleTaskSeparator = '/';
    private const char AppointmentMarker = '@';

    private static readonly MaintenanceTask[] CanonicalOrder =
        [MaintenanceTask.Backup, MaintenanceTask.Update, MaintenanceTask.Restart];

    /// <summary>
    /// Reads an instance's whole <c>maintenance_windows</c> value. Windows come back in the order
    /// they were written, each carrying its own validity: one unreadable window disables itself and
    /// leaves the rest of the list firing.
    /// </summary>
    /// <param name="packed">The packed value, or null/empty for an instance with no maintenance.</param>
    /// <returns>One entry per window written, valid or not. Empty when nothing is configured.</returns>
    public static IReadOnlyList<MaintenanceWindow> Parse(string? packed)
    {
        if (string.IsNullOrWhiteSpace(packed)) return [];

        var windows = new List<MaintenanceWindow>();
        var claimed = new HashSet<string>(StringComparer.Ordinal);

        foreach (string segment in packed.Split(WindowSeparator))
        {
            if (string.IsNullOrWhiteSpace(segment)) continue;

            MaintenanceWindow window = ParseWindow(segment);

            // Two identical schedules are one window, and the id is the schedule — so the second is
            // not a second appointment, it is a task set that belongs in the first.
            if (window.IsValid && !claimed.Add(window.Id))
                window = window.AsDuplicate(
                    $"'{window.Id}' is scheduled twice; merge the task sets into one window");

            windows.Add(window);
        }

        return windows;
    }

    /// <summary>
    /// Reads a single window expression, e.g. <c>weekly.sun@04:00/backup,update,restart</c>. The
    /// result is invalid rather than absent when the expression cannot be read.
    /// </summary>
    /// <param name="expression">One window expression.</param>
    /// <returns>The window, valid or carrying the reason it is not.</returns>
    public static MaintenanceWindow ParseWindow(string? expression)
    {
        string text = expression?.Trim() ?? string.Empty;
        if (text.Length == 0)
            return MaintenanceWindow.Invalid(string.Empty, string.Empty, "an empty window names no schedule and no tasks");

        int split = text.IndexOf(ScheduleTaskSeparator);
        if (split < 0)
            return MaintenanceWindow.Invalid(text, text,
                $"'{text}' is missing '/'; write the schedule, then '/', then the tasks it runs");

        string schedule = text[..split].Trim();
        string tasks = text[(split + 1)..].Trim();

        if (schedule.Length == 0)
            return MaintenanceWindow.Invalid(string.Empty, text, $"'{text}' names no schedule before '/'");

        if (!TryReadTasks(tasks, out List<MaintenanceTask> ordered, out string? taskError))
            return MaintenanceWindow.Invalid(schedule, text, taskError!);

        return schedule.Contains(AppointmentMarker)
            ? ReadAppointment(schedule, text, ordered)
            : ReadInterval(schedule, text, ordered);
    }

    /// <summary>
    /// Packs windows back into a <c>maintenance_windows</c> value — each window in canonical form,
    /// joined by <c>;</c>. The inverse of <see cref="Parse(string?)"/>.
    /// </summary>
    /// <param name="windows">The windows to pack.</param>
    /// <returns>The packed value; empty for an empty set.</returns>
    public static string Format(IEnumerable<MaintenanceWindow> windows)
    {
        ArgumentNullException.ThrowIfNull(windows);

        var packed = new StringBuilder();
        foreach (MaintenanceWindow window in windows)
        {
            if (packed.Length > 0) packed.Append(WindowSeparator);
            packed.Append(window.ToExpression());
        }

        return packed.ToString();
    }

    private static MaintenanceWindow ReadAppointment(string schedule, string text, List<MaintenanceTask> tasks)
    {
        int at = schedule.IndexOf(AppointmentMarker);
        if (schedule.IndexOf(AppointmentMarker, at + 1) >= 0)
            return MaintenanceWindow.Invalid(schedule, text, $"'{schedule}' carries more than one '@'");

        string cadence = schedule[..at].Trim().ToLowerInvariant();
        string time = schedule[(at + 1)..].Trim();

        if (!ScheduleClock.TryParseTime(time, out TimeOnly timeOfDay))
            return MaintenanceWindow.Invalid(schedule, text,
                $"'{time}' is not a time of day; write HH:MM between 00:00 and 23:59");

        string clock = $"{timeOfDay.Hour:00}:{timeOfDay.Minute:00}";

        if (cadence == "daily")
            return MaintenanceWindow.Appointment(
                $"daily@{clock}", text, AppointmentCadence.Daily, timeOfDay, null, null, tasks);

        if (cadence.StartsWith("weekly.", StringComparison.Ordinal))
        {
            string token = cadence["weekly.".Length..];
            if (!ScheduleClock.TryParseDayOfWeek(token, out DayOfWeek day))
                return MaintenanceWindow.Invalid(schedule, text,
                    $"'{token}' is not a day; write one of sun, mon, tue, wed, thu, fri, sat");

            return MaintenanceWindow.Appointment(
                $"weekly.{ScheduleClock.DayOfWeekToken(day)}@{clock}",
                text, AppointmentCadence.Weekly, timeOfDay, day, null, tasks);
        }

        if (cadence.StartsWith("monthly.", StringComparison.Ordinal))
        {
            string token = cadence["monthly.".Length..];
            if (!TryReadDayOfMonth(token, out int dayOfMonth))
                return MaintenanceWindow.Invalid(schedule, text,
                    $"'{token}' is not a day of the month; write a number from 1 to 31");

            return MaintenanceWindow.Appointment(
                $"monthly.{dayOfMonth}@{clock}",
                text, AppointmentCadence.Monthly, timeOfDay, null, dayOfMonth, tasks);
        }

        return MaintenanceWindow.Invalid(schedule, text,
            $"'{cadence}' is not an appointment; write daily@HH:MM, weekly.<dow>@HH:MM or monthly.<dom>@HH:MM");
    }

    private static MaintenanceWindow ReadInterval(string schedule, string text, List<MaintenanceTask> tasks)
    {
        string spec = schedule.ToLowerInvariant();

        IntervalUnit unit;
        switch (spec[^1])
        {
            case 'm': unit = IntervalUnit.Minutes; break;
            case 'h': unit = IntervalUnit.Hours; break;
            case 'd': unit = IntervalUnit.Days; break;
            default:
                return MaintenanceWindow.Invalid(schedule, text,
                    $"'{schedule}' is not an interval; write a number followed by m, h or d");
        }

        if (!TryReadCount(spec.AsSpan(0, spec.Length - 1), out long count))
            return MaintenanceWindow.Invalid(schedule, text,
                $"'{schedule}' is not an interval; write a number followed by m, h or d");

        // Bounded before the span is built: a count large enough to be rejected is also large enough
        // to overflow a TimeSpan.
        long ceiling = unit switch
        {
            IntervalUnit.Minutes => (long)ScheduleClock.MaximumInterval.TotalMinutes,
            IntervalUnit.Hours => (long)ScheduleClock.MaximumInterval.TotalHours,
            _ => (long)ScheduleClock.MaximumInterval.TotalDays,
        };

        if (count > ceiling)
            return MaintenanceWindow.Invalid(schedule, text,
                $"'{schedule}' is longer than the 30d maximum; write monthly.<dom>@HH:MM for a calendar month");

        TimeSpan interval = unit switch
        {
            IntervalUnit.Minutes => TimeSpan.FromMinutes(count),
            IntervalUnit.Hours => TimeSpan.FromHours(count),
            _ => TimeSpan.FromDays(count),
        };

        if (interval < ScheduleClock.MinimumInterval)
            return MaintenanceWindow.Invalid(schedule, text,
                $"'{schedule}' is shorter than the 10m minimum; write 10m or longer");

        string token = unit switch
        {
            IntervalUnit.Minutes => "m",
            IntervalUnit.Hours => "h",
            _ => "d",
        };

        return MaintenanceWindow.IntervalWindow($"{count}{token}", text, count, unit, interval, tasks);
    }

    private static bool TryReadTasks(string tasks, out List<MaintenanceTask> ordered, out string? error)
    {
        ordered = [];
        error = null;

        if (tasks.Length == 0)
        {
            error = "a window names at least one task: backup, update or restart";
            return false;
        }

        var named = new HashSet<MaintenanceTask>();
        foreach (string token in tasks.Split(TaskSeparator))
        {
            string trimmed = token.Trim();
            if (trimmed.Length == 0)
            {
                error = $"'{tasks}' carries an empty task between commas";
                return false;
            }

            if (!MaintenanceTaskExtensions.TryParse(trimmed, out MaintenanceTask task))
            {
                error = $"'{trimmed}' is not a task; write backup, update or restart";
                return false;
            }

            named.Add(task);
        }

        // Canonical order is a property of what the tasks are, not of how they were written: a backup
        // taken after an update archives the new build instead of the rollback point.
        foreach (MaintenanceTask task in CanonicalOrder)
        {
            if (named.Contains(task)) ordered.Add(task);
        }

        return true;
    }

    private static bool TryReadDayOfMonth(string token, out int dayOfMonth)
    {
        dayOfMonth = 0;
        if (!TryReadCount(token.AsSpan(), out long value)) return false;
        if (value is < 1 or > 31) return false;

        dayOfMonth = (int)value;
        return true;
    }

    private static bool TryReadCount(ReadOnlySpan<char> text, out long value)
    {
        value = 0;
        if (text.Length is 0 or > 9) return false;

        foreach (char c in text)
        {
            if (c is < '0' or > '9') return false;
            value = value * 10 + (c - '0');
        }

        return true;
    }
}
