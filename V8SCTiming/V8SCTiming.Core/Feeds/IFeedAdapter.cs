using V8SCTiming.Core.Models;

namespace V8SCTiming.Core.Feeds;

/// <summary>
/// Interface all timing feed adapters must implement.
/// Ported from adapter_base.js. Concrete adapters (Supercars, OpenF1, Replay)
/// implement this; the Logger drives whichever one is configured.
/// </summary>
public interface IFeedAdapter
{
    event Action<Lap>? LapReceived;
    event Action<SessionEvent>? SessionReceived;
    /// <summary>Raised for every raw message received, verbatim, before parsing — used for the raw archive.</summary>
    event Action<string>? RawMessageReceived;

    Task ConnectAsync(FeedProfile profile, System.Text.Json.Nodes.JsonObject? trackConfig, CancellationToken ct);
    void Disconnect();
    FeedStatus Status();
}

public record FeedProfile(string Id, string Type, System.Text.Json.Nodes.JsonObject Settings);

public record FeedStatus(bool Connected, string Type, string Detail);
