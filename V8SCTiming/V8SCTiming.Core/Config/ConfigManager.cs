using System.Text.Json;
using System.Text.Json.Nodes;

namespace V8SCTiming.Core.Config;

/// <summary>
/// Loads and caches all JSON config files from the config/ directory.
/// Ported from config_manager.js. Uses JsonNode (dynamic) so we don't need a
/// strict schema for every track/profile shape — matches the original's
/// loose JS object handling and lets existing config files be reused as-is.
/// </summary>
public sealed class ConfigManager
{
    private readonly string _dir;
    private JsonArray _profiles = new();
    private JsonObject _drivers = new();
    private JsonArray _championships = new();
    private readonly Dictionary<string, JsonObject> _tracks = new();

    public ConfigManager(string configDir)
    {
        _dir = configDir;
    }

    public void Load()
    {
        _profiles = ReadJson("profiles.json") as JsonArray ?? new JsonArray();
        _drivers = ReadJson("drivers.json") as JsonObject ?? new JsonObject();
        _championships = ReadJson("championships.json") as JsonArray ?? new JsonArray();
        _tracks.Clear();

        var tracksDir = Path.Combine(_dir, "tracks");
        if (Directory.Exists(tracksDir))
        {
            foreach (var file in Directory.GetFiles(tracksDir, "*.json"))
            {
                var track = ReadJson(Path.Combine("tracks", Path.GetFileName(file))) as JsonObject;
                var id = track?["id"]?.GetValue<string>();
                if (track != null && !string.IsNullOrEmpty(id))
                {
                    _tracks[id] = track;
                }
            }
        }

        Console.WriteLine($"[ConfigManager] Loaded {_profiles.Count} profile(s), {_tracks.Count} track(s).");
    }

    public JsonArray GetChampionships() => _championships;

    public JsonArray GetProfiles() => _profiles;

    public JsonObject? GetProfile(string id) =>
        _profiles.OfType<JsonObject>().FirstOrDefault(p => p["id"]?.GetValue<string>() == id);

    public void SaveProfileSettings(string id, JsonObject settings)
    {
        var profile = GetProfile(id) ?? throw new InvalidOperationException($"Profile \"{id}\" not found");
        var target = profile["settings"] as JsonObject ?? new JsonObject();
        foreach (var kv in settings)
        {
            target[kv.Key] = kv.Value?.DeepClone();
        }
        profile["settings"] = target;
        WriteJson("profiles.json", _profiles);
    }

    public IEnumerable<(string Id, string Name)> GetTrackList() =>
        _tracks.Values.Select(t => (t["id"]!.GetValue<string>(), t["name"]?.GetValue<string>() ?? t["id"]!.GetValue<string>()));

    public JsonObject? GetTrack(string id) => _tracks.TryGetValue(id, out var t) ? t : null;

    /// <summary>
    /// Merge dotted-key updates into a track config and persist to disk, e.g.
    /// { "pit.speedLimitKph": 40 }.
    /// </summary>
    public void SaveTrackSettings(string trackId, IDictionary<string, JsonNode?> updates)
    {
        var track = GetTrack(trackId) ?? throw new InvalidOperationException($"Track \"{trackId}\" not found");
        foreach (var (dotKey, val) in updates)
        {
            var parts = dotKey.Split('.');
            if (parts.Length == 1)
            {
                track[dotKey] = val;
            }
            else
            {
                var section = parts[0];
                var field = parts[1];
                var sectionObj = track[section] as JsonObject ?? new JsonObject();
                sectionObj[field] = val;
                track[section] = sectionObj;
            }
        }

        var tracksDir = Path.Combine(_dir, "tracks");
        var file = Directory.GetFiles(tracksDir, "*.json")
            .FirstOrDefault(f => Path.GetFileNameWithoutExtension(f) == trackId);
        if (file == null) throw new InvalidOperationException($"Track file for \"{trackId}\" not found on disk");
        WriteJson(Path.Combine("tracks", Path.GetFileName(file)), track);
    }

    public JsonObject GetDrivers() => _drivers;

    /// <summary>Flat list of all cars with team colour/name injected.</summary>
    public List<JsonObject> GetFlatCarList()
    {
        var cars = new List<JsonObject>();
        foreach (var teamNode in _drivers["teams"]?.AsArray() ?? new JsonArray())
        {
            if (teamNode is not JsonObject team) continue;
            foreach (var carNode in team["cars"]?.AsArray() ?? new JsonArray())
            {
                if (carNode is not JsonObject car) continue;
                var flat = (JsonObject)car.DeepClone();
                flat["teamId"] = team["id"]?.DeepClone();
                flat["teamName"] = team["name"]?.DeepClone();
                cars.Add(flat);
            }
        }
        return cars;
    }

    public JsonObject? GetCar(string number) =>
        GetFlatCarList().FirstOrDefault(c => c["number"]?.GetValue<string>() == number);

    public JsonObject? GetEventConfig(string? eventCode)
    {
        if (string.IsNullOrEmpty(eventCode)) return null;
        return ReadJson(Path.Combine("events", $"{eventCode}.json")) as JsonObject;
    }

    public void SaveEventConfig(string eventCode, JsonObject config)
    {
        if (string.IsNullOrEmpty(eventCode)) throw new ArgumentException("eventCode is required");
        var eventsDir = Path.Combine(_dir, "events");
        Directory.CreateDirectory(eventsDir);
        WriteJson(Path.Combine("events", $"{eventCode}.json"), config);
    }

    private JsonNode? ReadJson(string relPath)
    {
        var fullPath = Path.Combine(_dir, relPath);
        try
        {
            var raw = File.ReadAllText(fullPath);
            return JsonNode.Parse(raw);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[ConfigManager] Could not read \"{fullPath}\": {ex.Message}");
            return null;
        }
    }

    private void WriteJson(string relPath, JsonNode data)
    {
        var fullPath = Path.Combine(_dir, relPath);
        var options = new JsonSerializerOptions { WriteIndented = true };
        File.WriteAllText(fullPath, data.ToJsonString(options));
    }
}
