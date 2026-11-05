using System.Globalization;
using TheKrystalShip.KGSM.Engine.Contracts.Operations;

namespace TheKrystalShip.KGSM.Engine.Network;

/// <summary>
/// The sockets the host is listening on, read from <c>/proc/net</c>: TCP in the listen state and UDP
/// sockets bound without a peer (what <c>ss -tlnp</c> and <c>ss -ulnp</c> list). The process holding a
/// socket is named where <c>/proc/&lt;pid&gt;/fd</c> is readable by the caller and left unknown otherwise.
/// </summary>
public static class HostSockets
{
    private const string TcpListen = "0A";
    private const string UdpUnconnected = "07";

    /// <summary>Every listening port once per protocol, ordered by protocol then port.</summary>
    public static IReadOnlyList<ListeningPort> Listening(string procRoot = "/proc")
    {
        var found = new Dictionary<(string Protocol, int Port), long>();

        Collect(Path.Combine(procRoot, "net", "tcp"), "tcp", TcpListen, found);
        Collect(Path.Combine(procRoot, "net", "tcp6"), "tcp", TcpListen, found);
        Collect(Path.Combine(procRoot, "net", "udp"), "udp", UdpUnconnected, found);
        Collect(Path.Combine(procRoot, "net", "udp6"), "udp", UdpUnconnected, found);

        Dictionary<long, string> owners = Owners(procRoot, [.. found.Values.Where(inode => inode != 0)]);

        return
        [
            .. found
                .OrderBy(entry => entry.Key.Protocol, StringComparer.Ordinal)
                .ThenBy(entry => entry.Key.Port)
                .Select(entry => new ListeningPort
                {
                    Port = entry.Key.Port,
                    Protocol = entry.Key.Protocol,
                    Process = owners.GetValueOrDefault(entry.Value),
                }),
        ];
    }

    private static void Collect(string file, string protocol, string state, Dictionary<(string, int), long> found)
    {
        string[] lines;
        try
        {
            lines = File.ReadAllLines(file);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return;
        }

        foreach (string line in lines.Skip(1))
        {
            string[] fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length < 10 || fields[3] != state) continue;

            int colon = fields[1].LastIndexOf(':');
            if (colon < 0 || !int.TryParse(fields[1][(colon + 1)..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int port) || port == 0)
                continue;

            long.TryParse(fields[9], NumberStyles.None, CultureInfo.InvariantCulture, out long inode);
            if (!found.TryGetValue((protocol, port), out long known) || known == 0) found[(protocol, port)] = inode;
        }
    }

    private static Dictionary<long, string> Owners(string procRoot, HashSet<long> wanted)
    {
        var owners = new Dictionary<long, string>();
        if (wanted.Count == 0) return owners;

        IEnumerable<string> processes;
        try
        {
            processes = Directory.EnumerateDirectories(procRoot).Where(d => int.TryParse(Path.GetFileName(d), out _)).ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return owners;
        }

        foreach (string process in processes)
        {
            IEnumerable<string> descriptors;
            try
            {
                descriptors = Directory.EnumerateFileSystemEntries(Path.Combine(process, "fd")).ToList();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }

            foreach (string descriptor in descriptors)
            {
                string? target;
                try
                {
                    target = new FileInfo(descriptor).LinkTarget;
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    continue;
                }

                if (target is null || !target.StartsWith("socket:[", StringComparison.Ordinal)) continue;
                if (!long.TryParse(target.AsSpan(8, target.Length - 9), NumberStyles.None, CultureInfo.InvariantCulture, out long inode)) continue;
                if (!wanted.Contains(inode) || owners.ContainsKey(inode)) continue;

                try
                {
                    owners[inode] = File.ReadAllText(Path.Combine(process, "comm")).Trim();
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                }
            }
        }

        return owners;
    }
}
