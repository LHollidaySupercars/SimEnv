// ============================================================
// Azure Function — getLapStats
// HTTP Trigger: GET /api/getLapStats
//
// Storage moved from a wide dbo.lap_stats table (one column per
// channel-stat) to a narrow/long schema (dbo.LapStats + Channels/
// Sessions/Drivers lookup tables, exposed flat via dbo.vw_LapStats).
// This function reads the narrow view and PIVOTS it back into the
// exact same wide, one-row-per-lap JSON shape the dashboard has
// always consumed (columns like ground_speed_max, lap_time, etc.) —
// so no dashboard/consumer changes are needed even though the DB
// storage shape changed underneath it.
//
// Authentication is handled by the Function App's built-in
// Entra ID provider — only supercars.com accounts can reach this.
//
// SQL access via Managed Identity — no passwords stored.
// ============================================================

const sql = require('mssql');

// ── SQL CONFIG ───────────────────────────────────────────────
// Server and database read from App Settings (environment variables).
// Managed Identity auth — no username/password needed.
const SQL_CONFIG = {
    server:   process.env.SQL_SERVER,
    database: process.env.SQL_DATABASE,
    options: {
        encrypt:                true,
        trustServerCertificate: false,
    },
    authentication: {
        type: 'azure-active-directory-default',
    },
};

// ── CONSTANTS ────────────────────────────────────────────────
// Cap on narrow rows fetched from vw_LapStats per request. A single
// event can now produce 300,000+ narrow rows under the narrow/long
// schema (one row per lap x channel x stat). This was previously
// 50,000 (silently truncated data alphabetically by Team) then briefly
// 2,000,000 (caused a live 500 — the dashboard's old fetchRecent()
// fetched the ENTIRE unfiltered database on every page load, and
// removing the low cap let that attempt to actually pull everything at
// once, timing out / exhausting memory). The real fix is the dashboard
// now only fetching the specific event(s) it needs (see the ?meta=events
// endpoint below + smp_data.js's rewritten fetchRecent/fetchEvent) —
// this cap is kept as a sane per-request ceiling, not a load-bearing
// safety net for an unbounded query anymore.
const MAX_ROWS       = 400000;
const MAX_PARAM_LEN  = 50;

// ── CONNECTION POOL ──────────────────────────────────────────
// Reused across warm invocations — do not create per-request.
let _pool = null;

async function getPool() {
    if (_pool) {
        try {
            // Verify the pool is still alive
            await _pool.request().query('SELECT 1');
            return _pool;
        } catch (_) {
            _pool = null;
        }
    }
    _pool = await sql.connect(SQL_CONFIG);
    return _pool;
}

// ── ALLOWED ORIGIN ───────────────────────────────────────────
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || '';

// ── SECURITY + CORS HEADERS ─────────────────────────────────
function buildHeaders() {
    const h = {
        'Content-Type':                 'application/json',
        'X-Content-Type-Options':       'nosniff',
        'Cache-Control':                'no-store',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    };
    if (ALLOWED_ORIGIN) {
        h['Access-Control-Allow-Origin'] = ALLOWED_ORIGIN;
    }
    return h;
}

// ── STAT SUFFIX MAP ──────────────────────────────────────────
// StatType (as stored in LapStats) -> legacy wide-column suffix.
// Must match smp_flatten_stats.m's OPS table exactly so the pivoted
// column names are identical to what the old wide table produced.
const STAT_SUFFIX = {
    max:      'max',
    min:      'min',
    mean:     'mean',
    mean_nz:  'mean_nz',
    median:   'median',
    std:      'std',
    var:      'var',
    range:    'range',
    change:   'change',
    final:    'final',
    initial:  'initial',
};

function toSqlName(raw) {
    return String(raw)
        .toLowerCase()
        .replace(/[^a-z0-9_]/g, '_')
        .replace(/_+/g, '_')
        .replace(/^_|_$/g, '')
        .slice(0, 63) || 'ch';
}

// Pivot narrow vw_LapStats rows (one per lap+channel+stat) into the
// legacy wide shape (one row per lap, one column per channel_stat).
function pivotToWideRows(narrowRows) {
    const byLap = new Map();

    for (const row of narrowRows) {
        const key = [
            row.EventName, row.Venue, row.SessionName, row.Year,
            row.DriverName, row.Team, row.CarNumber, row.Manufacturer,
            row.LapNumber,
        ].join('||');

        if (!byLap.has(key)) {
            byLap.set(key, {
                event:        row.EventName,
                venue:        row.Venue,
                session:      row.SessionName,
                year:         row.Year,
                driver:       row.DriverName,
                team:         row.Team,
                car_number:   row.CarNumber,
                manufacturer: row.Manufacturer,
                lap_number:   row.LapNumber,
                math_version: row.MathVersion,
                source_file:  row.SourceFile,
            });
        }

        const wideRow = byLap.get(key);

        if (row.StatType === 'lap_time') {
            wideRow.lap_time = row.Value;
            continue;
        }

        const suffix = STAT_SUFFIX[row.StatType] || toSqlName(row.StatType);
        const colName = `${toSqlName(row.ChannelName)}_${suffix}`;
        wideRow[colName] = row.Value;
    }

    return Array.from(byLap.values());
}

// Merge in LapType from dbo.Laps (SessionID/DriverID/LapNumber keyed —
// resolved to the same natural key used above) onto already-pivoted wide
// rows. dbo.Laps is a newer/separate table from the LapStats narrow schema
// (added to classify each lap as flying/outlap/inlap/pitlap/pit_truncated/
// fcy), so this is a best-effort merge: if the table doesn't exist yet or
// the query fails for any reason, we log and continue without lap_type
// rather than failing the whole getLapStats response.
async function mergeLapTypes(pool, wideRows, where, request) {
    try {
        const laps = pool.request();
        if (request.parameters.event)   laps.input('event', sql.NVarChar(MAX_PARAM_LEN), request.parameters.event.value);
        if (request.parameters.session) laps.input('session', sql.NVarChar(MAX_PARAM_LEN), request.parameters.session.value);

        const result = await laps.query(`
            SELECT s.EventName, s.Venue, s.SessionName, s.Year,
                   d.DriverName, d.Team, d.CarNumber, d.Manufacturer,
                   l.LapNumber, l.LapType
            FROM dbo.Laps l
            JOIN dbo.Sessions s ON s.SessionID = l.SessionID
            JOIN dbo.Drivers  d ON d.DriverID  = l.DriverID
            WHERE 1=1 ${where}
        `);

        const byKey = new Map();
        result.recordset.forEach(r => {
            const key = [r.EventName, r.Venue, r.SessionName, r.Year, r.DriverName, r.Team, r.CarNumber, r.Manufacturer, r.LapNumber].join('||');
            byKey.set(key, r.LapType);
        });

        wideRows.forEach(row => {
            const key = [row.event, row.venue, row.session, row.year, row.driver, row.team, row.car_number, row.manufacturer, row.lap_number].join('||');
            if (byKey.has(key)) row.lap_type = byKey.get(key);
        });
    } catch (err) {
        // dbo.Laps may not exist yet in every environment, or be mid-reload —
        // don't fail the main response over it.
        console.log('mergeLapTypes skipped:', err.message);
    }
}


// ── MAIN HANDLER ─────────────────────────────────────────────
module.exports = async function (context, req) {

    context.log('getLapStats invoked');

    const headers = buildHeaders();

    // Handle preflight OPTIONS request
    if (req.method === 'OPTIONS') {
        context.res = { status: 204, headers };
        return;
    }

    // ── VALIDATE QUERY PARAMS ─────────────────────────────────
    // e.g. GET /api/getLapStats?event=AGP&session=RA4
    const eventFilter   = req.query.event   || null;
    const sessionFilter = req.query.session || null;
    const metaRequest   = req.query.meta    || null;   // 'events' | 'channels' — see below

    if (eventFilter && eventFilter.length > MAX_PARAM_LEN) {
        context.res = { status: 400, headers, body: JSON.stringify({ error: 'Invalid event parameter' }) };
        return;
    }
    if (sessionFilter && sessionFilter.length > MAX_PARAM_LEN) {
        context.res = { status: 400, headers, body: JSON.stringify({ error: 'Invalid session parameter' }) };
        return;
    }

    // ── LIGHTWEIGHT METADATA MODE ─────────────────────────────
    // ?meta=events — returns just the distinct event names that exist
    // (queries the small dbo.Sessions table, NOT the huge LapStats join),
    // so the dashboard can figure out which event(s) to auto-load WITHOUT
    // pulling the entire multi-hundred-thousand-row dataset unfiltered on
    // every page load. That unfiltered full-database fetch is what made
    // a low MAX_ROWS cap seem necessary in the first place, and caused a
    // 500 (timeout/OOM) once MAX_ROWS was raised — this endpoint is the
    // real fix, not a bigger cap.
    if (metaRequest === 'events') {
        try {
            const pool = await getPool();
            const result = await pool.request().query('SELECT DISTINCT EventName FROM dbo.Sessions');
            context.res = {
                status:  200,
                headers,
                body:    JSON.stringify({ events: result.recordset.map(r => r.EventName) }),
            };
        } catch (err) {
            context.log.error('SQL error (meta=events):', err.message);
            context.res = { status: 500, headers, body: JSON.stringify({ error: 'Database query failed' }) };
        }
        return;
    }

    // ?meta=channels — returns the distinct wide column names (e.g.
    // 'ground_speed_max') actually present in dbo.LapStats right now, built
    // with the exact same toSqlName/STAT_SUFFIX logic pivotToWideRows uses,
    // so newly-uploaded channels show up in the dashboard's channel pickers
    // without anyone hand-editing smp_config.js or rerunning
    // smp_generate_config.m. Queries ChannelID/StatType only (no Value, no
    // join needed against Sessions/Drivers/Laps) — a distinct scan of the
    // clustered index, same cost class as the rest of this narrow schema.
    if (metaRequest === 'channels') {
        try {
            const pool = await getPool();
            const result = await pool.request().query(`
                SELECT DISTINCT c.Name AS ChannelName, ls.StatType
                FROM dbo.LapStats ls
                JOIN dbo.Channels c ON c.ChannelID = ls.ChannelID
            `);
            const names = new Set();
            result.recordset.forEach(row => {
                if (row.StatType === 'lap_time') {
                    names.add('lap_time');
                    return;
                }
                const suffix = STAT_SUFFIX[row.StatType] || toSqlName(row.StatType);
                names.add(`${toSqlName(row.ChannelName)}_${suffix}`);
            });
            context.res = {
                status:  200,
                headers,
                body:    JSON.stringify({ channels: Array.from(names).sort() }),
            };
        } catch (err) {
            context.log.error('SQL error (meta=channels):', err.message);
            context.res = { status: 500, headers, body: JSON.stringify({ error: 'Database query failed' }) };
        }
        return;
    }

    try {
        const pool    = await getPool();
        const request = pool.request();

        // Build WHERE clause from optional filters (parameterised)
        let where = '';
        if (eventFilter) {
            request.input('event', sql.NVarChar(MAX_PARAM_LEN), eventFilter);
            where += ' AND EventName = @event';
        }
        if (sessionFilter) {
            request.input('session', sql.NVarChar(MAX_PARAM_LEN), sessionFilter);
            where += ' AND SessionName = @session';
        }

        // NOTE: MAX_ROWS caps narrow rows (one per lap+channel+stat), not
        // pivoted lap rows — each lap fans out into many narrow rows, so
        // this cap is intentionally generous relative to the old per-lap cap.
        request.input('maxRows', sql.Int, MAX_ROWS);

        const query = `
            SELECT TOP (@maxRows) * FROM [dbo].[vw_LapStats]
            WHERE 1=1 ${where}
            ORDER BY EventName, SessionName, Team, DriverName, LapNumber
        `;

        const result   = await request.query(query);
        const wideRows = pivotToWideRows(result.recordset);

        // ── Truncation detection ─────────────────────────────────
        // If we got exactly MAX_ROWS back, the TOP clause almost
        // certainly cut off real data rather than happening to land on
        // the DB's exact total row count — surface this loudly (server
        // log + a response flag) instead of silently returning partial
        // results, which is what caused teams sorted later alphabetically
        // to vanish from the dashboard without any error before this fix.
        const truncated = result.recordset.length >= MAX_ROWS;
        if (truncated) {
            context.log.warn(`getLapStats: hit MAX_ROWS cap (${MAX_ROWS}) — response is TRUNCATED. ` +
                'Raise MAX_ROWS or scope the request with event/session filters.');
        }

        await mergeLapTypes(pool, wideRows, where.replace(/\bEventName\b/g, 's.EventName').replace(/\bSessionName\b/g, 's.SessionName'), request);

        context.log(`Returning ${wideRows.length} pivoted row(s) from ${result.recordset.length} narrow row(s)`);

        context.res = {
            status:  200,
            headers,
            body:    JSON.stringify({
                items:      wideRows,
                totalItems: wideRows.length,
                truncated:  truncated,
            }),
        };

    } catch (err) {
        context.log.error('SQL error:', err.message);
        context.res = {
            status:  500,
            headers,
            body:    JSON.stringify({ error: 'Database query failed' }),
        };
    }
};
