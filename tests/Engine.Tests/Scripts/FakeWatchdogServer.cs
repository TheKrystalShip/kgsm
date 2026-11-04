using System.Net.Sockets;
using System.Text;

namespace TheKrystalShip.KGSM.Engine.Tests.Scripts;

/// <summary>A request the fake watchdog received.</summary>
internal sealed record WatchdogRequest(string Method, string Path);

/// <summary>
/// A watchdog's control socket for a test: HTTP/1.1 on a unix socket, answering what the test scripted and
/// recording what it was asked. The script talks to it with the host's own curl, as it does to the real one.
/// </summary>
internal sealed class FakeWatchdogServer : IDisposable
{
    private readonly Socket _listener;
    private readonly CancellationTokenSource _stop = new();
    private readonly Task _accepting;
    private readonly object _gate = new();
    private readonly List<WatchdogRequest> _requests = [];
    private readonly Dictionary<string, (int Status, string Body)> _answers = new(StringComparer.Ordinal);

    public FakeWatchdogServer(string socketPath)
    {
        SocketPath = socketPath;
        _listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        _listener.Bind(new UnixDomainSocketEndPoint(socketPath));
        _listener.Listen(16);
        _accepting = Task.Run(AcceptAsync);
    }

    public string SocketPath { get; }

    /// <summary>The requests received so far, in order.</summary>
    public IReadOnlyList<WatchdogRequest> Requests
    {
        get
        {
            lock (_gate) return [.. _requests];
        }
    }

    /// <summary>Scripts the answer to <c>METHOD /path</c>; a request nothing was scripted for gets a 404.</summary>
    public void Answer(string method, string path, int status, string body)
    {
        lock (_gate) _answers[$"{method} {path}"] = (status, body);
    }

    /// <summary>Scripts the state of an instance the watchdog tracks.</summary>
    public void Track(string instance, bool populated, int? pid = null, string? spawnedAt = null)
    {
        string pidText = pid is { } p ? p.ToString(System.Globalization.CultureInfo.InvariantCulture) : "null";
        string spawned = spawnedAt is null ? "null" : $"\"{spawnedAt}\"";
        Answer("GET", $"/status/{instance}", 200,
            $$"""{"name":"{{instance}}","desired":"running","enabled":true,"populated":{{(populated ? "true" : "false")}},"pid":{{pidText}},"cgroupPath":"/x","phase":"running","restarts":0,"reason":"","spawnedAt":{{spawned}},"lastExitedAt":null}""");
    }

    private async Task AcceptAsync()
    {
        try
        {
            while (!_stop.IsCancellationRequested)
            {
                Socket client = await _listener.AcceptAsync(_stop.Token).ConfigureAwait(false);
                _ = Task.Run(() => ServeAsync(client));
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private async Task ServeAsync(Socket client)
    {
        using (client)
        {
            try
            {
                using var stream = new NetworkStream(client, ownsSocket: false);
                using var reader = new StreamReader(stream, Encoding.ASCII);

                string? requestLine = await reader.ReadLineAsync().ConfigureAwait(false);
                if (requestLine is null) return;
                while (await reader.ReadLineAsync().ConfigureAwait(false) is { Length: > 0 })
                {
                }

                string[] parts = requestLine.Split(' ');
                string method = parts[0];
                string path = parts[1];
                string route = path.Split('?')[0];

                (int status, string body) answer;
                lock (_gate)
                {
                    _requests.Add(new WatchdogRequest(method, path));
                    answer = _answers.TryGetValue($"{method} {route}", out var scripted) ? scripted : (404, "{}");
                }

                byte[] payload = Encoding.UTF8.GetBytes(answer.body);
                string head = $"HTTP/1.1 {answer.status} X\r\nContent-Type: application/json\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n";
                await stream.WriteAsync(Encoding.ASCII.GetBytes(head)).ConfigureAwait(false);
                await stream.WriteAsync(payload).ConfigureAwait(false);
            }
            catch (IOException)
            {
            }
            catch (SocketException)
            {
            }
        }
    }

    public void Dispose()
    {
        _stop.Cancel();
        _listener.Dispose();
        try
        {
            _accepting.Wait(TimeSpan.FromSeconds(5));
        }
        catch (AggregateException)
        {
        }

        _stop.Dispose();
        if (File.Exists(SocketPath)) File.Delete(SocketPath);
    }
}
