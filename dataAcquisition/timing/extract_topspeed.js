'use strict';

// ── extract_topspeed.js ───────────────────────────────────────────────────────
// Extracts on-track top speed matrix data from a Supercars Speed Trap Report PDF.
// Each driver block has one row per 10-lap group; continuation rows are labelled
// 10 / 20 / 30 ... and contain speeds for laps offset+1 to offset+10.
//
// Output: one CSV row per (car, driver, lap, kph).
//
// Called internally by smp_extract_topspeed.m — not intended for direct use.
//
// Usage:
//   node extract_topspeed.js <pdf_path> [--event TAU] [--session R09]
// ─────────────────────────────────────────────────────────────────────────────

const fs   = require('fs');
const path = require('path');

let pdfParse;
try {
    pdfParse = require('pdf-parse');
} catch (e) {
    console.error('[ERROR] pdf-parse not found. Run: npm install');
    process.exit(1);
}

// ── CLI argument parsing ──────────────────────────────────────────────────────
const args = process.argv.slice(2);
if (args.length === 0 || args[0].startsWith('-')) {
    console.error('Usage: node extract_topspeed.js <pdf_path> [--event XXX] [--session YYY]');
    process.exit(1);
}

const pdfPath = args[0];
let event = '', session = '';
for (let i = 1; i < args.length; i++) {
    if (args[i] === '--event'   && args[i + 1]) event   = args[++i];
    if (args[i] === '--session' && args[i + 1]) session = args[++i];
}

if (!fs.existsSync(pdfPath)) {
    console.error(`[ERROR] PDF not found: ${pdfPath}`);
    process.exit(1);
}

const pdfDir  = path.dirname(pdfPath);
const pdfBase = path.basename(pdfPath, path.extname(pdfPath));
const csvOut  = path.join(pdfDir, `${pdfBase}_topspeed.csv`);

// ── Main ──────────────────────────────────────────────────────────────────────
(async () => {
    const buf  = fs.readFileSync(pdfPath);
    const data = await pdfParse(buf);

    const lines = data.text
        .split(/\r?\n/)
        .map(l => l.trimEnd());

    // ── Confirm this is a Speed Trap Report ───────────────────────────────────
    const fullText = lines.join(' ').toUpperCase();
    if (!fullText.includes('SPEED TRAP')) {
        console.error('[ERROR] This does not appear to be a Speed Trap Report.');
        console.error('        Title "SPEED TRAP" not found in PDF text.');
        process.exit(1);
    }

    // ── Find column header row ────────────────────────────────────────────────
    // A line whose tokens are consecutive integers starting at 1: "1  2  3 ... N"
    let headerIdx = -1;
    for (let i = 0; i < lines.length; i++) {
        const tokens = lines[i].trim().split(/\s+/);
        if (tokens.length >= 5 &&
            tokens.every(t => /^\d+$/.test(t)) &&
            parseInt(tokens[0], 10) === 1 &&
            parseInt(tokens[tokens.length - 1], 10) === tokens.length) {
            headerIdx = i;
            break;
        }
    }

    if (headerIdx === -1) {
        console.error('[ERROR] Cannot find column header row.');
        console.error('        Expected a line of consecutive integers starting at 1 (e.g. "1  2  3 ... 10").');
        console.error('        First 20 non-empty lines of extracted text:');
        lines.filter(l => l.trim().length > 0).slice(0, 20)
             .forEach((l, idx) => console.error(`  ${idx + 1}: ${l}`));
        process.exit(1);
    }

    // ── Row patterns ──────────────────────────────────────────────────────────
    //
    // Driver row:       "  1 Chaz Mostert                   58   254   254 ..."
    //   ^spaces, 1-3 digit car, 1-4 spaces, driver name (letters/spaces/.'-)
    //   2+ spaces, then space-separated integers
    //
    // Continuation row: "  10                               251   252   254 ..."
    //   ^spaces, multiple-of-10 offset (10/20/.../90), 2+ spaces, integers
    //   NOTE: no driver name on continuation rows
    //
    const driverRe = /^\s{0,4}(\d{1,3})\s{1,4}([A-Za-z][A-Za-z '.\\-]{2,}?)\s{2,}(\d[\d ]+)$/;
    const contRe   = /^\s{1,}(10|20|30|40|50|60|70|80|90)\s{2,}(\d[\d ]+)\s*$/;

    const rows = [];
    let currentCar    = null;
    let currentDriver = null;

    for (let i = headerIdx + 1; i < lines.length; i++) {
        const line = lines[i];
        if (!line.trim()) continue;

        const dm = driverRe.exec(line);
        const cm = !dm && contRe.exec(line);

        if (dm) {
            currentCar    = dm[1].trim();
            currentDriver = dm[2].trim();
            const vals    = dm[3].trim().split(/\s+/).filter(Boolean);
            pushRows(rows, event, session, currentCar, currentDriver, 0, vals);
        } else if (cm) {
            if (currentCar === null) continue;
            const offset = parseInt(cm[1], 10);
            const vals   = cm[2].trim().split(/\s+/).filter(Boolean);
            pushRows(rows, event, session, currentCar, currentDriver, offset, vals);
        }
        // Page headers, footers, blank lines silently skipped
    }

    if (rows.length === 0) {
        console.error('[ERROR] No data rows extracted.');
        console.error('        Header row was found but no car number rows followed.');
        console.error(`        Header line (${headerIdx}): ${lines[headerIdx]}`);
        process.exit(1);
    }

    // ── Write CSV ─────────────────────────────────────────────────────────────
    const cols = ['event', 'session', 'car', 'driver', 'lap', 'kph', 'parse_error'];
    const csvLines = [cols.join(',')];
    for (const row of rows) {
        const vals = cols.map(col => {
            const v = row[col];
            if (v === undefined || v === null) return '';
            const s = String(v);
            return (s.includes(',') || s.includes('"'))
                ? `"${s.replace(/"/g, '""')}"`
                : s;
        });
        csvLines.push(vals.join(','));
    }

    fs.writeFileSync(csvOut, csvLines.join('\r\n'), 'utf8');

    // ── Summary ───────────────────────────────────────────────────────────────
    const errRows = rows.filter(r => r.parse_error === 'true');
    const drivers = new Set(rows.map(r => r.car)).size;
    console.log(`[OK] Extracted ${rows.length} rows (${drivers} drivers) -> ${csvOut}`);
    if (errRows.length > 0) {
        console.log(`[WARN] ${errRows.length} row(s) flagged with parse_error=true`);
        errRows.forEach(r => console.log(`       Car ${r.car}, Lap ${r.lap}`));
    }

    // Sentinel: MATLAB reads PDF-detected session as fallback for session aliasing
    const pdfSession = detectPdfSession(lines);
    if (pdfSession) console.log(`__SESSION__${pdfSession}`);

    // Sentinel line: MATLAB reads this to find the CSV path
    console.log(`__CSV__${csvOut}`);
})();

// ── Detect session label from PDF header lines ────────────────────────────────
function detectPdfSession(lines) {
    // Matches lines like: "Practice P2   45 Mins" or "Race 9   X Mins" or "Qualifying Q6  24 Mins"
    const re = /^(Qualifying\s+Race|Practice|Qualifying|Race|Warm[\s-]?Up|Sprint)\s+([A-Z]?\d+)\s+\d+\s*Mins/i;
    for (const line of lines) {
        const m = re.exec(line.trim());
        if (m) return `${m[1].trim()} ${m[2].trim()}`;
    }
    return null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function pushRows(rows, event, session, car, driver, lapOffset, vals) {
    vals.forEach((v, idx) => {
        const kph = parseInt(v, 10);
        rows.push({
            event, session, car, driver,
            lap:         lapOffset + idx + 1,
            kph:         isNaN(kph) ? null : kph,
            parse_error: isNaN(kph) ? 'true' : 'false',
        });
    });
}
