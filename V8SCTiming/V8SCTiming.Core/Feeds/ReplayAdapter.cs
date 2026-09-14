using System.Text.Json;
using System.Text.Json.Nodes;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Core.Feeds;

/// <summary>
/// Replays a previously saved session from a JSON file ({ laps, passings } or a
/// bare array of laps). Ported from adapter_replay.js. Emits events in
/// timestamp order at a configurable speed multiplier, with pause/resume/setSpeed.
/// </summary>
public sealed class ReplayAdapter : IFeedAdapter
{
    public event Action<Lap>? LapReceived;
    public event Action<SessionEvent>? SessionReceived;
    public event Action<string>? RawMessageReceived;

    private sealed class TimelineEvent
    {
        public string Kind = "lap"; // "lap" | "passing"
        public long Timestamp;
        public Lap? Lap;
        public Passing? Passing;
    }

    private List<Lap> _laps = new();
    private List<TimelineEvent> _events = new();
    private int _index;
    private double _speed = 10;
    private bool _loopOnEnd;
    private bool _connected;
    private bool _paused;

    private long _segmentStartLap;
    private DateTime _segmentStartWall;
    private double _pausedElapsedMs;
    private Timer? _timer;

    public async Task ConnectAsync(FeedProfile profile, JsonObject? trackConfig, CancellationToken ct)
    {
        var s = profile.Settings;
        var filePath = s["filePath"]?.GetValue<string>()
            ?? throw new InvalidOperationException("Replay adapter: profile.settings.filePath is required");

        _speed = s["speedMultiplier"]?.GetValue<double>() ?? 10;
        _loopOnEnd = s["loopOnEnd"]?.GetValue<bool>() ?? false;

        string raw;
        try { raw = await File.ReadAllTextAsync(filePath, ct); }
        catch (Exception ex) { throw new InvalidOperationException($"Replay adapter: could not read file \"{filePath}\": {ex.Message}"); }

        RawMessageReceived?.Invoke(raw);

        JsonNode? parsed;
        try { parsed = JsonNode.Parse(raw); }
        catch (Exception ex) { throw new InvalidOperationException($"Replay adapter: invalid JSON in \"{filePath}\": {ex.Message}"); }

        List<Lap> laps;
        List<Passing> passings;
        if (parsed is JsonArray arr)
        {
            if (arr.Count == 0) throw new InvalidOperationException("Replay adapter: file must be a non-empty JSON array of lap objects");
            laps = arr.Select(DeserialiseLap).ToList();
            passings = new List<Passing>();
        }
        else if (parsed is JsonObject obj)
        {
            laps = (obj["laps"] as JsonArray)?.Select(DeserialiseLap).ToList() ?? new();
            passings = (obj["passings"] as JsonArray)?.Select(DeserialisePassing).ToList() ?? new();
            if (laps.Count == 0) throw new InvalidOperationException("Replay adapter: file contains no lap records");
        }
        else
        {
            throw new InvalidOperationException("Replay adapter: unrecognised JSON shape");
        }

        _laps = laps;
        DeriveSectorTimesFromPassings(laps, passings);

        _events = laps.Select(l => new TimelineEvent { Kind = "lap", Timestamp = l.Timestamp, Lap = l })
            .Concat(passings.Select(p => new TimelineEvent { Kind = "passing", Timestamp = p.Timestamp, Passing = p }))
            .OrderBy(e => e.Timestamp)
            .ToList();

        _index = 0;
        _connected = true;
        Console.WriteLine($"[ReplayAdapter] Connected: file=\"{filePath}\", {laps.Count} laps + {passings.Count} passings, speed={_speed}x");

        BeginSegment();
    }

    public void Disconnect()
    {
        ClearTimer();
        _paused = false;
        _connected = false;
        Console.WriteLine("[ReplayAdapter] Disconnected: user request");
    }

    public FeedStatus Status()
    {
        var lapsEmitted = _events.Take(_index).Count(e => e.Kind == "lap");
        return new FeedStatus(_connected, "replay",
            _connected ? $"Replay {(_paused ? "PAUSED" : "PLAYING")} — lap {lapsEmitted}/{_laps.Count}, speed={_speed}x" : "Not connected");
    }

    // ── Runtime controls ─────────────────────────────────────────────────

    public void SetSpeed(double multiplier)
    {
        if (!double.IsFinite(multiplier) || multiplier <= 0)
            throw new ArgumentOutOfRangeException(nameof(multiplier), "setSpeed: multiplier must be a positive number");

        if (!_paused && _timer != null)
        {
            var wallElapsed = (DateTime.UtcNow - _segmentStartWall).TotalMilliseconds;
            var lapElapsed = wallElapsed * _speed;
            _segmentStartLap += (long)lapElapsed;
            _segmentStartWall = DateTime.UtcNow;
        }

        _speed = multiplier;

        if (!_paused)
        {
            ClearTimer();
            ScheduleNext(0);
        }
        Console.WriteLine($"[ReplayAdapter] Speed set to {_speed}x");
    }

    public void Pause()
    {
        if (_paused) return;
        _paused = true;
        _pausedElapsedMs = (DateTime.UtcNow - _segmentStartWall).TotalMilliseconds;
        ClearTimer();
        Console.WriteLine($"[ReplayAdapter] Paused at lap index {_index}.");
    }

    public void Resume()
    {
        if (!_paused) return;
        _paused = false;
        var lapDelay = DelayToLap(_index);
        var remaining = Math.Max(0, lapDelay - _pausedElapsedMs);
        _segmentStartWall = DateTime.UtcNow.AddMilliseconds(-_pausedElapsedMs);
        _pausedElapsedMs = 0;
        ScheduleNext(remaining);
        Console.WriteLine($"[ReplayAdapter] Resumed at lap index {_index}.");
    }

    // ── Playback engine ──────────────────────────────────────────────────

    private void BeginSegment()
    {
        if (_index >= _events.Count) return;
        _segmentStartLap = _events[_index].Timestamp;
        _segmentStartWall = DateTime.UtcNow;
        ScheduleNext(0);
    }

    private void ScheduleNext(double? delayMs)
    {
        if (_index >= _events.Count) { OnPlaybackEnd(); return; }

        var delay = delayMs ?? Math.Max(0, DelayToLap(_index));

        _timer = new Timer(_ =>
        {
            _timer = null;
            if (_paused) return;

            var evt = _events[_index];
            if (evt.Kind == "passing" && evt.Passing != null) SessionReceived?.Invoke(new SessionEvent { Type = "passing", Payload = evt.Passing });
            else if (evt.Lap != null) LapReceived?.Invoke(evt.Lap);

            _index++;
            ScheduleNext(null);
        }, null, (int)Math.Max(0, delay), Timeout.Infinite);
    }

    private double DelayToLap(int index)
    {
        var evt = _events[index];
        var lapOffset = evt.Timestamp - _segmentStartLap;
        var wallTarget = lapOffset / _speed;
        var wallNow = (DateTime.UtcNow - _segmentStartWall).TotalMilliseconds;
        return wallTarget - wallNow;
    }

    private void OnPlaybackEnd()
    {
        if (_loopOnEnd)
        {
            Console.WriteLine("[ReplayAdapter] End of file — looping.");
            _index = 0;
            BeginSegment();
        }
        else
        {
            Console.WriteLine($"[ReplayAdapter] End of file — {_laps.Count} laps complete.");
            _connected = false;
        }
    }

    private void ClearTimer()
    {
        _timer?.Dispose();
        _timer = null;
    }

    // ── Sector-time backfill from Int1/Int2 passings ─────────────────────

    private static void DeriveSectorTimesFromPassings(List<Lap> laps, List<Passing> passings)
    {
        if (passings.Count == 0) return;

        var byCar = passings.GroupBy(p => p.CarNumber).ToDictionary(g => g.Key, g => g.OrderBy(p => p.Time).ToList());
        var derived = new Dictionary<string, (double? S1, double? S2)>();

        foreach (var (car, ps) in byCar)
        {
            double? sfToc = null, int1Toc = null;
            foreach (var p in ps)
            {
                if (p.Time <= 0) continue;
                var key = $"{car}_{p.LapNumber}";
                if (p.LoopType == 1) { sfToc = p.Time; int1Toc = null; }
                else if (p.LoopType == 5 && sfToc != null)
                {
                    int1Toc = p.Time;
                    var s1 = p.Time - sfToc.Value;
                    if (s1 is > 0 and < 200)
                    {
                        derived.TryGetValue(key, out var existing);
                        derived[key] = (s1, existing.S2);
                    }
                }
                else if (p.LoopType == 6 && int1Toc != null)
                {
                    var s2 = p.Time - int1Toc.Value;
                    if (s2 is > 0 and < 200)
                    {
                        derived.TryGetValue(key, out var existing);
                        derived[key] = (existing.S1, s2);
                    }
                }
            }
        }

        foreach (var lap in laps)
        {
            var key = $"{lap.CarNumber}_{lap.LapNumber}";
            if (!derived.TryGetValue(key, out var d)) continue;
            if (lap.S1 == null && d.S1 != null) lap.S1 = d.S1;
            if (lap.S2 == null && d.S2 != null) lap.S2 = d.S2;
        }
    }

    // ── JSON -> model deserialisation (tolerant of missing/extra fields) ──

    private static long? GetLongFlexible(JsonNode? node)
    {
        if (node == null) return null;
        var d = node.GetValue<double>();
        return (long)d;
    }

    private static Lap DeserialiseLap(JsonNode? node)
    {
        var o = node as JsonObject ?? new JsonObject();
        return new Lap
        {
            CarNumber = o["carNumber"]?.ToString() ?? "",
            LapNumber = o["lapNumber"]?.GetValue<int?>() ?? 0,
            LapTime = o["lapTime"]?.GetValue<double?>(),
            S1 = o["s1"]?.GetValue<double?>(),
            S2 = o["s2"]?.GetValue<double?>(),
            S3 = o["s3"]?.GetValue<double?>(),
            IsPitLap = o["isPitLap"]?.GetValue<bool?>() ?? false,
            Outing = o["outing"]?.GetValue<int?>() ?? 0,
            LapsSincePit = o["lapsSincePit"]?.GetValue<int?>() ?? 0,
            Position = o["position"]?.GetValue<int?>(),
            Tyre = o["tyre"]?.ToString(),
            PitDuration = o["pitDuration"]?.GetValue<double?>(),
            YellowFlag = o["yellowFlag"]?.GetValue<bool?>() ?? false,
            Timestamp = GetLongFlexible(o["timestamp"]) ?? 0,
            InLapSegmentTime = o["inLapSegmentTime"]?.GetValue<double?>(),
            OutLapSegmentTime = o["outLapSegmentTime"]?.GetValue<double?>(),
            SpeedTrap = o["speedTrap"]?.GetValue<double?>(),
            DriverName = o["driverName"]?.ToString(),
            Vehicle = o["vehicle"]?.ToString(),
        };
    }

    private static Passing DeserialisePassing(JsonNode? node)
    {
        var o = node as JsonObject ?? new JsonObject();
        return new Passing
        {
            CarNumber = o["carNumber"]?.ToString() ?? "",
            LoopType = o["loopType"]?.GetValue<int?>() ?? 0,
            Time = o["time"]?.GetValue<double?>() ?? 0,
            Sector = o["sector"]?.GetValue<int?>(),
            LapNumber = o["lapNumber"]?.GetValue<int?>(),
            Timestamp = GetLongFlexible(o["timestamp"]) ?? 0,
        };
    }
}
