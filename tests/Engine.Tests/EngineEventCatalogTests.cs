using System.Reflection;
using TheKrystalShip.KGSM.Engine.Contracts.Events;

namespace TheKrystalShip.KGSM.Engine.Tests;

/// <summary>
/// Keeps the catalog honest. A payload type added without a descriptor, or a payload field added without a
/// classification, fails here: the moment anyone is thinking about it.
/// </summary>
public class EngineEventCatalogTests
{
    private static readonly Type[] PayloadTypes = typeof(EngineEventData).Assembly
        .GetTypes()
        .Where(t => !t.IsAbstract && typeof(EngineEventData).IsAssignableFrom(t))
        .OrderBy(t => t.Name, StringComparer.Ordinal)
        .ToArray();

    private static readonly string[] SubjectProperties = ["InstanceName", "BlueprintName", "LibraryName"];

    [Fact]
    public void EveryPayloadType_HasADescriptor_AndEveryDescriptorAPayloadType()
    {
        Assert.Equal(PayloadTypes.Select(t => t.Name), EngineEventCatalog.All.Select(d => d.PayloadType).Order(StringComparer.Ordinal));
    }

    [Fact]
    public void EveryPayloadType_DeclaresTheEventContract()
    {
        Assert.All(PayloadTypes, type =>
        {
            Type contract = typeof(IEngineEvent<>).MakeGenericType(type);
            Assert.True(contract.IsAssignableFrom(type), type.Name);
        });
    }

    [Fact]
    public void Names_AreUnique_WellFormed_AndPastTense()
    {
        string[] names = EngineEventCatalog.All.Select(d => d.Name.Value).ToArray();

        Assert.Equal(names.Length, names.Distinct(StringComparer.Ordinal).Count());
        Assert.All(names, name => Assert.True(EventName.IsWellFormed(name), name));
        Assert.All(names, name => Assert.DoesNotContain('-', name));
    }

    [Fact]
    public void TheNamespaces_AreTheEnginesOwn()
    {
        string[] allowed = ["server", "backup", "config", "console", "announcement", "player", "blueprint", "library"];

        Assert.All(EngineEventCatalog.All, d => Assert.Contains(d.Name.Namespace, allowed));
    }

    [Fact]
    public void NoBracketIsRecordedTwice_AsFinishedAndCompleted()
    {
        Assert.DoesNotContain(EngineEventCatalog.All, d => d.Name.Value.EndsWith(".completed", StringComparison.Ordinal));
    }

    [Fact]
    public void EveryBracketThatStarts_Finishes()
    {
        string[] names = EngineEventCatalog.All.Select(d => d.Name.Value).ToArray();
        string[] brackets = EngineEventCatalog.All
            .Where(d => d.Traits.Weight == EventWeight.Phase && d.Name.Value.EndsWith(".started", StringComparison.Ordinal))
            .Select(d => d.Name.Value)
            .ToArray();

        Assert.NotEmpty(brackets);
        foreach (string started in brackets)
            Assert.Contains(started[..^".started".Length] + ".finished", names);
    }

    [Fact]
    public void ADeclaredFailure_IsAFact_NotABracket()
    {
        foreach (EventDescriptor failed in EngineEventCatalog.All.Where(d => d.Traits.Outcome == EventOutcome.Failure))
        {
            Assert.Equal(EventWeight.Fact, failed.Traits.Weight);
            Assert.Equal(EventSeverity.Danger, failed.Traits.Severity);
        }
    }

    [Fact]
    public void EveryPayloadProperty_IsClassified_AndNoClassificationNamesAMissingProperty()
    {
        foreach (EventDescriptor descriptor in EngineEventCatalog.All)
        {
            Type payload = PayloadTypes.Single(t => t.Name == descriptor.PayloadType);
            string[] properties = payload
                .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .Select(p => p.Name)
                .Order(StringComparer.Ordinal)
                .ToArray();

            Assert.True(
                properties.SequenceEqual(descriptor.Fields.Select(f => f.Name).Order(StringComparer.Ordinal)),
                $"{descriptor.PayloadType}: properties [{string.Join(", ", properties)}] vs classified [{string.Join(", ", descriptor.Fields.Select(f => f.Name))}]");
        }
    }

    [Fact]
    public void TheSubject_IsTheBaseTypesIdentifyingField()
    {
        foreach (EventDescriptor descriptor in EngineEventCatalog.All)
        {
            Type payload = PayloadTypes.Single(t => t.Name == descriptor.PayloadType);
            string expected = descriptor.Subject switch
            {
                EventSubject.Instance => "InstanceName",
                EventSubject.Blueprint => "BlueprintName",
                _ => "LibraryName",
            };

            Assert.NotNull(payload.GetProperty(expected));
            Assert.All(SubjectProperties.Where(p => p != expected), other => Assert.Null(payload.GetProperty(other)));
        }
    }

    [Fact]
    public void ACommandIsPrivileged_AndAModerationTargetIsConditional()
    {
        EventDescriptor kicked = EngineEventCatalog.Find("player.kicked")!;

        Assert.Equal(FieldSensitivity.Privileged, kicked.Fields.Single(f => f.Name == "Command").Sensitivity);
        Assert.Equal(FieldSensitivity.Conditional, kicked.Fields.Single(f => f.Name == "Target").Sensitivity);
        Assert.Equal(FieldSensitivity.Privileged, EngineEventCatalog.Find("console.input.sent")!.Fields.Single().Sensitivity);
    }

    [Fact]
    public void ConfigChanged_NamesTheKeyAndNeverCarriesAValue()
    {
        Assert.Equal(["Key"], EngineEventCatalog.Find("config.changed")!.Fields.Select(f => f.Name));
    }

    [Fact]
    public void FindingByName_AnswersForTheEnginesNames_AndNullForAnyOther()
    {
        Assert.Equal("BackupCreated", EngineEventCatalog.Find("backup.created")!.PayloadType);
        Assert.True(EngineEventCatalog.IsEngineEvent("blueprint.created"));
        Assert.False(EngineEventCatalog.IsEngineEvent("blueprint-created"));
        Assert.False(EngineEventCatalog.IsEngineEvent("watchdog.something"));
        Assert.False(EngineEventCatalog.IsEngineEvent(null));
    }

    [Theory]
    [InlineData("backup.created", true)]
    [InlineData("network.upnp.reasserted", true)]
    [InlineData("server.crash.exhausted", true)]
    [InlineData("blueprint-created.x", true)]
    [InlineData("Backup.Created", false)]
    [InlineData("backup", false)]
    [InlineData("backup..created", false)]
    [InlineData("1backup.created", false)]
    [InlineData(".backup", false)]
    public void ANameIsDottedLowercaseWithAtLeastTwoSegments(string name, bool valid)
    {
        Assert.Equal(valid, EventName.TryParse(name, out _));
    }

    [Fact]
    public void AHyphenReadsAsAnUnderscore()
    {
        Assert.Equal("blueprint_created.x", EventName.Parse("blueprint-created.x").Value);
    }
}
