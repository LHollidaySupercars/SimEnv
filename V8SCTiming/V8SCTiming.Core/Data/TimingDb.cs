using System;
using Microsoft.Data.Sqlite;

namespace V8SCTiming.Core.Data;

/// <summary>
/// Shared SQLite database access layer, used by both the Logger (writer) and the
/// Viewer (reader). Ported from the original Electron app's db_local.js.
///
/// Schema
/// ------
/// sessions        one row per connect/replay session
/// laps            one row per completed lap
/// passings        one row per timing-loop crossing
/// raw_messages    NEW: every raw message received from a feed, verbatim, for
///                 permanent archival/debugging. Written only by the Logger.
///
/// WAL mode is enabled so the Viewer can read while the Logger writes.
/// </summary>
public sealed class TimingDb : IDisposable
{
    private readonly string _connectionString;

    public TimingDb(string dbPath)
    {
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = dbPath,
            Cache = SqliteCacheMode.Shared,
        }.ToString();

        using var conn = Open();
        conn.Execute("PRAGMA journal_mode=WAL;");
        conn.Execute("PRAGMA foreign_keys=ON;");
        CreateSchema(conn);
    }

    public SqliteConnection Open()
    {
        var conn = new SqliteConnection(_connectionString);
        conn.Open();
        return conn;
    }

    private static void CreateSchema(SqliteConnection conn)
    {
        conn.Execute(@"
            CREATE TABLE IF NOT EXISTS sessions (
                id          TEXT    PRIMARY KEY,
                profileId   TEXT    NOT NULL,
                trackId     TEXT    NOT NULL,
                trackName   TEXT    NOT NULL,
                startedAt   INTEGER NOT NULL,
                status      TEXT    NOT NULL DEFAULT 'open',
                closedAt    INTEGER,
                eventCode   TEXT,
                eventName   TEXT
            );

            CREATE TABLE IF NOT EXISTS laps (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                sessionId         TEXT    NOT NULL REFERENCES sessions(id),
                carNumber         TEXT    NOT NULL,
                lapNumber         INTEGER NOT NULL,
                lapTime           REAL,
                s1                REAL,
                s2                REAL,
                s3                REAL,
                isPitLap          INTEGER NOT NULL DEFAULT 0,
                outing            INTEGER NOT NULL DEFAULT 0,
                lapsSincePit      INTEGER NOT NULL DEFAULT 0,
                position          INTEGER,
                tyre              TEXT,
                pitDuration       REAL,
                yellowFlag        INTEGER NOT NULL DEFAULT 0,
                timestamp         INTEGER NOT NULL,
                inLapSegmentTime  REAL,
                outLapSegmentTime REAL,
                speedTrap         REAL,
                driverName        TEXT,
                vehicle           TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_laps_session ON laps (sessionId);
            CREATE INDEX IF NOT EXISTS idx_laps_car ON laps (sessionId, carNumber, lapNumber);

            CREATE TABLE IF NOT EXISTS passings (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                sessionId  TEXT    NOT NULL REFERENCES sessions(id),
                carNumber  TEXT    NOT NULL,
                loopType   INTEGER NOT NULL,
                time       REAL    NOT NULL,
                sector     INTEGER,
                lapNumber  INTEGER,
                timestamp  INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_passings_session ON passings (sessionId);

            -- NEW: raw feed archive. One row per message received by the Logger,
            -- verbatim, regardless of whether it parsed successfully. This is the
            -- permanent, source-of-truth capture the user asked for.
            CREATE TABLE IF NOT EXISTS raw_messages (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                sessionId  TEXT    NOT NULL REFERENCES sessions(id),
                source     TEXT    NOT NULL,   -- 'supercars' | 'openf1' | 'replay'
                timestamp  INTEGER NOT NULL,   -- Unix ms received
                payload    TEXT    NOT NULL    -- raw XML / JSON text
            );
            CREATE INDEX IF NOT EXISTS idx_raw_session ON raw_messages (sessionId, id);
        ");
    }

    // ── Session API ──────────────────────────────────────────────────────

    public string StartSession(string profileId, string trackId, string trackName,
        long? startedAt = null, string? eventCode = null, string? eventName = null)
    {
        var id = $"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}-{Guid.NewGuid().ToString("N")[..8]}";
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"INSERT INTO sessions (id, profileId, trackId, trackName, startedAt, status, eventCode, eventName)
                             VALUES ($id, $profileId, $trackId, $trackName, $startedAt, 'open', $eventCode, $eventName)";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.Parameters.AddWithValue("$profileId", profileId);
        cmd.Parameters.AddWithValue("$trackId", trackId);
        cmd.Parameters.AddWithValue("$trackName", trackName);
        cmd.Parameters.AddWithValue("$startedAt", startedAt ?? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        cmd.Parameters.AddWithValue("$eventCode", (object?)eventCode ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$eventName", (object?)eventName ?? DBNull.Value);
        cmd.ExecuteNonQuery();
        return id;
    }

    public void CloseSession(string sessionId)
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "UPDATE sessions SET status='closed', closedAt=$closedAt WHERE id=$id";
        cmd.Parameters.AddWithValue("$id", sessionId);
        cmd.Parameters.AddWithValue("$closedAt", DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        cmd.ExecuteNonQuery();
    }

    public string? GetOpenSessionId()
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT id FROM sessions WHERE status='open' ORDER BY startedAt DESC LIMIT 1";
        return cmd.ExecuteScalar() as string;
    }

    // ── Write API (Logger only) ──────────────────────────────────────────

    public void InsertLap(string sessionId, Models.Lap lap)
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO laps (sessionId, carNumber, lapNumber, lapTime, s1, s2, s3, isPitLap, outing,
                               lapsSincePit, position, tyre, pitDuration, yellowFlag, timestamp,
                               inLapSegmentTime, outLapSegmentTime, speedTrap, driverName, vehicle)
            VALUES ($sessionId, $carNumber, $lapNumber, $lapTime, $s1, $s2, $s3, $isPitLap, $outing,
                    $lapsSincePit, $position, $tyre, $pitDuration, $yellowFlag, $timestamp,
                    $inLapSegmentTime, $outLapSegmentTime, $speedTrap, $driverName, $vehicle)";
        cmd.Parameters.AddWithValue("$sessionId", sessionId);
        cmd.Parameters.AddWithValue("$carNumber", lap.CarNumber);
        cmd.Parameters.AddWithValue("$lapNumber", lap.LapNumber);
        cmd.Parameters.AddWithValue("$lapTime", (object?)lap.LapTime ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$s1", (object?)lap.S1 ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$s2", (object?)lap.S2 ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$s3", (object?)lap.S3 ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$isPitLap", lap.IsPitLap ? 1 : 0);
        cmd.Parameters.AddWithValue("$outing", lap.Outing);
        cmd.Parameters.AddWithValue("$lapsSincePit", lap.LapsSincePit);
        cmd.Parameters.AddWithValue("$position", (object?)lap.Position ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$tyre", (object?)lap.Tyre ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$pitDuration", (object?)lap.PitDuration ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$yellowFlag", lap.YellowFlag ? 1 : 0);
        cmd.Parameters.AddWithValue("$timestamp", lap.Timestamp);
        cmd.Parameters.AddWithValue("$inLapSegmentTime", (object?)lap.InLapSegmentTime ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$outLapSegmentTime", (object?)lap.OutLapSegmentTime ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$speedTrap", (object?)lap.SpeedTrap ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$driverName", (object?)lap.DriverName ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$vehicle", (object?)lap.Vehicle ?? DBNull.Value);
        cmd.ExecuteNonQuery();
    }

    public void InsertPassing(string sessionId, Models.Passing p)
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            INSERT INTO passings (sessionId, carNumber, loopType, time, sector, lapNumber, timestamp)
            VALUES ($sessionId, $carNumber, $loopType, $time, $sector, $lapNumber, $timestamp)";
        cmd.Parameters.AddWithValue("$sessionId", sessionId);
        cmd.Parameters.AddWithValue("$carNumber", p.CarNumber);
        cmd.Parameters.AddWithValue("$loopType", p.LoopType);
        cmd.Parameters.AddWithValue("$time", p.Time);
        cmd.Parameters.AddWithValue("$sector", (object?)p.Sector ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$lapNumber", (object?)p.LapNumber ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$timestamp", p.Timestamp);
        cmd.ExecuteNonQuery();
    }

    public void InsertRawMessage(string sessionId, string source, long timestamp, string payload)
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"INSERT INTO raw_messages (sessionId, source, timestamp, payload)
                             VALUES ($sessionId, $source, $timestamp, $payload)";
        cmd.Parameters.AddWithValue("$sessionId", sessionId);
        cmd.Parameters.AddWithValue("$source", source);
        cmd.Parameters.AddWithValue("$timestamp", timestamp);
        cmd.Parameters.AddWithValue("$payload", payload);
        cmd.ExecuteNonQuery();
    }

    // ── Read API (Viewer) ────────────────────────────────────────────────

    public long GetMaxLapId()
    {
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT IFNULL(MAX(id), 0) FROM laps";
        return (long)cmd.ExecuteScalar()!;
    }

    /// <summary>Returns laps with id greater than <paramref name="sinceId"/>, for live tailing.</summary>
    public List<(long Id, Models.Lap Lap)> GetLapsSince(string sessionId, long sinceId)
    {
        var result = new List<(long, Models.Lap)>();
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"SELECT id, carNumber, lapNumber, lapTime, s1, s2, s3, isPitLap, outing,
                                    lapsSincePit, position, tyre, pitDuration, yellowFlag, timestamp,
                                    inLapSegmentTime, outLapSegmentTime, speedTrap, driverName, vehicle
                             FROM laps WHERE sessionId=$sessionId AND id > $sinceId ORDER BY id ASC";
        cmd.Parameters.AddWithValue("$sessionId", sessionId);
        cmd.Parameters.AddWithValue("$sinceId", sinceId);
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var lap = new Models.Lap
            {
                CarNumber = reader.GetString(1),
                LapNumber = reader.GetInt32(2),
                LapTime = reader.IsDBNull(3) ? null : reader.GetDouble(3),
                S1 = reader.IsDBNull(4) ? null : reader.GetDouble(4),
                S2 = reader.IsDBNull(5) ? null : reader.GetDouble(5),
                S3 = reader.IsDBNull(6) ? null : reader.GetDouble(6),
                IsPitLap = reader.GetInt32(7) != 0,
                Outing = reader.GetInt32(8),
                LapsSincePit = reader.GetInt32(9),
                Position = reader.IsDBNull(10) ? null : reader.GetInt32(10),
                Tyre = reader.IsDBNull(11) ? null : reader.GetString(11),
                PitDuration = reader.IsDBNull(12) ? null : reader.GetDouble(12),
                YellowFlag = reader.GetInt32(13) != 0,
                Timestamp = reader.GetInt64(14),
                InLapSegmentTime = reader.IsDBNull(15) ? null : reader.GetDouble(15),
                OutLapSegmentTime = reader.IsDBNull(16) ? null : reader.GetDouble(16),
                SpeedTrap = reader.IsDBNull(17) ? null : reader.GetDouble(17),
                DriverName = reader.IsDBNull(18) ? null : reader.GetString(18),
                Vehicle = reader.IsDBNull(19) ? null : reader.GetString(19),
            };
            result.Add((reader.GetInt64(0), lap));
        }
        return result;
    }

    public List<Models.SessionRow> GetAllSessions()
    {
        var result = new List<Models.SessionRow>();
        using var conn = Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT id, profileId, trackId, trackName, startedAt, status, closedAt, eventCode, eventName FROM sessions ORDER BY startedAt DESC";
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            result.Add(new Models.SessionRow
            {
                Id = reader.GetString(0),
                ProfileId = reader.GetString(1),
                TrackId = reader.GetString(2),
                TrackName = reader.GetString(3),
                StartedAt = reader.GetInt64(4),
                Status = reader.GetString(5),
                ClosedAt = reader.IsDBNull(6) ? null : reader.GetInt64(6),
                EventCode = reader.IsDBNull(7) ? null : reader.GetString(7),
                EventName = reader.IsDBNull(8) ? null : reader.GetString(8),
            });
        }
        return result;
    }

    public void Dispose() { /* connections are opened/closed per-call; nothing persistent to dispose */ }
}

internal static class SqliteConnectionExtensions
{
    public static void Execute(this SqliteConnection conn, string sql)
    {
        using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.ExecuteNonQuery();
    }
}
