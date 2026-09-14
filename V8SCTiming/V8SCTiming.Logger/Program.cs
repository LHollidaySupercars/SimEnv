using System.Text.Json.Nodes;
using V8SCTiming.Core.Config;
using V8SCTiming.Core.Data;
using V8SCTiming.Core.Feeds;

namespace V8SCTiming.Logger;

/// <summary>
/// V8SCTiming.Logger — standalone, always-on capture process.
///
/// Connects to whichever timing feed is configured (Supercars TCP, OpenF1, or
/// Replay) and is the SOLE WRITER to the shared SQLite database: every raw
/// message is archived verbatim (raw_messages table) and every parsed lap /
/// passing is written as it arrives. Designed to run independently of the
/// Viewer — start it once, leave it running, and it keeps recording whether
/// or not you have the Viewer open.
///
/// Usage:
///   V8SCTiming.Logger.exe <profileId> [configDir] [dbPath]
///
/// profileId must match an "id" in config/profiles.json.
/// Defaults: configDir = ./config, dbPath = ./v8sctiming.db
/// </summary>
public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        var profileId = args.Length > 0 ? args[0] : null;
        var configDir = args.Length > 1 ? args[1] : Path.Combine(AppContext.BaseDirectory, "config");
        var dbPath = args.Length > 2 ? args[2] : Path.Combine(AppContext.BaseDirectory, "v8sctiming.db");

        if (profileId == null)
        {
            Console.WriteLine("Usage: V8SCTiming.Logger <profileId> [configDir] [dbPath]");
            Console.WriteLine();
            Console.WriteLine("Available profiles:");
            var cfgPreview = new ConfigManager(configDir);
            cfgPreview.Load();
            foreach (var p in cfgPreview.GetProfiles().OfType<JsonObject>())
                Console.WriteLine($"  {p["id"]} — {p["type"]} — {p["label"] ?? p["name"]}");
            return 1;
        }

        Console.WriteLine($"[Logger] Config dir: {configDir}");
        Console.WriteLine($"[Logger] Database:   {dbPath}");

        var cfg = new ConfigManager(configDir);
        cfg.Load();

        var profileObj = cfg.GetProfile(profileId)
            ?? throw new InvalidOperationException($"Profile \"{profileId}\" not found in profiles.json");

        var type = profileObj["type"]?.GetValue<string>() ?? throw new InvalidOperationException("Profile missing 'type'");
        var settings = profileObj["settings"] as JsonObject ?? new JsonObject();
        var trackId = profileObj["trackId"]?.GetValue<string>();
        var track = trackId != null ? cfg.GetTrack(trackId) : null;

        IFeedAdapter adapter = type switch
        {
            "supercars" => new SupercarsTcpAdapter(),
            "openf1" => new OpenF1Adapter(),
            "replay" => new ReplayAdapter(),
            _ => throw new InvalidOperationException($"Unknown adapter type \"{type}\""),
        };

        var db = new TimingDb(dbPath);
        var carColoursPath = Path.Combine(configDir, "cars.json");
        var carColours = new CarColours(carColoursPath).Load();

        var sessionId = db.StartSession(
            profileId: profileId,
            trackId: trackId ?? "",
            trackName: track?["name"]?.GetValue<string>() ?? trackId ?? "Unknown",
            eventCode: null,
            eventName: null);
        Console.WriteLine($"[Logger] Session started: {sessionId}");

        var running = true;
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            running = false;
        };

        adapter.RawMessageReceived += payload =>
        {
            try { db.InsertRawMessage(sessionId, type, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), payload); }
            catch (Exception ex) { Console.WriteLine($"[Logger] Failed to write raw message: {ex.Message}"); }
        };

        adapter.LapReceived += lap =>
        {
            try
            {
                db.InsertLap(sessionId, lap);
                carColours.Merge(new[] { new CarColours.CarDescriptor(lap.CarNumber, null, lap.DriverName, null) });
                Console.WriteLine($"[Logger] Lap: car={lap.CarNumber} lap={lap.LapNumber} time={lap.LapTime} pos={lap.Position}");
            }
            catch (Exception ex) { Console.WriteLine($"[Logger] Failed to write lap: {ex.Message}"); }
        };

        adapter.SessionReceived += sessionEvent =>
        {
            try
            {
                if (sessionEvent.Type == "passing" && sessionEvent.Payload is Core.Models.Passing p)
                {
                    db.InsertPassing(sessionId, p);
                }
                // v8drivers / f1drivers / track-info / flag / race-snapshot events are
                // archived via the raw_messages capture already; structured storage for
                // these can be added to dedicated tables if the Viewer needs to query them
                // independently of raw payload replay.
            }
            catch (Exception ex) { Console.WriteLine($"[Logger] Failed to write session event: {ex.Message}"); }
        };

        Console.WriteLine($"[Logger] Connecting via profile \"{profileId}\" (type={type})…");
        using var cts = new CancellationTokenSource();
        await adapter.ConnectAsync(new FeedProfile(profileId, type, settings), track, cts.Token);

        Console.WriteLine("[Logger] Running. Press Ctrl+C to stop.");
        while (running)
        {
            await Task.Delay(500);
        }

        Console.WriteLine("[Logger] Shutting down…");
        adapter.Disconnect();
        db.CloseSession(sessionId);
        Console.WriteLine("[Logger] Session closed. Bye.");
        return 0;
    }
}
