namespace TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

/// <summary>
/// Wall-clock arithmetic for maintenance windows. Pure and side-effect free, so a host's timing can
/// be tested without a host, a watchdog, or a clock that actually advances.
/// </summary>
/// <remarks>
/// <para>
/// Every method answers "when does this next fire, strictly after the given instant" — never "is it
/// due now". A schedule is due when a target computed on an earlier tick has been reached, which is
/// why a caller stores the target rather than recomputing it each tick and comparing to the present.
/// </para>
/// <para>
/// Instants are UTC in and UTC out. An appointment is resolved by converting each candidate wall
/// clock time to UTC and comparing there, so a daylight-saving transition moves the fire by the
/// offset it changed and never by a day.
/// </para>
/// </remarks>
public static class ScheduleClock
{
    /// <summary>The shortest interval a window may carry.</summary>
    public static readonly TimeSpan MinimumInterval = TimeSpan.FromMinutes(10);

    /// <summary>The longest interval a window may carry.</summary>
    public static readonly TimeSpan MaximumInterval = TimeSpan.FromDays(30);

    /// <summary>
    /// The next moment <paramref name="window"/> fires, strictly after <paramref name="afterUtc"/>.
    /// Null for a window that could not be read — an invalid window has no next fire, and saying so
    /// is what distinguishes it from one that is simply not due yet.
    /// </summary>
    /// <param name="window">The window to time.</param>
    /// <param name="timezone">The instance's timezone, used for appointments and ignored by intervals.</param>
    /// <param name="afterUtc">The instant to search forward from.</param>
    /// <returns>The next fire in UTC, or <c>null</c> when the window is invalid.</returns>
    public static DateTime? NextFire(MaintenanceWindow window, TimeZoneInfo timezone, DateTime afterUtc)
    {
        ArgumentNullException.ThrowIfNull(window);
        ArgumentNullException.ThrowIfNull(timezone);

        if (!window.IsValid) return null;

        if (window.Kind == MaintenanceScheduleKind.Interval)
            return NextIntervalFire(window.Interval!.Value, afterUtc);

        return NextAppointmentFire(
            window.Cadence!.Value,
            window.TimeOfDay!.Value,
            window.DayOfWeek,
            window.DayOfMonth,
            timezone,
            afterUtc);
    }

    /// <summary>
    /// The next <paramref name="count"/> moments <paramref name="window"/> fires, each strictly
    /// after the one before it. Empty for an invalid window.
    /// </summary>
    /// <param name="window">The window to time.</param>
    /// <param name="timezone">The instance's timezone, used for appointments and ignored by intervals.</param>
    /// <param name="afterUtc">The instant to search forward from.</param>
    /// <param name="count">How many fires to produce.</param>
    /// <returns>Ascending UTC instants, at most <paramref name="count"/> of them.</returns>
    /// <exception cref="ArgumentOutOfRangeException"><paramref name="count"/> is negative.</exception>
    public static IReadOnlyList<DateTime> NextFires(
        MaintenanceWindow window, TimeZoneInfo timezone, DateTime afterUtc, int count)
    {
        ArgumentNullException.ThrowIfNull(window);
        ArgumentNullException.ThrowIfNull(timezone);
        ArgumentOutOfRangeException.ThrowIfNegative(count);

        var fires = new List<DateTime>(count);
        DateTime cursor = afterUtc;

        for (int i = 0; i < count; i++)
        {
            DateTime? next = NextFire(window, timezone, cursor);
            if (next is null) break;
            fires.Add(next.Value);
            cursor = next.Value;
        }

        return fires;
    }

    /// <summary>
    /// The next whole <paramref name="interval"/> boundary after <paramref name="afterUtc"/>,
    /// measured from the Unix epoch in UTC. An interval carries no time of day and no timezone by
    /// construction: "every 6 hours" is an interval, not an appointment, so every host answers
    /// identically and nothing has to be anchored at install time.
    /// </summary>
    /// <param name="interval">The span between fires.</param>
    /// <param name="afterUtc">The instant to search forward from.</param>
    /// <returns>The next boundary, in UTC.</returns>
    /// <exception cref="ArgumentOutOfRangeException"><paramref name="interval"/> is zero or negative.</exception>
    public static DateTime NextIntervalFire(TimeSpan interval, DateTime afterUtc)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(interval, TimeSpan.Zero, nameof(interval));

        long sinceEpoch = NormalizeUtc(afterUtc).Ticks - DateTime.UnixEpoch.Ticks;
        long width = interval.Ticks;

        // Floor division: truncation toward zero would round the wrong way before the epoch.
        long completed = sinceEpoch / width;
        if (sinceEpoch < 0 && completed * width != sinceEpoch) completed--;

        return DateTime.UnixEpoch.AddTicks((completed + 1) * width);
    }

    /// <summary>The next daily appointment at <paramref name="timeOfDay"/>, in UTC.</summary>
    /// <param name="timeOfDay">The wall clock time in <paramref name="timezone"/>.</param>
    /// <param name="timezone">The timezone the appointment is read in.</param>
    /// <param name="afterUtc">The instant to search forward from.</param>
    /// <returns>The next fire, in UTC.</returns>
    public static DateTime NextDailyFire(TimeOnly timeOfDay, TimeZoneInfo timezone, DateTime afterUtc)
        => NextAppointmentFire(AppointmentCadence.Daily, timeOfDay, null, null, timezone, afterUtc);

    /// <summary>The next weekly appointment on <paramref name="day"/> at <paramref name="timeOfDay"/>, in UTC.</summary>
    /// <param name="timeOfDay">The wall clock time in <paramref name="timezone"/>.</param>
    /// <param name="day">The day of the week the appointment falls on.</param>
    /// <param name="timezone">The timezone the appointment is read in.</param>
    /// <param name="afterUtc">The instant to search forward from.</param>
    /// <returns>The next fire, in UTC.</returns>
    public static DateTime NextWeeklyFire(TimeOnly timeOfDay, DayOfWeek day, TimeZoneInfo timezone, DateTime afterUtc)
        => NextAppointmentFire(AppointmentCadence.Weekly, timeOfDay, day, null, timezone, afterUtc);

    /// <summary>
    /// The next monthly appointment on <paramref name="dayOfMonth"/> at <paramref name="timeOfDay"/>,
    /// in UTC. A month shorter than <paramref name="dayOfMonth"/> fires on its last day — clamping
    /// down is the only rule that never surprises, since the alternative skips the month entirely.
    /// </summary>
    /// <param name="timeOfDay">The wall clock time in <paramref name="timezone"/>.</param>
    /// <param name="dayOfMonth">The day of the month, 1–31.</param>
    /// <param name="timezone">The timezone the appointment is read in.</param>
    /// <param name="afterUtc">The instant to search forward from.</param>
    /// <returns>The next fire, in UTC.</returns>
    public static DateTime NextMonthlyFire(TimeOnly timeOfDay, int dayOfMonth, TimeZoneInfo timezone, DateTime afterUtc)
        => NextAppointmentFire(AppointmentCadence.Monthly, timeOfDay, null, dayOfMonth, timezone, afterUtc);

    /// <summary>
    /// Reads <c>HH:MM</c>. One or two digits are accepted for each half; the hour must be 0–23 and
    /// the minute 0–59. Anything else fails rather than resolving to a default.
    /// </summary>
    /// <param name="hhmm">The text to read.</param>
    /// <param name="timeOfDay">The time it names, when this returns <c>true</c>.</param>
    /// <returns><c>true</c> when <paramref name="hhmm"/> names a time of day.</returns>
    public static bool TryParseTime(string? hhmm, out TimeOnly timeOfDay)
    {
        timeOfDay = default;
        if (string.IsNullOrWhiteSpace(hhmm)) return false;

        int colon = hhmm.IndexOf(':');
        if (colon < 0 || hhmm.IndexOf(':', colon + 1) >= 0) return false;

        if (!TryReadSmallNumber(hhmm.AsSpan(0, colon), out int hour)) return false;
        if (!TryReadSmallNumber(hhmm.AsSpan(colon + 1), out int minute)) return false;
        if (hour > 23 || minute > 59) return false;

        timeOfDay = new TimeOnly(hour, minute);
        return true;
    }

    /// <summary>
    /// Reads a three-letter day token (<c>sun</c>…<c>sat</c>), case-insensitively. An unrecognised
    /// token fails rather than resolving to a default — a typo that silently became Sunday would
    /// schedule maintenance on a day nobody asked for.
    /// </summary>
    /// <param name="token">The text to read.</param>
    /// <param name="day">The day it names, when this returns <c>true</c>.</param>
    /// <returns><c>true</c> when <paramref name="token"/> names a day.</returns>
    public static bool TryParseDayOfWeek(string? token, out DayOfWeek day)
    {
        day = System.DayOfWeek.Sunday;
        if (string.IsNullOrWhiteSpace(token)) return false;

        switch (token.Trim().ToLowerInvariant())
        {
            case "sun": day = System.DayOfWeek.Sunday; return true;
            case "mon": day = System.DayOfWeek.Monday; return true;
            case "tue": day = System.DayOfWeek.Tuesday; return true;
            case "wed": day = System.DayOfWeek.Wednesday; return true;
            case "thu": day = System.DayOfWeek.Thursday; return true;
            case "fri": day = System.DayOfWeek.Friday; return true;
            case "sat": day = System.DayOfWeek.Saturday; return true;
            default: return false;
        }
    }

    /// <summary>The three-letter token the grammar writes <paramref name="day"/> as.</summary>
    /// <param name="day">The day to render.</param>
    /// <returns><c>sun</c> … <c>sat</c>.</returns>
    public static string DayOfWeekToken(DayOfWeek day) => day switch
    {
        System.DayOfWeek.Monday => "mon",
        System.DayOfWeek.Tuesday => "tue",
        System.DayOfWeek.Wednesday => "wed",
        System.DayOfWeek.Thursday => "thu",
        System.DayOfWeek.Friday => "fri",
        System.DayOfWeek.Saturday => "sat",
        _ => "sun",
    };

    /// <summary>
    /// Resolves an IANA timezone id. An empty or unknown id yields the host's own timezone, which is
    /// the answer a host with nothing configured already lives by.
    /// </summary>
    /// <param name="iana">The IANA id, e.g. <c>Europe/Madrid</c>.</param>
    /// <returns>The timezone, or the host's local timezone.</returns>
    public static TimeZoneInfo ResolveTimezone(string? iana)
    {
        if (string.IsNullOrWhiteSpace(iana)) return TimeZoneInfo.Local;
        try { return TimeZoneInfo.FindSystemTimeZoneById(iana); }
        catch { return TimeZoneInfo.Local; }
    }

    /// <summary>
    /// Walks candidate local dates forward from the day <paramref name="afterUtc"/> falls on, and
    /// returns the first whose wall clock time converts to an instant strictly after it. Comparing
    /// in UTC rather than in local time is what keeps the answer right across a daylight-saving
    /// transition, where a local comparison has two candidates or none.
    /// </summary>
    private static DateTime NextAppointmentFire(
        AppointmentCadence cadence,
        TimeOnly timeOfDay,
        DayOfWeek? dayOfWeek,
        int? dayOfMonth,
        TimeZoneInfo timezone,
        DateTime afterUtc)
    {
        DateTime after = NormalizeUtc(afterUtc);
        DateTime afterLocal = TimeZoneInfo.ConvertTimeFromUtc(after, timezone);
        DateOnly date = DateOnly.FromDateTime(afterLocal);

        // A monthly appointment on the 31st is the widest gap between candidate dates: two calendar
        // months. The bound exists so a defect cannot spin, never because a fire can be this far out.
        for (int i = 0; i < 400; i++, date = date.AddDays(1))
        {
            if (!Matches(date, cadence, dayOfWeek, dayOfMonth)) continue;

            DateTime fire = ToUtc(date.ToDateTime(timeOfDay, DateTimeKind.Unspecified), timezone);
            if (fire > after) return fire;
        }

        throw new InvalidOperationException(
            $"No {cadence} appointment falls within 400 days of {after:O} in {timezone.Id}.");
    }

    private static bool Matches(DateOnly date, AppointmentCadence cadence, DayOfWeek? dayOfWeek, int? dayOfMonth)
        => cadence switch
        {
            AppointmentCadence.Daily => true,
            AppointmentCadence.Weekly => date.DayOfWeek == dayOfWeek,
            AppointmentCadence.Monthly =>
                date.Day == Math.Min(dayOfMonth ?? 1, DateTime.DaysInMonth(date.Year, date.Month)),
            _ => false,
        };

    /// <summary>
    /// Converts a wall clock time to the instant it names. A time the clock skips over resolves to
    /// the moment it is skipped; a time the clock reads twice resolves to the first of the two, so a
    /// daily appointment is never held back an hour by a transition.
    /// </summary>
    private static DateTime ToUtc(DateTime local, TimeZoneInfo timezone)
    {
        if (timezone.IsInvalidTime(local))
        {
            DateTime probe = local;
            for (int i = 0; i < 24 * 60 && timezone.IsInvalidTime(probe); i++)
                probe = probe.AddMinutes(1);
            local = probe;
        }

        if (timezone.IsAmbiguousTime(local))
        {
            TimeSpan[] offsets = timezone.GetAmbiguousTimeOffsets(local);
            TimeSpan earliest = offsets[0];
            foreach (TimeSpan offset in offsets)
                if (offset > earliest) earliest = offset;

            return DateTime.SpecifyKind(local - earliest, DateTimeKind.Utc);
        }

        return TimeZoneInfo.ConvertTimeToUtc(local, timezone);
    }

    private static DateTime NormalizeUtc(DateTime instant) => instant.Kind switch
    {
        DateTimeKind.Local => instant.ToUniversalTime(),
        _ => DateTime.SpecifyKind(instant, DateTimeKind.Utc),
    };

    private static bool TryReadSmallNumber(ReadOnlySpan<char> text, out int value)
    {
        value = 0;
        if (text.Length is 0 or > 2) return false;

        foreach (char c in text)
        {
            if (c is < '0' or > '9') return false;
            value = value * 10 + (c - '0');
        }

        return true;
    }
}
