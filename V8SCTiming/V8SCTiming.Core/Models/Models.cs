namespace V8SCTiming.Core.Models;

/// <summary>A completed lap event, as emitted by any feed adapter.</summary>
public class Lap
{
    public string CarNumber { get; set; } = "";
    public int LapNumber { get; set; }
    public double? LapTime { get; set; }
    public double? S1 { get; set; }
    public double? S2 { get; set; }
    public double? S3 { get; set; }
    public bool IsPitLap { get; set; }
    public int Outing { get; set; }
    public int LapsSincePit { get; set; }
    public int? Position { get; set; }
    public string? Tyre { get; set; }
    public double? PitDuration { get; set; }
    public bool YellowFlag { get; set; }
    public long Timestamp { get; set; }
    public double? InLapSegmentTime { get; set; }
    public double? OutLapSegmentTime { get; set; }
    public double? SpeedTrap { get; set; }
    public string? DriverName { get; set; }
    public string? Vehicle { get; set; }
}

/// <summary>A timing-loop crossing event (Supercars Int1/Int2/position loops).</summary>
public class Passing
{
    public string CarNumber { get; set; } = "";
    public int LoopType { get; set; }
    public double Time { get; set; }
    public int? Sector { get; set; }
    public int? LapNumber { get; set; }
    public long Timestamp { get; set; }
}

/// <summary>Session-level event: flag change, safety car, track info, etc.</summary>
public class SessionEvent
{
    public string Type { get; set; } = ""; // 'flag' | 'sc' | 'vsc' | 'info' | 'passing'
    public object? Payload { get; set; }
}

public class SessionRow
{
    public string Id { get; set; } = "";
    public string ProfileId { get; set; } = "";
    public string TrackId { get; set; } = "";
    public string TrackName { get; set; } = "";
    public long StartedAt { get; set; }
    public string Status { get; set; } = "open";
    public long? ClosedAt { get; set; }
    public string? EventCode { get; set; }
    public string? EventName { get; set; }
}

/// <summary>Driver/car metadata (from cars.json).</summary>
public class CarInfo
{
    public string CarNumber { get; set; } = "";
    public string Colour { get; set; } = "#888888";
    public string? LineStyle { get; set; }
    public string? ShortName { get; set; }
    public string? Name { get; set; }
}
