using System.Net.Http.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Core.Feeds;

/// <summary>
/// Timing feed adapter for the public OpenF1 REST API (https://openf1.org).
/// Ported from adapter_f1.js. Polls /v1/laps, /v1/pit, /v1/race_control,
/// /v1/position, /v1/drivers. No API key required.
/// </summary>
public sealed class OpenF1Adapter : IFeedAdapter
{
    public event Action<Lap>? LapReceived;
    public event Action<SessionEvent>? SessionReceived;
    public event Action<string>? RawMessageReceived;

    private readonly HttpClient _http = new();
    private string _baseUrl = "https://api.openf1.org";
    private int _pollIntervalMs = 4000;
    private string _sessionKey = "latest";
    private bool _connected;
    private CancellationTokenSource? _cts;

    private readonly Dictionary<string, int> _highWaterMark = new();
    private readonly Dictionary<string, int> _outingByDriver = new();
    private readonly Dictionary<string, int> _lapsSincePitMap = new();
    private readonly Dictionary<string, Dictionary<int, double>> _pitDurByDriver = new();
    private readonly Dictionary<string, List<(long Ts, int Pos)>> _positionTimeline = new();
    private string? _lastRcTime;

    public async Task ConnectAsync(FeedProfile profile, JsonObject? trackConfig, CancellationToken ct)
    {
        var s = profile.Settings;
        _baseUrl = (s["baseUrl"]?.GetValue<string>() ?? "https://api.openf1.org").TrimEnd('/');
        _pollIntervalMs = s["pollIntervalMs"]?.GetValue<int>() ?? 4000;
        _sessionKey = s["sessionKey"]?.GetValue<string>() ?? "latest";

        var isHistorical = _sessionKey != "latest";
        if (!isHistorical) _sessionKey = await ResolveLatestSessionKeyAsync();

        _connected = true;
        Console.WriteLine($"[OpenF1Adapter] Connected: session_key={_sessionKey}, poll={_pollIntervalMs}ms");

        if (!isHistorical) await SeedHighWaterMarksAsync();

        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        _ = FetchAndEmitDriversAsync();
        _ = FetchPitDataAsync();
        _ = FetchPositionsAsync();

        _ = Task.Run(() => LapPollLoopAsync(_cts.Token), _cts.Token);

        var rcInterval = Math.Max(_pollIntervalMs * 2, 30_000);
        _ = Task.Run(() => RaceControlPollLoopAsync(isHistorical, rcInterval, _cts.Token), _cts.Token);
    }

    public void Disconnect()
    {
        _connected = false;
        _cts?.Cancel();
        Console.WriteLine("[OpenF1Adapter] Disconnected: user request");
    }

    public FeedStatus Status() => new(_connected, "openf1",
        _connected ? $"OpenF1 session {_sessionKey}, polling every {_pollIntervalMs}ms" : "Not connected");

    private async Task<JsonNode?> GetAsync(string path)
    {
        var url = _baseUrl + path;
        var resp = await _http.GetStringAsync(url);
        RawMessageReceived?.Invoke(resp);
        return JsonNode.Parse(resp);
    }

    private async Task<string> ResolveLatestSessionKeyAsync()
    {
        var year = DateTime.UtcNow.Year;
        foreach (var y in new[] { year, year - 1 })
        {
            try
            {
                var sessions = (await GetAsync($"/v1/sessions?year={y}"))?.AsArray();
                if (sessions is { Count: > 0 })
                {
                    var best = sessions.OfType<JsonObject>()
                        .OrderByDescending(s => s["session_key"]?.GetValue<long>() ?? 0)
                        .First();
                    return best["session_key"]!.ToString();
                }
            }
            catch { /* try previous year */ }
        }
        throw new InvalidOperationException(
            "Cannot resolve the current OpenF1 session. Pick a session_key explicitly in the profile.");
    }

    private async Task SeedHighWaterMarksAsync()
    {
        try
        {
            var laps = (await GetAsync($"/v1/laps?session_key={_sessionKey}"))?.AsArray();
            if (laps == null) return;
            foreach (var node in laps.OfType<JsonObject>())
            {
                var key = node["driver_number"]?.ToString() ?? "";
                var lapNum = node["lap_number"]?.GetValue<int>() ?? 0;
                if (lapNum > _highWaterMark.GetValueOrDefault(key, 0)) _highWaterMark[key] = lapNum;
            }
            Console.WriteLine($"[OpenF1Adapter] Seeded high-water marks for {_highWaterMark.Count} driver(s).");
        }
        catch (Exception ex) { Console.WriteLine($"[OpenF1Adapter] Could not seed high-water marks: {ex.Message}"); }
    }

    private async Task LapPollLoopAsync(CancellationToken ct)
    {
        var failCount = 0;
        while (!ct.IsCancellationRequested)
        {
            await FetchPositionsAsync();
            try
            {
                var laps = (await GetAsync($"/v1/laps?session_key={_sessionKey}"))?.AsArray();
                if (laps != null)
                {
                    failCount = 0;
                    var newLaps = laps.OfType<JsonObject>()
                        .Where(raw => (raw["lap_number"]?.GetValue<int>() ?? 0) >
                                      _highWaterMark.GetValueOrDefault(raw["driver_number"]?.ToString() ?? "", 0))
                        .OrderBy(raw => raw["lap_number"]?.GetValue<int>() ?? 0)
                        .ToList();

                    foreach (var raw in newLaps)
                    {
                        var key = raw["driver_number"]?.ToString() ?? "";
                        _highWaterMark[key] = raw["lap_number"]?.GetValue<int>() ?? 0;
                        LapReceived?.Invoke(NormaliseLap(raw));
                    }
                }
            }
            catch (Exception ex)
            {
                failCount++;
                if (failCount <= 3 || failCount % 10 == 0)
                    Console.WriteLine($"[OpenF1Adapter] Lap poll error (#{failCount}): {ex.Message}");
            }
            await Task.Delay(_pollIntervalMs, ct).ContinueWith(_ => { });
        }
    }

    private async Task RaceControlPollLoopAsync(bool isHistorical, int interval, CancellationToken ct)
    {
        var failCount = 0;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var events = (await GetAsync($"/v1/race_control?session_key={_sessionKey}"))?.AsArray();
                if (events != null)
                {
                    failCount = 0;
                    foreach (var ev in events.OfType<JsonObject>())
                    {
                        var date = ev["date"]?.ToString();
                        if (date == null) continue;
                        if (_lastRcTime != null && string.CompareOrdinal(date, _lastRcTime) <= 0) continue;
                        _lastRcTime = date;
                        SessionReceived?.Invoke(NormaliseRaceControl(ev));
                    }
                }
            }
            catch (Exception ex)
            {
                failCount++;
                if (failCount <= 3 || failCount % 10 == 0)
                    Console.WriteLine($"[OpenF1Adapter] Race control poll error (#{failCount}): {ex.Message}");
            }

            if (isHistorical) break; // static data — fetch once
            await Task.Delay(interval, ct).ContinueWith(_ => { });
        }
    }

    private async Task FetchPositionsAsync()
    {
        try
        {
            var entries = (await GetAsync($"/v1/position?session_key={_sessionKey}"))?.AsArray();
            if (entries == null) return;
            foreach (var e in entries.OfType<JsonObject>())
            {
                var pos = e["position"]?.GetValue<int?>();
                var date = e["date"]?.ToString();
                if (pos == null || date == null) continue;
                var key = e["driver_number"]?.ToString() ?? "";
                var ts = DateTimeOffset.Parse(date).ToUnixTimeMilliseconds();
                if (!_positionTimeline.TryGetValue(key, out var list)) _positionTimeline[key] = list = new();
                list.Add((ts, pos.Value));
            }
            foreach (var list in _positionTimeline.Values) list.Sort((a, b) => a.Ts.CompareTo(b.Ts));
        }
        catch (Exception ex) { Console.WriteLine($"[OpenF1Adapter] Could not fetch position data: {ex.Message}"); }
    }

    private int? PositionAt(string driverKey, long ts)
    {
        if (!_positionTimeline.TryGetValue(driverKey, out var timeline) || timeline.Count == 0) return null;
        int lo = 0, hi = timeline.Count - 1;
        int? result = timeline[0].Pos;
        while (lo <= hi)
        {
            var mid = (lo + hi) / 2;
            if (timeline[mid].Ts <= ts) { result = timeline[mid].Pos; lo = mid + 1; }
            else hi = mid - 1;
        }
        return result;
    }

    private async Task FetchPitDataAsync()
    {
        try
        {
            var pits = (await GetAsync($"/v1/pit?session_key={_sessionKey}"))?.AsArray();
            if (pits == null) return;
            foreach (var p in pits.OfType<JsonObject>())
            {
                var key = p["driver_number"]?.ToString() ?? "";
                var lapNumber = p["lap_number"]?.GetValue<int>() ?? 0;
                var duration = p["pit_duration"]?.GetValue<double?>();
                if (duration == null) continue;
                if (!_pitDurByDriver.TryGetValue(key, out var map)) _pitDurByDriver[key] = map = new();
                map[lapNumber] = duration.Value;
            }
            Console.WriteLine($"[OpenF1Adapter] Fetched pit data: {pits.Count} pit stop(s).");
        }
        catch (Exception ex) { Console.WriteLine($"[OpenF1Adapter] Could not fetch pit data: {ex.Message}"); }
    }

    private async Task FetchAndEmitDriversAsync()
    {
        try
        {
            var drivers = (await GetAsync($"/v1/drivers?session_key={_sessionKey}"))?.AsArray();
            if (drivers is not { Count: > 0 }) return;
            SessionReceived?.Invoke(new SessionEvent { Type = "f1drivers", Payload = drivers });
        }
        catch (Exception ex) { Console.WriteLine($"[OpenF1Adapter] Could not fetch driver roster: {ex.Message}"); }
    }

    private Lap NormaliseLap(JsonObject raw)
    {
        var key = raw["driver_number"]?.ToString() ?? "";

        if (!_outingByDriver.ContainsKey(key))
        {
            _outingByDriver[key] = 1;
            _lapsSincePitMap[key] = 0;
        }

        var outing = _outingByDriver[key];
        var lapsSincePit = _lapsSincePitMap[key];
        var isPitOutLap = raw["is_pit_out_lap"]?.GetValue<bool>() ?? false;

        if (isPitOutLap)
        {
            outing++;
            lapsSincePit = 0;
            _outingByDriver[key] = outing;
        }
        else
        {
            lapsSincePit++;
        }
        _lapsSincePitMap[key] = lapsSincePit;

        var lapNumber = raw["lap_number"]?.GetValue<int>() ?? 0;
        var lapDuration = raw["lap_duration"]?.GetValue<double?>();

        var hasPitData = _pitDurByDriver.Count > 0;
        var isPitLap = hasPitData
            ? _pitDurByDriver.TryGetValue(key, out var m) && m.ContainsKey(lapNumber)
            : lapDuration == null && !isPitOutLap;

        double? pitDuration = _pitDurByDriver.TryGetValue(key, out var m2) && m2.TryGetValue(lapNumber, out var d) ? d : null;

        var dateStart = raw["date_start"]?.ToString();
        long? lapStartTs = dateStart != null ? DateTimeOffset.Parse(dateStart).ToUnixTimeMilliseconds() : null;
        var lapEndTs = lapStartTs != null ? lapStartTs.Value + (long)((lapDuration ?? 0) * 1000) : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        return new Lap
        {
            CarNumber = key,
            LapNumber = lapNumber,
            LapTime = lapDuration,
            S1 = raw["duration_sector_1"]?.GetValue<double?>(),
            S2 = raw["duration_sector_2"]?.GetValue<double?>(),
            S3 = raw["duration_sector_3"]?.GetValue<double?>(),
            Position = PositionAt(key, lapEndTs),
            IsPitLap = isPitLap,
            PitDuration = pitDuration,
            Outing = outing,
            LapsSincePit = lapsSincePit,
            Timestamp = lapStartTs ?? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
        };
    }

    private static SessionEvent NormaliseRaceControl(JsonObject raw)
    {
        var type = "info";
        var msg = (raw["message"]?.ToString() ?? "").ToUpperInvariant();
        if (msg.Contains("SAFETY CAR") && !msg.Contains("VIRTUAL")) type = "sc";
        else if (msg.Contains("VIRTUAL SAFETY CAR")) type = "vsc";
        else if (msg.Contains("FLAG")) type = "flag";

        return new SessionEvent
        {
            Type = type,
            Payload = new
            {
                message = raw["message"]?.ToString(),
                category = raw["category"]?.ToString(),
                flag = raw["flag"]?.ToString(),
                lapNumber = raw["lap_number"]?.GetValue<int?>(),
                rawDate = raw["date"]?.ToString(),
            },
        };
    }
}
