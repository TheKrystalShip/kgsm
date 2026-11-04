using TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

namespace TheKrystalShip.KGSM.Engine.Tests.Scheduling;

/// <summary>
/// Locks the arithmetic every surface in the ecosystem times a maintenance window with — the leaf
/// that fires it and the API that previews it run this same code, so an answer that drifts here
/// drifts everywhere at once. The daylight-saving cases are the reason the comparison happens in UTC
/// rather than on the wall clock: a local comparison has two candidates in autumn and none in spring.
/// </summary>
public class ScheduleClockTests
{
    private static readonly TimeZoneInfo Madrid = TimeZoneInfo.FindSystemTimeZoneById("Europe/Madrid");

    private static MaintenanceWindow Window(string expression)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);
        Assert.True(window.IsValid, window.Error);
        return window;
    }

    private static DateTime Utc(string iso) =>
        DateTime.SpecifyKind(DateTime.Parse(iso, System.Globalization.CultureInfo.InvariantCulture), DateTimeKind.Utc);

    // --- Appointments ---

    [Fact]
    public void ADailyAppointment_FiresTheNextTimeTheClockReadsIt()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("daily@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T12:00:00"));

        Assert.Equal(Utc("2026-08-27T04:00:00"), next);
        Assert.Equal(DateTimeKind.Utc, next!.Value.Kind);
    }

    [Fact]
    public void ADailyAppointment_LaterToday_FiresToday()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("daily@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T01:00:00"));

        Assert.Equal(Utc("2026-08-26T04:00:00"), next);
    }

    [Fact]
    public void AnAppointment_FiresStrictlyAfterTheInstantGiven()
    {
        // Standing exactly on a fire asks for the one after it, never the one underfoot.
        DateTime? next = ScheduleClock.NextFire(
            Window("daily@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T04:00:00"));

        Assert.Equal(Utc("2026-08-27T04:00:00"), next);
    }

    [Fact]
    public void AWeeklyAppointment_FiresOnItsDay()
    {
        // 2026-08-26 is a Wednesday.
        DateTime? next = ScheduleClock.NextFire(
            Window("weekly.sun@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T00:00:00"));

        Assert.Equal(Utc("2026-08-30T04:00:00"), next);
        Assert.Equal(DayOfWeek.Sunday, next!.Value.DayOfWeek);
    }

    [Fact]
    public void AWeeklyAppointment_StandingOnAFire_SkipsAWholeWeek()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("weekly.sun@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-30T04:00:00"));

        Assert.Equal(Utc("2026-09-06T04:00:00"), next);
    }

    [Fact]
    public void AMonthlyAppointment_FiresOnItsDay()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("monthly.1@03:00/update,restart"), TimeZoneInfo.Utc, Utc("2026-01-01T04:00:00"));

        Assert.Equal(Utc("2026-02-01T03:00:00"), next);
    }

    // --- The monthly clamp ---

    [Fact]
    public void MonthlyOnThe31st_FiresOnTheLastDayOfAShorterMonth()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("monthly.31@03:00/backup"), TimeZoneInfo.Utc, Utc("2026-01-31T05:00:00"));

        Assert.Equal(Utc("2026-02-28T03:00:00"), next);
    }

    [Fact]
    public void MonthlyOnThe31st_FollowsTheLeapDay()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("monthly.31@03:00/backup"), TimeZoneInfo.Utc, Utc("2024-01-31T05:00:00"));

        Assert.Equal(Utc("2024-02-29T03:00:00"), next);
    }

    [Fact]
    public void MonthlyOnThe30th_ClampsInFebruaryAndNotOtherwise()
    {
        var fires = ScheduleClock.NextFires(
            Window("monthly.30@03:00/backup"), TimeZoneInfo.Utc, Utc("2026-01-30T05:00:00"), 3);

        Assert.Equal(
            [Utc("2026-02-28T03:00:00"), Utc("2026-03-30T03:00:00"), Utc("2026-04-30T03:00:00")],
            fires);
    }

    [Fact]
    public void MonthlyClamping_NeverSkipsAMonth()
    {
        // Clamping down is what makes every month carry exactly one fire.
        var fires = ScheduleClock.NextFires(
            Window("monthly.31@03:00/backup"), TimeZoneInfo.Utc, Utc("2026-01-01T00:00:00"), 12);

        Assert.Equal(12, fires.Count);
        Assert.Equal(Enumerable.Range(1, 12).ToArray(), fires.Select(f => f.Month).ToArray());
    }

    // --- Daylight saving ---

    [Fact]
    public void AnAppointment_HoldsItsWallClockTimeAcrossSpringForward()
    {
        // Europe/Madrid moves CET (+1) to CEST (+2) on 2026-03-29, so 04:00 local moves an hour
        // earlier in UTC and the day between the two fires is 23 hours long.
        var fires = ScheduleClock.NextFires(
            Window("daily@04:00/restart"), Madrid, Utc("2026-03-27T12:00:00"), 2);

        Assert.Equal([Utc("2026-03-28T03:00:00"), Utc("2026-03-29T02:00:00")], fires);
        Assert.Equal(TimeSpan.FromHours(23), fires[1] - fires[0]);
    }

    [Fact]
    public void AnAppointment_HoldsItsWallClockTimeAcrossFallBack()
    {
        // The reverse: 2026-10-25 is 25 hours long in Madrid.
        var fires = ScheduleClock.NextFires(
            Window("daily@04:00/restart"), Madrid, Utc("2026-10-23T12:00:00"), 2);

        Assert.Equal([Utc("2026-10-24T02:00:00"), Utc("2026-10-25T03:00:00")], fires);
        Assert.Equal(TimeSpan.FromHours(25), fires[1] - fires[0]);
    }

    [Fact]
    public void ATimeTheClockSkipsOver_FiresAtTheMomentItIsSkipped()
    {
        // 02:30 never happens in Madrid on 2026-03-29: the clock goes 01:59:59 CET to 03:00 CEST.
        // The window fires at the jump rather than being lost for the day.
        DateTime? next = ScheduleClock.NextFire(
            Window("daily@02:30/backup"), Madrid, Utc("2026-03-28T12:00:00"));

        Assert.Equal(Utc("2026-03-29T01:00:00"), next);
    }

    [Fact]
    public void ATimeTheClockReadsTwice_FiresTheFirstTime()
    {
        // 02:30 happens twice in Madrid on 2026-10-25. Taking the later one would hold a daily
        // window back a full hour on that one day.
        DateTime? next = ScheduleClock.NextFire(
            Window("daily@02:30/backup"), Madrid, Utc("2026-10-24T12:00:00"));

        Assert.Equal(Utc("2026-10-25T00:30:00"), next);
    }

    [Fact]
    public void ADailyAppointment_KeepsFiringOncePerLocalDayThroughATransition()
    {
        var fires = ScheduleClock.NextFires(
            Window("daily@04:00/restart"), Madrid, Utc("2026-03-27T12:00:00"), 4);

        var localDays = fires
            .Select(f => TimeZoneInfo.ConvertTimeFromUtc(f, Madrid))
            .ToArray();

        Assert.All(localDays, local => Assert.Equal(new TimeOnly(4, 0), TimeOnly.FromDateTime(local)));
        Assert.Equal([28, 29, 30, 31], localDays.Select(d => d.Day).ToArray());
    }

    // --- Intervals ---

    [Fact]
    public void AnInterval_FiresOnWholeBoundariesFromTheEpoch()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("6h/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T13:37:00"));

        Assert.Equal(Utc("2026-08-26T18:00:00"), next);
    }

    [Fact]
    public void AnIntervalStandingOnABoundary_FiresAtTheNextOne()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("6h/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T12:00:00"));

        Assert.Equal(Utc("2026-08-26T18:00:00"), next);
    }

    [Fact]
    public void TheShortestInterval_AlignsToTheEpochToo()
    {
        DateTime? next = ScheduleClock.NextFire(
            Window("10m/backup"), TimeZoneInfo.Utc, Utc("2026-08-26T13:37:00"));

        Assert.Equal(Utc("2026-08-26T13:40:00"), next);
    }

    [Theory]
    [InlineData("10m")]
    [InlineData("90m")]
    [InlineData("6h")]
    [InlineData("7h")]
    [InlineData("1d")]
    [InlineData("30d")]
    public void EveryInterval_LandsOnAWholeMultipleOfItselfFromTheEpoch(string spec)
    {
        MaintenanceWindow window = Window($"{spec}/backup");
        DateTime after = Utc("2026-08-26T13:37:19");

        DateTime next = ScheduleClock.NextFire(window, TimeZoneInfo.Utc, after)!.Value;

        Assert.Equal(0, (next - DateTime.UnixEpoch).Ticks % window.Interval!.Value.Ticks);
        Assert.True(next > after);
        Assert.True(next - after <= window.Interval.Value);
    }

    [Fact]
    public void AnInterval_IgnoresTheTimezoneEntirely()
    {
        MaintenanceWindow window = Window("6h/restart");
        DateTime after = Utc("2026-03-28T23:00:00");

        Assert.Equal(
            ScheduleClock.NextFire(window, TimeZoneInfo.Utc, after),
            ScheduleClock.NextFire(window, Madrid, after));
    }

    [Fact]
    public void AnInterval_KeepsItsFullWidthAcrossADaylightSavingTransition()
    {
        // An interval is timezone-free by construction, so a transition cannot shorten or stretch it.
        var fires = ScheduleClock.NextFires(Window("1d/backup"), Madrid, Utc("2026-03-27T12:00:00"), 3);

        Assert.Equal(TimeSpan.FromDays(1), fires[1] - fires[0]);
        Assert.Equal(TimeSpan.FromDays(1), fires[2] - fires[1]);
    }

    [Fact]
    public void IntervalBoundaries_AreTheSameOnEveryHostBecauseNothingIsAnchored()
    {
        // Two hosts asking at different moments inside the same window get the same answer.
        MaintenanceWindow window = Window("6h/restart");

        Assert.Equal(
            ScheduleClock.NextFire(window, TimeZoneInfo.Utc, Utc("2026-08-26T12:00:01")),
            ScheduleClock.NextFire(window, TimeZoneInfo.Utc, Utc("2026-08-26T17:59:59")));
    }

    [Fact]
    public void AnIntervalBeforeTheEpoch_RoundsDownRatherThanTowardZero()
    {
        // Truncating toward zero would skip a boundary on the negative side of the epoch.
        Assert.Equal(
            Utc("1970-01-01T00:00:00"),
            ScheduleClock.NextIntervalFire(TimeSpan.FromMinutes(10), Utc("1969-12-31T23:55:00")));

        Assert.Equal(
            Utc("1969-12-31T23:50:00"),
            ScheduleClock.NextIntervalFire(TimeSpan.FromMinutes(10), Utc("1969-12-31T23:45:00")));
    }

    [Fact]
    public void AnIntervalOfZeroOrLess_IsRefused()
    {
        Assert.Throws<ArgumentOutOfRangeException>(
            () => ScheduleClock.NextIntervalFire(TimeSpan.Zero, Utc("2026-08-26T13:37:00")));
        Assert.Throws<ArgumentOutOfRangeException>(
            () => ScheduleClock.NextIntervalFire(TimeSpan.FromMinutes(-5), Utc("2026-08-26T13:37:00")));
    }

    // --- Several fires ahead ---

    [Fact]
    public void NextFires_ReturnsAscendingDistinctInstants()
    {
        var fires = ScheduleClock.NextFires(
            Window("weekly.sun@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T00:00:00"), 4);

        Assert.Equal(
            [
                Utc("2026-08-30T04:00:00"),
                Utc("2026-09-06T04:00:00"),
                Utc("2026-09-13T04:00:00"),
                Utc("2026-09-20T04:00:00"),
            ],
            fires);
    }

    [Fact]
    public void NextFires_OfNone_IsEmpty()
    {
        Assert.Empty(ScheduleClock.NextFires(
            Window("daily@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T00:00:00"), 0));
    }

    [Fact]
    public void NextFires_RefusesANegativeCount()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => ScheduleClock.NextFires(
            Window("daily@04:00/restart"), TimeZoneInfo.Utc, Utc("2026-08-26T00:00:00"), -1));
    }

    // --- An invalid window has no next fire ---

    [Fact]
    public void AnInvalidWindow_HasNoNextFire()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("weekly.funday@04:00/restart");

        Assert.False(window.IsValid);
        Assert.Null(ScheduleClock.NextFire(window, TimeZoneInfo.Utc, Utc("2026-08-26T00:00:00")));
        Assert.Empty(ScheduleClock.NextFires(window, TimeZoneInfo.Utc, Utc("2026-08-26T00:00:00"), 5));
    }

    // --- Instants ---

    [Fact]
    public void AnInstantWithNoKind_IsReadAsUtc()
    {
        DateTime unspecified = new(2026, 8, 26, 13, 37, 0, DateTimeKind.Unspecified);

        Assert.Equal(
            Utc("2026-08-26T18:00:00"),
            ScheduleClock.NextIntervalFire(TimeSpan.FromHours(6), unspecified));
    }

    [Fact]
    public void ALocalInstant_IsConvertedRatherThanTakenAtFaceValue()
    {
        DateTime local = new DateTime(2026, 8, 26, 13, 37, 0, DateTimeKind.Utc).ToLocalTime();

        Assert.Equal(
            Utc("2026-08-26T18:00:00"),
            ScheduleClock.NextIntervalFire(TimeSpan.FromHours(6), local));
    }

    // --- Reading the pieces ---

    [Theory]
    [InlineData("04:00", 4, 0)]
    [InlineData("4:00", 4, 0)]
    [InlineData("00:00", 0, 0)]
    [InlineData("23:59", 23, 59)]
    [InlineData("9:5", 9, 5)]
    public void TryParseTime_ReadsWhatTheGrammarAllows(string text, int hour, int minute)
    {
        Assert.True(ScheduleClock.TryParseTime(text, out TimeOnly time));
        Assert.Equal(new TimeOnly(hour, minute), time);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("24:00")]
    [InlineData("23:60")]
    [InlineData("0400")]
    [InlineData("04:00:00")]
    [InlineData("004:00")]
    [InlineData("-4:00")]
    [InlineData("+4:00")]
    [InlineData("ab:cd")]
    public void TryParseTime_RefusesAnythingElse(string? text)
    {
        Assert.False(ScheduleClock.TryParseTime(text, out _));
    }

    [Theory]
    [InlineData(DayOfWeek.Sunday)]
    [InlineData(DayOfWeek.Monday)]
    [InlineData(DayOfWeek.Tuesday)]
    [InlineData(DayOfWeek.Wednesday)]
    [InlineData(DayOfWeek.Thursday)]
    [InlineData(DayOfWeek.Friday)]
    [InlineData(DayOfWeek.Saturday)]
    public void EveryDay_RoundTripsThroughItsToken(DayOfWeek day)
    {
        Assert.True(ScheduleClock.TryParseDayOfWeek(ScheduleClock.DayOfWeekToken(day), out DayOfWeek read));
        Assert.Equal(day, read);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("sunday")]
    [InlineData("su")]
    [InlineData("xyz")]
    public void AnUnknownDayToken_Fails_RatherThanBecomingSunday(string? token)
    {
        Assert.False(ScheduleClock.TryParseDayOfWeek(token, out _));
    }

    [Fact]
    public void ResolveTimezone_FindsAnIanaId()
    {
        Assert.Equal(Madrid, ScheduleClock.ResolveTimezone("Europe/Madrid"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("Mars/Olympus_Mons")]
    public void ResolveTimezone_FallsBackToTheHostsOwn(string? iana)
    {
        Assert.Equal(TimeZoneInfo.Local, ScheduleClock.ResolveTimezone(iana));
    }

    // --- The bounds the grammar enforces are the clock's own ---

    [Fact]
    public void TheIntervalBounds_AreOneDefinition()
    {
        Assert.Equal(TimeSpan.FromMinutes(10), ScheduleClock.MinimumInterval);
        Assert.Equal(TimeSpan.FromDays(30), ScheduleClock.MaximumInterval);
    }
}
