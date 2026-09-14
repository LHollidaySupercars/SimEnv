using System.Windows.Threading;
using V8SCTiming.Core.Data;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Services;

/// <summary>
/// Polls the shared SQLite database for new laps and raises an event for each
/// batch found. This is how the Viewer stays "live" without ever writing to
/// the DB itself — the Logger is the sole writer (see TimingDb / Logger.Program).
/// </summary>
public sealed class DbTailService : IDisposable
{
    private readonly TimingDb _db;
    private readonly DispatcherTimer _timer;
    private long _lastSeenId;
    private string? _sessionId;

    public event Action<IReadOnlyList<Lap>>? NewLaps;

    public DbTailService(TimingDb db, TimeSpan? interval = null)
    {
        _db = db;
        _timer = new DispatcherTimer { Interval = interval ?? TimeSpan.FromMilliseconds(500) };
        _timer.Tick += (_, _) => Poll();
    }

    public void Start(string sessionId)
    {
        _sessionId = sessionId;
        _lastSeenId = 0;
        _timer.Start();
    }

    public void Stop() => _timer.Stop();

    private void Poll()
    {
        if (_sessionId == null) return;
        var rows = _db.GetLapsSince(_sessionId, _lastSeenId);
        if (rows.Count == 0) return;
        _lastSeenId = rows[^1].Id;
        NewLaps?.Invoke(rows.Select(r => r.Lap).ToList());
    }

    public void Dispose() => _timer.Stop();
}
