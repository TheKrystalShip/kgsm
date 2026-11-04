using TheKrystalShip.KGSM.Engine.Contracts.Scheduling;

namespace TheKrystalShip.KGSM.Engine.Tests.Scheduling;

/// <summary>
/// Locks the <c>maintenance_windows</c> grammar. This parser is the ecosystem's only implementation
/// of it and its only validator — the API refuses a bad expression with the error produced here and
/// the scheduler fires on what is returned here — so the shape of a window, the canonical order of
/// its tasks, and the exact set of things that are rejected are all contract.
/// </summary>
public class MaintenanceWindowParserTests
{
    // --- Every example the grammar documents ---

    [Theory]
    [InlineData("daily@05:00/backup")]
    [InlineData("weekly.sun@04:00/backup,update,restart")]
    [InlineData("monthly.1@03:00/update,restart")]
    [InlineData("6h/restart")]
    [InlineData("30d/backup")]
    public void DocumentedExample_ReadsAndRendersBackUnchanged(string expression)
    {
        var windows = MaintenanceWindowParser.Parse(expression);

        MaintenanceWindow window = Assert.Single(windows);
        Assert.True(window.IsValid, window.Error);
        Assert.Null(window.Error);
        Assert.Equal(expression, window.ToExpression());
        Assert.Equal(expression, MaintenanceWindowParser.Format(windows));
    }

    [Fact]
    public void TheCommonPair_ReadsAsTwoIndependentWindows()
    {
        const string packed = "daily@05:00/backup;weekly.sun@04:00/update,restart";

        var windows = MaintenanceWindowParser.Parse(packed);

        Assert.Equal(2, windows.Count);
        Assert.All(windows, w => Assert.True(w.IsValid, w.Error));

        Assert.Equal("daily@05:00", windows[0].Id);
        Assert.Equal(MaintenanceScheduleKind.Appointment, windows[0].Kind);
        Assert.Equal(AppointmentCadence.Daily, windows[0].Cadence);
        Assert.Equal(new TimeOnly(5, 0), windows[0].TimeOfDay);
        Assert.Equal([MaintenanceTask.Backup], windows[0].Tasks);

        Assert.Equal("weekly.sun@04:00", windows[1].Id);
        Assert.Equal(AppointmentCadence.Weekly, windows[1].Cadence);
        Assert.Equal(DayOfWeek.Sunday, windows[1].DayOfWeek);
        Assert.Equal([MaintenanceTask.Update, MaintenanceTask.Restart], windows[1].Tasks);

        Assert.Equal(packed, MaintenanceWindowParser.Format(windows));
    }

    // --- The two schedule kinds, and the discriminator between them ---

    [Fact]
    public void AtSign_DiscriminatesAnAppointmentFromAnInterval()
    {
        Assert.Equal(MaintenanceScheduleKind.Appointment,
            MaintenanceWindowParser.ParseWindow("daily@05:00/backup").Kind);
        Assert.Equal(MaintenanceScheduleKind.Interval,
            MaintenanceWindowParser.ParseWindow("6h/backup").Kind);
    }

    [Theory]
    [InlineData("sun", DayOfWeek.Sunday)]
    [InlineData("mon", DayOfWeek.Monday)]
    [InlineData("tue", DayOfWeek.Tuesday)]
    [InlineData("wed", DayOfWeek.Wednesday)]
    [InlineData("thu", DayOfWeek.Thursday)]
    [InlineData("fri", DayOfWeek.Friday)]
    [InlineData("sat", DayOfWeek.Saturday)]
    public void EveryDayToken_Reads(string token, DayOfWeek expected)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow($"weekly.{token}@04:00/restart");

        Assert.True(window.IsValid, window.Error);
        Assert.Equal(expected, window.DayOfWeek);
    }

    [Theory]
    [InlineData("10m", 10)]
    [InlineData("90m", 90)]
    [InlineData("6h", 360)]
    [InlineData("720h", 43200)]
    [InlineData("1d", 1440)]
    [InlineData("30d", 43200)]
    public void IntervalUnits_ReadAsTheSpanTheyName(string spec, int expectedMinutes)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow($"{spec}/backup");

        Assert.True(window.IsValid, window.Error);
        Assert.Equal(TimeSpan.FromMinutes(expectedMinutes), window.Interval);
    }

    [Fact]
    public void AnInterval_KeepsTheUnitItWasWrittenWith()
    {
        // The expression is the window's id, so rewriting 120m as 2h would silently make it a
        // different window and retract anything already announced about it.
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("120m/backup");

        Assert.Equal("120m", window.Id);
        Assert.Equal(120, window.IntervalCount);
        Assert.Equal(IntervalUnit.Minutes, window.IntervalUnit);
    }

    // --- The clamps ---

    [Theory]
    [InlineData("10m")]
    [InlineData("30d")]
    [InlineData("43200m")]
    [InlineData("720h")]
    public void IntervalAtABound_IsAccepted(string spec)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow($"{spec}/backup");

        Assert.True(window.IsValid, window.Error);
    }

    [Theory]
    [InlineData("1m")]
    [InlineData("9m")]
    [InlineData("0m")]
    [InlineData("0h")]
    public void IntervalBelowTheFloor_IsRejected(string spec)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow($"{spec}/backup");

        Assert.False(window.IsValid);
        Assert.Contains("10m", window.Error);
    }

    [Theory]
    [InlineData("31d")]
    [InlineData("43201m")]
    [InlineData("721h")]
    [InlineData("365d")]
    public void IntervalAboveTheCeiling_IsRejectedAndNamesTheAlternative(string spec)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow($"{spec}/backup");

        Assert.False(window.IsValid);
        Assert.Contains("30d", window.Error);
        Assert.Contains("monthly.", window.Error);
    }

    [Fact]
    public void IntervalTooLargeToHold_IsRejectedRatherThanOverflowing()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("999999999d/backup");

        Assert.False(window.IsValid);
        Assert.NotNull(window.Error);
    }

    // --- Canonical task order ---

    [Theory]
    [InlineData("restart,update,backup")]
    [InlineData("update,backup,restart")]
    [InlineData("restart,backup,update")]
    [InlineData("backup,update,restart")]
    public void TasksRunInCanonicalOrder_WhateverOrderTheyWereWrittenIn(string written)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow($"weekly.sun@04:00/{written}");

        Assert.True(window.IsValid, window.Error);
        Assert.Equal(
            [MaintenanceTask.Backup, MaintenanceTask.Update, MaintenanceTask.Restart],
            window.Tasks);
        Assert.Equal("weekly.sun@04:00/backup,update,restart", window.ToExpression());
    }

    [Fact]
    public void DuplicateTasks_Collapse()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("daily@05:00/backup,backup,restart,backup");

        Assert.True(window.IsValid, window.Error);
        Assert.Equal([MaintenanceTask.Backup, MaintenanceTask.Restart], window.Tasks);
    }

    [Fact]
    public void Runs_AnswersFromTheTaskSet()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("daily@05:00/backup");

        Assert.True(window.Runs(MaintenanceTask.Backup));
        Assert.False(window.Runs(MaintenanceTask.Update));
    }

    // --- Rejections ---

    [Theory]
    [InlineData("daily@05:00/reboot", "reboot")]
    [InlineData("daily@05:00/backup,reboot", "reboot")]
    [InlineData("daily@05:00/BACKUPS", "BACKUPS")]
    public void UnknownTask_IsRejectedAndNamesTheOffendingToken(string expression, string offender)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.Contains(offender, window.Error);
        Assert.Empty(window.Tasks);
    }

    [Theory]
    [InlineData("daily@05:00/")]
    [InlineData("daily@05:00/,")]
    [InlineData("daily@05:00/backup,")]
    public void AWindowWithNoTask_IsRejected(string expression)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.NotNull(window.Error);
    }

    [Theory]
    [InlineData("daily@24:00/backup")]
    [InlineData("daily@05:60/backup")]
    [InlineData("daily@0500/backup")]
    [InlineData("daily@05:00:00/backup")]
    [InlineData("daily@:/backup")]
    [InlineData("daily@ab:cd/backup")]
    [InlineData("daily@/backup")]
    public void MalformedTime_IsRejected(string expression)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.NotNull(window.Error);
    }

    [Theory]
    [InlineData("weekly.sunday@04:00/restart", "sunday")]
    [InlineData("weekly.xyz@04:00/restart", "xyz")]
    [InlineData("weekly.@04:00/restart", "day")]
    public void MalformedDay_IsRejected(string expression, string offender)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.Contains(offender, window.Error);
    }

    [Theory]
    [InlineData("monthly.0@03:00/restart")]
    [InlineData("monthly.32@03:00/restart")]
    [InlineData("monthly.-1@03:00/restart")]
    [InlineData("monthly.x@03:00/restart")]
    [InlineData("monthly@03:00/restart")]
    public void MalformedDayOfMonth_IsRejected(string expression)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.NotNull(window.Error);
    }

    [Theory]
    [InlineData("yearly@04:00/restart")]
    [InlineData("weekly@04:00/restart")]
    [InlineData("daily.sun@04:00/restart")]
    public void UnknownAppointment_IsRejectedAndNamesTheThreeThatWork(string expression)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.Contains("daily@HH:MM", window.Error);
        Assert.Contains("weekly.<dow>@HH:MM", window.Error);
        Assert.Contains("monthly.<dom>@HH:MM", window.Error);
    }

    [Theory]
    [InlineData("6x/restart")]
    [InlineData("6/restart")]
    [InlineData("h/restart")]
    [InlineData("six h/restart")]
    [InlineData("6 h/restart")]
    public void MalformedInterval_IsRejected(string expression)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(expression);

        Assert.False(window.IsValid);
        Assert.NotNull(window.Error);
    }

    [Fact]
    public void AWindowWithNoSlash_IsRejectedAndSaysWhatIsMissing()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("daily@05:00");

        Assert.False(window.IsValid);
        Assert.Contains("/", window.Error);
    }

    [Fact]
    public void AWindowWithNoSchedule_IsRejected()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("/backup");

        Assert.False(window.IsValid);
        Assert.NotNull(window.Error);
    }

    [Fact]
    public void ASecondAtSign_IsRejected()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("daily@05:00@06:00/backup");

        Assert.False(window.IsValid);
        Assert.Contains("'@'", window.Error);
    }

    [Fact]
    public void NothingInTheGrammarThrows_HoweverBadTheInput()
    {
        string[] junk =
        [
            "", "   ", ";", ";;;", "/", "@", "//", "@@@", "daily@", "@05:00/backup",
            " ", "daily@05:00/backup;;;;", new string('x', 4096), "-;-;-",
        ];

        foreach (string input in junk)
        {
            var windows = MaintenanceWindowParser.Parse(input);
            Assert.All(windows, w => Assert.NotNull(w.Expression));
        }
    }

    // --- Validity is per window ---

    [Fact]
    public void OneUnreadableWindow_DisablesItselfAndNothingElse()
    {
        var windows = MaintenanceWindowParser.Parse(
            "daily@05:00/backup;weekly.funday@04:00/restart;6h/backup");

        Assert.Equal(3, windows.Count);

        Assert.True(windows[0].IsValid, windows[0].Error);
        Assert.Equal("daily@05:00", windows[0].Id);

        Assert.False(windows[1].IsValid);
        Assert.Contains("funday", windows[1].Error);

        Assert.True(windows[2].IsValid, windows[2].Error);
        Assert.Equal("6h", windows[2].Id);
    }

    [Fact]
    public void AnUnreadableWindow_IsReturnedInvalidRatherThanDropped()
    {
        var windows = MaintenanceWindowParser.Parse("nonsense");

        MaintenanceWindow window = Assert.Single(windows);
        Assert.False(window.IsValid);
        Assert.Equal("nonsense", window.Expression);
        Assert.NotNull(window.Error);
    }

    // --- Duplicate schedules ---

    [Fact]
    public void ADuplicateSchedule_InvalidatesTheSecondAndSaysToMerge()
    {
        var windows = MaintenanceWindowParser.Parse("daily@05:00/backup;daily@05:00/restart");

        Assert.Equal(2, windows.Count);
        Assert.True(windows[0].IsValid, windows[0].Error);

        Assert.False(windows[1].IsValid);
        Assert.Contains("daily@05:00", windows[1].Error);
        Assert.Contains("merge", windows[1].Error);
        Assert.Empty(windows[1].Tasks);
    }

    [Fact]
    public void ADuplicateSchedule_IsDetectedThroughCanonicalForm()
    {
        // Same appointment, differently written: the id is canonical, so these collide.
        var windows = MaintenanceWindowParser.Parse("daily@5:00/backup;DAILY@05:00/restart");

        Assert.Equal("daily@05:00", windows[0].Id);
        Assert.True(windows[0].IsValid, windows[0].Error);
        Assert.False(windows[1].IsValid);
        Assert.Contains("merge", windows[1].Error);
    }

    [Fact]
    public void TwoWindowsDifferingOnlyInTime_AreNotDuplicates()
    {
        var windows = MaintenanceWindowParser.Parse("daily@05:00/backup;daily@06:00/backup");

        Assert.All(windows, w => Assert.True(w.IsValid, w.Error));
    }

    // --- The empty value ---

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void NoValue_MeansNoMaintenance(string? packed)
    {
        Assert.Empty(MaintenanceWindowParser.Parse(packed));
    }

    [Fact]
    public void EmptySegments_AreSkippedRatherThanReportedAsWindows()
    {
        var windows = MaintenanceWindowParser.Parse(";daily@05:00/backup;;6h/restart;");

        Assert.Equal(2, windows.Count);
        Assert.All(windows, w => Assert.True(w.IsValid, w.Error));
    }

    // --- Canonical form and round-tripping ---

    [Theory]
    [InlineData(" daily@5:00 / backup , restart ", "daily@05:00/backup,restart")]
    [InlineData("WEEKLY.SUN@04:00/RESTART", "weekly.sun@04:00/restart")]
    [InlineData("monthly.09@03:00/update", "monthly.9@03:00/update")]
    [InlineData("06h/backup", "6h/backup")]
    [InlineData("6H/Backup", "6h/backup")]
    public void ARelaxedlyWrittenWindow_RendersBackCanonical(string written, string canonical)
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow(written);

        Assert.True(window.IsValid, window.Error);
        Assert.Equal(canonical, window.ToExpression());
    }

    [Fact]
    public void AWindowKeepsTheTextItWasWrittenWith()
    {
        MaintenanceWindow window = MaintenanceWindowParser.ParseWindow("  DAILY@5:00/restart,backup  ");

        Assert.Equal("DAILY@5:00/restart,backup", window.Expression);
        Assert.Equal("daily@05:00/backup,restart", window.ToExpression());
    }

    [Fact]
    public void ParseThenFormat_RoundTripsThroughCanonicalForm()
    {
        const string packed = "daily@05:00/backup;weekly.sun@04:00/backup,update,restart;6h/restart";

        string once = MaintenanceWindowParser.Format(MaintenanceWindowParser.Parse(packed));
        string twice = MaintenanceWindowParser.Format(MaintenanceWindowParser.Parse(once));

        Assert.Equal(packed, once);
        Assert.Equal(once, twice);
    }

    [Fact]
    public void AnInvalidWindow_RendersBackAsWritten()
    {
        // Nothing was understood well enough to rewrite it, so packing the set again loses nothing.
        var windows = MaintenanceWindowParser.Parse("daily@05:00/backup;weekly.funday@04:00/restart");

        Assert.Equal(
            "daily@05:00/backup;weekly.funday@04:00/restart",
            MaintenanceWindowParser.Format(windows));
    }

    // --- The grammar survives the instance config ---

    [Fact]
    public void NoCanonicalExpression_CarriesACharacterTheInstanceConfigCannot()
    {
        // The instance-config readers cannot carry a tab or a newline; every other character the
        // grammar uses passes through untouched.
        var windows = MaintenanceWindowParser.Parse(
            "daily@05:00/backup;weekly.sun@04:00/backup,update,restart;30d/restart");

        string packed = MaintenanceWindowParser.Format(windows);

        Assert.DoesNotContain('\t', packed);
        Assert.DoesNotContain('\n', packed);
        Assert.DoesNotContain('\r', packed);
    }

    // --- Task tokens ---

    [Theory]
    [InlineData(MaintenanceTask.Backup, "backup")]
    [InlineData(MaintenanceTask.Update, "update")]
    [InlineData(MaintenanceTask.Restart, "restart")]
    public void EveryTask_RoundTripsThroughItsToken(MaintenanceTask task, string token)
    {
        Assert.Equal(token, task.ToToken());
        Assert.True(MaintenanceTaskExtensions.TryParse(token, out MaintenanceTask read));
        Assert.Equal(task, read);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("reboot")]
    [InlineData("back up")]
    public void AnUnknownToken_IsNotATask(string? token)
    {
        Assert.False(MaintenanceTaskExtensions.TryParse(token, out _));
    }
}
