using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Core.Feeds;

/// <summary>
/// Timing feed adapter for the official Supercars Championship TCP timing stream.
/// Ported from adapter_supercars.js.
///
/// Protocol: binary-framed XML: "!@#" + 5-digit decimal length + 2-byte sequence
/// id + N bytes of XML payload.
/// </summary>
public sealed partial class SupercarsTcpAdapter : IFeedAdapter
{
    public event Action<Lap>? LapReceived;
    public event Action<SessionEvent>? SessionReceived;
    public event Action<string>? RawMessageReceived;

    private TcpClient? _client;
    private NetworkStream? _stream;
    private CancellationTokenSource? _cts;
    private byte[] _buf = Array.Empty<byte>();
    private string _host = "127.0.0.1";
    private int _port = 5000;
    private bool _connected;

    // Internal competitor ID -> car info
    private readonly Dictionary<string, Competitor> _competitors = new();

    // Per-car state
    private readonly Dictionary<string, int> _lastLap = new();
    private readonly Dictionary<string, int> _lastPitStops = new();
    private readonly Dictionary<string, string> _lastOutLap = new();
    private readonly Dictionary<string, int> _lapsSinceExit = new();
    private readonly Dictionary<string, string> _lastTyre = new();
    private readonly Dictionary<string, double> _sfToc = new();
    private readonly Dictionary<string, double> _int1Toc = new();
    private readonly Dictionary<string, double> _int2Toc = new();

    private string _flagState = "Green";

    private sealed record Competitor(string CarNumber, string Name, string ShortName, string TeamCode, string Vehicle);

    public async Task ConnectAsync(FeedProfile profile, JsonObject? trackConfig, CancellationToken ct)
    {
        var s = profile.Settings;
        _host = s["host"]?.GetValue<string>() ?? "127.0.0.1";
        _port = s["port"]?.GetValue<int>() ?? 5000;

        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        await OpenSocketAsync(_cts.Token);
        _connected = true;
        Console.WriteLine($"[SupercarsTcpAdapter] Connected: {_host}:{_port}");
    }

    public void Disconnect()
    {
        _connected = false;
        _cts?.Cancel();
        _stream?.Dispose();
        _client?.Dispose();
        Console.WriteLine("[SupercarsTcpAdapter] Disconnected: user request");
    }

    public FeedStatus Status() => new(_connected, "supercars",
        _connected ? $"Supercars timing {_host}:{_port}" : "Not connected");

    // ── Socket management with auto-reconnect ────────────────────────────

    private async Task OpenSocketAsync(CancellationToken ct)
    {
        _buf = Array.Empty<byte>();
        _client = new TcpClient();
        await _client.ConnectAsync(_host, _port, ct);
        _stream = _client.GetStream();
        Console.WriteLine($"[SupercarsTcpAdapter] Socket connected to {_host}:{_port}");
        _ = Task.Run(() => ReadLoopAsync(ct), ct);
    }

    private async Task ReadLoopAsync(CancellationToken ct)
    {
        var chunk = new byte[8192];
        try
        {
            while (!ct.IsCancellationRequested)
            {
                int n = await _stream!.ReadAsync(chunk, 0, chunk.Length, ct);
                if (n == 0) break; // connection closed by remote
                var newBuf = new byte[_buf.Length + n];
                Buffer.BlockCopy(_buf, 0, newBuf, 0, _buf.Length);
                Buffer.BlockCopy(chunk, 0, newBuf, _buf.Length, n);
                _buf = newBuf;
                ProcessBuffer();
            }
        }
        catch (OperationCanceledException) { /* expected on disconnect */ }
        catch (Exception ex)
        {
            Console.WriteLine($"[SupercarsTcpAdapter] Socket error: {ex.Message}");
        }

        if (_connected && !ct.IsCancellationRequested)
        {
            Console.WriteLine("[SupercarsTcpAdapter] Connection closed — reconnecting in 5s…");
            await Task.Delay(5000, CancellationToken.None);
            if (_connected)
            {
                try { await OpenSocketAsync(ct); }
                catch (Exception ex) { Console.WriteLine($"[SupercarsTcpAdapter] Reconnect failed: {ex.Message}"); }
            }
        }
    }

    // ── Protocol framing: "!@#" + 5-digit length + 2-byte seq + N bytes XML ──

    private static readonly byte[] Marker = Encoding.ASCII.GetBytes("!@#");

    private void ProcessBuffer()
    {
        while (true)
        {
            var idx = IndexOf(_buf, Marker);
            if (idx < 0) { _buf = Array.Empty<byte>(); break; }
            if (idx > 0) _buf = _buf[idx..];

            if (_buf.Length < 10) break;

            var lenStr = Encoding.ASCII.GetString(_buf, 3, 5);
            if (!int.TryParse(lenStr, out var payloadLen) || payloadLen < 0)
            {
                _buf = _buf[4..];
                continue;
            }

            if (_buf.Length < 10 + payloadLen) break;

            var xml = Encoding.UTF8.GetString(_buf, 10, payloadLen);
            _buf = _buf[(10 + payloadLen)..];

            RawMessageReceived?.Invoke(xml);
            try { HandleMessage(xml); }
            catch (Exception ex) { Console.WriteLine($"[SupercarsTcpAdapter] Message handler error: {ex.Message}"); }
        }
    }

    private static int IndexOf(byte[] haystack, byte[] needle)
    {
        if (haystack.Length < needle.Length) return -1;
        for (int i = 0; i <= haystack.Length - needle.Length; i++)
        {
            var match = true;
            for (int j = 0; j < needle.Length; j++)
            {
                if (haystack[i + j] != needle[j]) { match = false; break; }
            }
            if (match) return i;
        }
        return -1;
    }

    // ── XML attribute helper (mirrors _attr() in the JS original) ────────

    [GeneratedRegex(@"[\s<](?<name>[A-Za-z0-9_]+)=(?:""(?<dq>[^""]*)""|'(?<sq>[^']*)')")]
    private static partial Regex AttrRegex();

    private static string? Attr(string xml, string name, string? fallback = null)
    {
        var re = new Regex($@"[\s<]{Regex.Escape(name)}=(?:""([^""]*)""|'([^']*)')");
        var m = re.Match(xml);
        if (!m.Success) return fallback;
        return m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value;
    }

    private static double? ParseSec(string? val)
    {
        if (string.IsNullOrEmpty(val) || val == "?" || val == "0.0000" || val == "0") return null;
        if (double.TryParse(val, System.Globalization.CultureInfo.InvariantCulture, out var n) && n > 0)
            return n;
        return null;
    }

    // ── Message routing ────────────────────────────────────────────────

    private void HandleMessage(string xml)
    {
        var t = xml.TrimStart();
        if (t.StartsWith("<New")) HandleNew(xml);
        else if (t.StartsWith("<Position")) HandlePosition(xml);
        else if (t.StartsWith("<Leaderboard")) HandleLeaderboard(xml);
        else if (t.StartsWith("<Passing")) HandlePassing(xml);
        else if (t.StartsWith("<Flag")) HandleFlag(xml);
        // <Change>, <Sectors>, <Status>, <Counters>, <Seen>, <Fastest>, <Message>
        // are captured in raw_messages but not yet parsed into panel-facing
        // events — track-map/sector-progression detail can be layered on later.
    }

    // ── Initial full snapshot ──────────────────────────────────────────

    [GeneratedRegex(@"<Competitor\b([^>]*)>([\s\S]*?)</Competitor>")]
    private static partial Regex CompetitorRegex();

    [GeneratedRegex(@"<Position\b[^>]*>([\s\S]*?)</Position>")]
    private static partial Regex PositionBlockRegex();

    [GeneratedRegex(@"<Driver\b([^>]*)")]
    private static partial Regex DriverRegex();

    [GeneratedRegex(@"<Event\b([^>]*)")]
    private static partial Regex EventRegex();

    private void HandleNew(string xml)
    {
        var parsedCount = 0;
        foreach (Match cm in CompetitorRegex().Matches(xml))
        {
            parsedCount++;
            ParseCompetitor(cm.Groups[1].Value, cm.Groups[2].Value);
        }
        Console.WriteLine($"[SupercarsTcpAdapter] Snapshot: {parsedCount} Competitor elements found, {_competitors.Count} stored.");

        foreach (Match pm in PositionBlockRegex().Matches(xml))
        {
            var posTag = pm.Value;
            var comp = Attr(posTag, "Comp");
            if (comp == null || !_competitors.TryGetValue(comp, out var car)) continue;

            var dStart = posTag.IndexOf("<Detail ", StringComparison.Ordinal);
            if (dStart < 0) continue;
            var d = posTag[dStart..];

            var lastLap = int.TryParse(Attr(d, "LastLap") ?? "0", out var ll) ? ll : 0;
            var pitStops = int.TryParse(Attr(d, "PitStops") ?? "0", out var ps) ? ps : 0;
            var outLap = Attr(d, "OutLap") ?? "N";
            var tyre = Attr(d, "Tyre") ?? "";
            var llp = int.TryParse(Attr(d, "LapsLastPit") ?? "0", out var l2) ? l2 : 0;

            _lastLap[car.CarNumber] = lastLap;
            _lastPitStops[car.CarNumber] = pitStops;
            _lastOutLap[car.CarNumber] = outLap;
            if (tyre != "") _lastTyre[car.CarNumber] = tyre;

            var approxLapsSince = outLap == "Y" ? 0 : Math.Max(0, lastLap - llp);
            _lapsSinceExit[car.CarNumber] = approxLapsSince;
        }

        EmitTrackInfo(xml);

        var raceSnapshot = _competitors.Values.Select(car => new
        {
            carNumber = car.CarNumber,
            pitStops = _lastPitStops.GetValueOrDefault(car.CarNumber, 0),
            lapsSincePit = _lapsSinceExit.GetValueOrDefault(car.CarNumber, 0),
            lastLap = _lastLap.GetValueOrDefault(car.CarNumber, 0),
            tyre = _lastTyre.GetValueOrDefault(car.CarNumber, (string?)null),
        }).ToList();
        SessionReceived?.Invoke(new SessionEvent { Type = "race-snapshot", Payload = raceSnapshot });

        EmitDrivers();
    }

    private void ParseCompetitor(string compAttrs, string compBody)
    {
        var id = Attr(compAttrs, "ID");
        var num = Attr(compAttrs, "Number");
        if (id == null || num == null)
        {
            Console.WriteLine("[SupercarsTcpAdapter] Skipping competitor — missing ID or Number");
            return;
        }

        var driverMatch = DriverRegex().Match(compBody);
        var driverAttrs = driverMatch.Success ? driverMatch.Groups[1].Value : "";
        var abbrev = Attr(driverAttrs, "AbbrevName") ?? "";
        var code = Attr(driverAttrs, "Code") ?? "";
        var name = (Attr(driverAttrs, "Name") ?? "").Replace('_', ' ');

        _competitors[id] = new Competitor(
            num,
            name,
            abbrev != "" ? abbrev : (code != "" ? code : num),
            Attr(compAttrs, "TeamCode") ?? "",
            Attr(compAttrs, "Vehicle") ?? "");
    }

    private void EmitDrivers()
    {
        var payload = _competitors.Values.Select(car => new
        {
            driver_number = car.CarNumber,
            team_colour = "888888",
            name_acronym = car.ShortName,
            full_name = car.Name,
            line_style = "solid",
            vehicle = car.Vehicle,
        }).ToList();
        SessionReceived?.Invoke(new SessionEvent { Type = "v8drivers", Payload = payload });
    }

    private void EmitTrackInfo(string xml)
    {
        var trackMatch = Regex.Match(xml, @"<Track\b([^>]*)>([\s\S]*?)</Track>");
        if (!trackMatch.Success) return;
        var trackAttrs = trackMatch.Groups[1].Value;
        var trackBody = trackMatch.Groups[2].Value;

        var lapLengthM = (double.TryParse(Attr(trackAttrs, "Length") ?? "0",
            System.Globalization.CultureInfo.InvariantCulture, out var lenKm) ? lenKm : 0) * 1000;

        var evMatch = EventRegex().Match(xml);
        var ev = evMatch.Success ? evMatch.Groups[1].Value : "";

        SessionReceived?.Invoke(new SessionEvent
        {
            Type = "track-info",
            Payload = new
            {
                trackCode = Attr(trackAttrs, "Code") ?? "",
                trackName = Attr(trackAttrs, "Name") ?? "",
                lapLengthM = double.IsFinite(lapLengthM) ? lapLengthM : (double?)null,
                eventCode = Attr(ev, "Code") ?? "",
                eventName = Attr(ev, "Description1") ?? "",
                scheduledLaps = int.TryParse(Attr(ev, "Laps") ?? "0", out var laps) && laps > 0 ? laps : (int?)null,
                tyre = Attr(ev, "Tyre") ?? "",
            },
        });
    }

    // ── Leaderboard / Position (lap completion) ─────────────────────────

    private void HandleLeaderboard(string xml)
    {
        foreach (Match m in Regex.Matches(xml, @"<Position\b[\s\S]*?</Position>"))
        {
            HandlePosition(m.Value);
        }
    }

    private void HandlePosition(string xml)
    {
        var comp = Attr(xml, "Comp");
        if (comp == null || !_competitors.TryGetValue(comp, out var car)) return;

        var dStart = xml.IndexOf("<Detail ", StringComparison.Ordinal);
        if (dStart < 0) return;
        var d = xml[dStart..];

        var lastLap = int.TryParse(Attr(d, "LastLap") ?? "0", out var ll) ? ll : 0;
        var prevLap = _lastLap.GetValueOrDefault(car.CarNumber, 0);
        if (lastLap <= prevLap) return; // no new completed lap

        var racePos = int.TryParse(Attr(d, "Pos") ?? "0", out var pos) && pos > 0 ? pos : (int?)null;
        var speedTrap = int.TryParse(Attr(d, "SpeedTrap") ?? "0", out var st) && st > 0 ? st : (int?)null;
        var pitStops = int.TryParse(Attr(d, "PitStops") ?? "0", out var ps) ? ps : 0;
        var isFirstSeen = !_lastPitStops.ContainsKey(car.CarNumber);
        if (isFirstSeen) _lastPitStops[car.CarNumber] = pitStops;
        var prevPit = isFirstSeen ? pitStops : _lastPitStops.GetValueOrDefault(car.CarNumber, 0);
        var outLap = Attr(d, "OutLap") ?? "N";
        var tyre = Attr(d, "Tyre") ?? "";
        var lastTime = double.TryParse(Attr(d, "LastTime") ?? "0", System.Globalization.CultureInfo.InvariantCulture, out var lt) && lt > 0 ? lt : (double?)null;
        var lastTOD = Attr(d, "LastTOD");
        var pitLaneTime = double.TryParse(Attr(d, "PitLaneTime") ?? "0", System.Globalization.CultureInfo.InvariantCulture, out var plt) ? plt : 0;

        var isInLap = !isFirstSeen && pitStops > prevPit;
        var isPitLap = isInLap;

        var outing = isInLap ? prevPit + 1 : pitStops + 1;

        int lapsSincePit;
        if (isInLap)
        {
            lapsSincePit = _lapsSinceExit.GetValueOrDefault(car.CarNumber, 0);
            _lapsSinceExit[car.CarNumber] = -1;
        }
        else if (outLap == "Y")
        {
            lapsSincePit = 0;
            _lapsSinceExit[car.CarNumber] = 0;
        }
        else
        {
            var prevSince = _lapsSinceExit.GetValueOrDefault(car.CarNumber, -999);
            lapsSincePit = prevSince != -999 ? prevSince + 1 : 1;
            _lapsSinceExit[car.CarNumber] = lapsSincePit;
        }

        var pitDuration = isInLap && pitLaneTime > 0 ? pitLaneTime : (double?)null;

        var lapTime = (outLap == "Y" || isInLap || lastTime is null || lastTime <= 0) ? null : lastTime;

        var inLapSegmentTime = isInLap && lastTime > 0 ? lastTime : (double?)null;
        var outLapSegmentTime = outLap == "Y" && lastTime > 0 ? lastTime : (double?)null;

        double? s1 = null, s2 = null, s3 = null;
        if (lapTime != null)
        {
            s3 = ParseSec(Attr(d, "LastSec3Time"));

            var carNum = car.CarNumber;
            var sfToc = _sfToc.GetValueOrDefault(carNum, double.NaN);
            var int1Toc = _int1Toc.GetValueOrDefault(carNum, double.NaN);
            var int2Toc = _int2Toc.GetValueOrDefault(carNum, double.NaN);

            if (!double.IsNaN(sfToc) && !double.IsNaN(int1Toc))
            {
                var derived1 = int1Toc - sfToc;
                if (derived1 is > 0 and < 200) s1 = derived1;
            }
            if (!double.IsNaN(int1Toc) && !double.IsNaN(int2Toc))
            {
                var derived2 = int2Toc - int1Toc;
                if (derived2 is > 0 and < 200) s2 = derived2;
            }
        }

        var lapEndSec = lastTOD != null && double.TryParse(lastTOD, System.Globalization.CultureInfo.InvariantCulture, out var tod) ? tod : (double?)null;
        var timestamp = lapEndSec != null ? (long)(lapEndSec.Value * 1000) : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        var yellowFlag = _flagState != "Green";

        _lastLap[car.CarNumber] = lastLap;
        _lastPitStops[car.CarNumber] = pitStops;
        _lastOutLap[car.CarNumber] = outLap;
        if (tyre != "") _lastTyre[car.CarNumber] = tyre;

        LapReceived?.Invoke(new Lap
        {
            CarNumber = car.CarNumber,
            LapNumber = lastLap,
            LapTime = lapTime,
            S1 = s1,
            S2 = s2,
            S3 = s3,
            Position = racePos,
            IsPitLap = isPitLap,
            Outing = outing,
            LapsSincePit = lapsSincePit,
            PitDuration = pitDuration,
            Tyre = tyre != "" ? tyre : null,
            YellowFlag = yellowFlag,
            Timestamp = timestamp,
            InLapSegmentTime = inLapSegmentTime,
            OutLapSegmentTime = outLapSegmentTime,
            SpeedTrap = speedTrap,
            DriverName = car.Name,
            Vehicle = car.TeamCode,
        });
    }

    // ── Timing loop crossings ───────────────────────────────────────────

    private static readonly HashSet<int> PositionTypes = new() { 1, 5, 6, 71, 72, 73, 74, 75, 76 };

    private void HandlePassing(string xml)
    {
        var id = Attr(xml, "ID");
        if (id == null || !_competitors.TryGetValue(id, out var car)) return;

        var loopType = int.TryParse(Attr(xml, "Type") ?? "0", out var lt) ? lt : 0;
        var time = double.TryParse(Attr(xml, "Time") ?? "0", System.Globalization.CultureInfo.InvariantCulture, out var t) ? t : 0;
        var sector = int.TryParse(Attr(xml, "Sector") ?? "0", out var sec) ? sec : 0;

        if (!PositionTypes.Contains(loopType)) return;

        if (time > 0)
        {
            var carNum = car.CarNumber;
            if (loopType == 1)
            {
                _sfToc[carNum] = time;
                _int1Toc.Remove(carNum);
                _int2Toc.Remove(carNum);
            }
            else if (loopType == 5) _int1Toc[carNum] = time;
            else if (loopType == 6) _int2Toc[carNum] = time;
        }

        SessionReceived?.Invoke(new SessionEvent
        {
            Type = "passing",
            Payload = new Passing
            {
                CarNumber = car.CarNumber,
                LoopType = loopType,
                Time = time,
                Sector = sector,
                LapNumber = _lastLap.GetValueOrDefault(car.CarNumber, 0),
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            },
        });
    }

    // ── Flag / safety car state ─────────────────────────────────────────

    private void HandleFlag(string xml)
    {
        var status = Attr(xml, "Status") ?? "";
        var subStatus = Attr(xml, "SubStatus") ?? "";

        if (status == "Yellow" || subStatus == "SafetyCar") _flagState = "Yellow";
        else if (status == "Green") _flagState = "Green";
        else if (status == "Checkered") _flagState = "Checkered";
        else if (status == "Red") _flagState = "Red";
        else if (status == "End") _flagState = "End";

        SessionReceived?.Invoke(new SessionEvent
        {
            Type = "flag",
            Payload = new { flag = _flagState, rawDate = Attr(xml, "TOD") },
        });
    }
}
