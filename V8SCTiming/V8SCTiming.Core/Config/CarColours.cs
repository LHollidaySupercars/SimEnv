using System.Text.Json;
using System.Text.RegularExpressions;

namespace V8SCTiming.Core.Config;

public class CarColourEntry
{
    public string ShortName { get; set; } = "";
    public string Name { get; set; } = "";
    public string Colour { get; set; } = "#888888";
    public string LineStyle { get; set; } = "solid";
}

/// <summary>
/// Single source of truth for car colours across all feed adapters.
/// Ported from car_colours.js. Manages config/cars.json — a flat map keyed by
/// car number. New cars get the next palette colour/line style; existing
/// entries' colour/lineStyle are preserved (user preference), while
/// name/shortName are refreshed from live data.
/// </summary>
public sealed partial class CarColours
{
    private static readonly string[] Palette =
    {
        "#FF4444", "#44BBFF", "#44FF88", "#FFB344", "#BB44FF", "#FF44BB",
        "#44FFFF", "#FF8844", "#FFFF44", "#FF4488", "#88BBFF", "#AA44FF",
    };
    private static readonly string[] LineStyles = { "solid", "dashed", "dotted" };

    private readonly string _filePath;
    private Dictionary<string, CarColourEntry> _cars = new();
    private int _palIdx;
    private int _styleIdx;

    public CarColours(string filePath)
    {
        _filePath = filePath;
    }

    public CarColours Load()
    {
        try
        {
            if (File.Exists(_filePath))
            {
                var raw = File.ReadAllText(_filePath);
                _cars = JsonSerializer.Deserialize<Dictionary<string, CarColourEntry>>(raw,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
                var count = _cars.Count;
                _palIdx = count % Palette.Length;
                _styleIdx = (count / Palette.Length) % LineStyles.Length;
                Console.WriteLine($"[CarColours] Loaded {count} cars from {_filePath}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[CarColours] Could not load cars.json: {ex.Message}");
            _cars = new();
        }
        return this;
    }

    public record CarDescriptor(string CarNumber, string? ShortName, string? Name, string? Colour);

    [GeneratedRegex("^#[0-9a-fA-F]{6}$")]
    private static partial Regex HexColourRegex();

    public void Merge(IEnumerable<CarDescriptor> cars)
    {
        var changed = false;

        foreach (var car in cars)
        {
            var key = (car.CarNumber ?? "").Trim();
            if (key.Length == 0) continue;

            if (!_cars.TryGetValue(key, out var existing))
            {
                var colour = !string.IsNullOrEmpty(car.Colour) && HexColourRegex().IsMatch(car.Colour)
                    ? car.Colour
                    : Palette[_palIdx % Palette.Length];
                var lineStyle = LineStyles[_styleIdx % LineStyles.Length];

                _cars[key] = new CarColourEntry
                {
                    ShortName = car.ShortName ?? key,
                    Name = car.Name ?? "",
                    Colour = colour,
                    LineStyle = lineStyle,
                };

                _palIdx++;
                if (_palIdx % Palette.Length == 0)
                {
                    _styleIdx = (_styleIdx + 1) % LineStyles.Length;
                }
                changed = true;
            }
            else
            {
                // Existing car — preserve colour/lineStyle (user preference); refresh
                // name/shortName from the live feed (facts, not preferences).
                if (!string.IsNullOrEmpty(car.Name) && car.Name != existing.Name) { existing.Name = car.Name; changed = true; }
                if (!string.IsNullOrEmpty(car.ShortName) && car.ShortName != existing.ShortName) { existing.ShortName = car.ShortName; changed = true; }
            }
        }

        if (changed) Save();
    }

    public IReadOnlyDictionary<string, CarColourEntry> GetAll() => _cars;

    /// <summary>
    /// F1-compatible array shape expected by panel onDrivers() implementations:
    /// [{ driver_number, team_colour (no '#'), name_acronym, full_name, line_style }]
    /// </summary>
    public List<Dictionary<string, string>> ToF1Array() =>
        _cars.Select(kv => new Dictionary<string, string>
        {
            ["driver_number"] = kv.Key,
            ["team_colour"] = (kv.Value.Colour ?? "#888888").Replace("#", ""),
            ["name_acronym"] = string.IsNullOrEmpty(kv.Value.ShortName) ? kv.Key : kv.Value.ShortName,
            ["full_name"] = kv.Value.Name ?? "",
            ["line_style"] = string.IsNullOrEmpty(kv.Value.LineStyle) ? "solid" : kv.Value.LineStyle,
        }).ToList();

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            var options = new JsonSerializerOptions { WriteIndented = true };
            File.WriteAllText(_filePath, JsonSerializer.Serialize(_cars, options));
            Console.WriteLine($"[CarColours] Saved {_cars.Count} cars to {_filePath}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[CarColours] Could not save cars.json: {ex.Message}");
        }
    }
}
