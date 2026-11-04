namespace TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

/// <summary>
/// Which of the two schedule kinds a window carries. The presence of <c>@</c> in the schedule
/// expression is the discriminator.
/// </summary>
public enum MaintenanceScheduleKind
{
    /// <summary>
    /// A wall-clock appointment — a time of day, read in the instance's timezone, so it holds its
    /// place against daylight-saving transitions.
    /// </summary>
    Appointment = 0,

    /// <summary>
    /// A fixed span between fires, aligned to whole multiples from the Unix epoch. It carries no
    /// time of day and ignores the timezone by construction, so every host answers identically and
    /// nothing has to be anchored at install time.
    /// </summary>
    Interval = 1,
}

/// <summary>
/// How often an <see cref="MaintenanceScheduleKind.Appointment"/> comes round.
/// </summary>
public enum AppointmentCadence
{
    /// <summary>Every day at the window's time of day.</summary>
    Daily = 0,

    /// <summary>One named day of the week.</summary>
    Weekly = 1,

    /// <summary>One day of the month, clamped down to the month's last day.</summary>
    Monthly = 2,
}

/// <summary>
/// The unit an interval is written in. A window keeps the unit it was written with, so the schedule
/// expression — which is the window's id — renders back exactly as stored and identity survives an
/// edit that does not touch the schedule.
/// </summary>
public enum IntervalUnit
{
    /// <summary>Minutes — the <c>m</c> token.</summary>
    Minutes = 0,

    /// <summary>Hours — the <c>h</c> token.</summary>
    Hours = 1,

    /// <summary>Days — the <c>d</c> token.</summary>
    Days = 2,
}
