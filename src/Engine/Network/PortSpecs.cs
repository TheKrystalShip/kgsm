using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Instances;
using TheKrystalShip.KGSM.Engine.Contracts.Network;
using TheKrystalShip.KGSM.Engine.Instances;

namespace TheKrystalShip.KGSM.Engine.Network;

/// <summary>
/// The ports an instance declares, and the conflicts between instances. An instance config holds them in
/// UFW format, pipe-separated: <c>25565</c>, <c>2456:2458/udp</c>, <c>14159/tcp|14159/udp</c>. A token
/// without a protocol is open on both.
/// </summary>
public static class PortSpecs
{
    /// <summary>
    /// Parses a spec. A token that is not a port range is left out: the engine writes the spec itself and
    /// checks it at install, so a stray token is not a reason to refuse a read.
    /// </summary>
    public static IReadOnlyList<PortRange> Parse(string? spec)
    {
        var ranges = new List<PortRange>();
        if (string.IsNullOrWhiteSpace(spec)) return ranges;

        foreach (string token in spec.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            string numbers = token;
            PortProtocol[] protocols = [PortProtocol.Tcp, PortProtocol.Udp];

            int slash = token.IndexOf('/', StringComparison.Ordinal);
            if (slash >= 0)
            {
                numbers = token[..slash];
                string protocol = token[(slash + 1)..];
                if (protocol.Equals("tcp", StringComparison.OrdinalIgnoreCase)) protocols = [PortProtocol.Tcp];
                else if (protocol.Equals("udp", StringComparison.OrdinalIgnoreCase)) protocols = [PortProtocol.Udp];
                else continue;
            }

            int colon = numbers.IndexOf(':', StringComparison.Ordinal);
            string first = colon < 0 ? numbers : numbers[..colon];
            string last = colon < 0 ? numbers : numbers[(colon + 1)..];

            if (!TryPort(first, out int start) || !TryPort(last, out int end) || end < start) continue;

            foreach (PortProtocol protocol in protocols)
                ranges.Add(new PortRange { Start = start, End = end, Protocol = protocol });
        }

        return ranges;
    }

    /// <summary>Every range every given instance declares, ordered by protocol, start, end and instance.</summary>
    public static IReadOnlyList<PortUse> Used(IEnumerable<InstanceDescription> instances) =>
        instances
            .Where(i => i.Config is not null)
            .SelectMany(i => Parse(i.Config!.Ports).Select(r => new PortUse
            {
                Instance = i.Id, Start = r.Start, End = r.End, Protocol = r.Protocol,
            }))
            .OrderBy(u => u.Protocol)
            .ThenBy(u => u.Start)
            .ThenBy(u => u.End)
            .ThenBy(u => u.Instance, StringComparer.Ordinal)
            .ToList();

    /// <summary>
    /// The overlaps between different instances, on one protocol. Each conflict is a connected group of
    /// overlapping ranges and the span it covers, so three instances contending for one port are one conflict.
    /// </summary>
    public static IReadOnlyList<PortConflict> Conflicts(IReadOnlyList<PortUse> used)
    {
        var conflicts = new List<PortConflict>();

        foreach (IGrouping<PortProtocol, PortUse> byProtocol in used.GroupBy(u => u.Protocol).OrderBy(g => g.Key))
        {
            PortUse[] sorted = [.. byProtocol.OrderBy(u => u.Start).ThenBy(u => u.End)];
            var group = new List<PortUse>();
            int groupEnd = 0;

            void Flush()
            {
                string[] instances = [.. group.Select(u => u.Instance).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)];
                if (instances.Length > 1)
                {
                    conflicts.Add(new PortConflict
                    {
                        Protocol = byProtocol.Key,
                        Start = group.Min(u => u.Start),
                        End = group.Max(u => u.End),
                        Instances = instances,
                    });
                }

                group.Clear();
            }

            foreach (PortUse use in sorted)
            {
                if (group.Count > 0 && use.Start > groupEnd) Flush();
                group.Add(use);
                groupEnd = group.Count == 1 ? use.End : Math.Max(groupEnd, use.End);
            }

            if (group.Count > 0) Flush();
        }

        return conflicts;
    }

    private static bool TryPort(string text, out int port) =>
        int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out port) && port is >= 1 and <= 65535;
}
