// ============================================================
// Azure Function — getLapStats
// HTTP Trigger: GET /api/getLapStats
//
// Returns all rows from dbo.lap_stats as a JSON array.
// Authentication is handled by the Function App's built-in
// Entra ID provider — only supercars.com accounts can reach this.
//
// SQL access via Managed Identity — no passwords stored.
//
// Deploy this file to your Function App via VS Code Azure
// Functions extension or Azure Portal editor.
// ============================================================

const sql = require('mssql');

// ── SQL CONFIG ───────────────────────────────────────────────
// Managed Identity auth — no username/password needed.
// Replace YOUR_SERVER_NAME and YOUR_DATABASE_NAME with your values.
const SQL_CONFIG = {
    server:   'sc-sql-data.database.windows.net',
    database: 'motorsport-sql-data',
    options: {
        encrypt:                true,
        trustServerCertificate: false,
    },
    authentication: {
        type: 'azure-active-directory-default',
    },
};

// ── CONNECTION POOL ──────────────────────────────────────────
// Reused across warm invocations — do not create per-request.
let _pool = null;

async function getPool() {
    if (_pool) return _pool;
    _pool = await sql.connect(SQL_CONFIG);
    return _pool;
}

// ── MAIN HANDLER ─────────────────────────────────────────────
module.exports = async function (context, req) {

    context.log('getLapStats invoked');

    // ── CORS headers — allow the dashboard origin ─────────────
    const headers = {
        'Content-Type':                'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    };

    // Handle preflight OPTIONS request
    if (req.method === 'OPTIONS') {
        context.res = { status: 204, headers };
        return;
    }

    // ── OPTIONAL QUERY PARAMS ─────────────────────────────────
    // e.g. GET /api/getLapStats?event=AGP&session=RA4
    const eventFilter   = req.query.event   || null;
    const sessionFilter = req.query.session || null;

    try {
        const pool    = await getPool();
        const request = pool.request();

        // Build WHERE clause from optional filters
        let where = '';
        if (eventFilter) {
            request.input('event', sql.NVarChar, eventFilter);
            where += ' AND event = @event';
        }
        if (sessionFilter) {
            request.input('session', sql.NVarChar, sessionFilter);
            where += ' AND session = @session';
        }

        const query = `
            SELECT * FROM [dbo].[lap_stats]
            WHERE 1=1 ${where}
            ORDER BY event, session, team, driver, lap_number
        `;

        const result = await request.query(query);

        context.log(`Returning ${result.recordset.length} rows`);

        context.res = {
            status:  200,
            headers,
            body:    JSON.stringify({
                items:      result.recordset,
                totalItems: result.recordset.length,
            }),
        };

    } catch (err) {
        context.log.error('SQL error:', err.message);
        context.res = {
            status:  500,
            headers,
            body:    JSON.stringify({ error: 'Database query failed', detail: err.message }),
        };
    }
};
