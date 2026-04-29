'use strict';

// ── extract_speed_trap.js ─────────────────────────────────────────────────────
// Extracts pit lane speed trap data from a PDF timing report.
// Called internally by smp_extract_speed_trap.m — not intended for direct use.
//
// Usage:
//   node extract_speed_trap.js <pdf_path> [--event TAU] [--session Race]
//
// Output:
//   Writes <pdf_name>_speed_trap.csv alongside the PDF.
//   Prints __CSV__<path> on the final line so MATLAB can locate it.
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
    console.error('Usage: node extract_speed_trap.js <pdf_path> [--event XXX] [--session YYY]');
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

// Output CSV: same folder, same base name + _speed_trap.csv
const pdfDir  = path.dirname(pdfPath);
const pdfBase = path.basename(pdfPath, path.extname(pdfPath));
const csvOut  = path.join(pdfDir, `${pdfBase}_speed_trap.csv`);

// ── Main ──────────────────────────────────────────────────────────────────────
(async () => {
    const buf  = fs.readFileSync(pdfPath);
    const data = await pdfParse(buf);

    const lines = data.text
        .split(/\r?\n/)
        .map(l => l.trimEnd());

    // ── Locate header row ─────────────────────────────────────────────────────
    // Looks for a line containing car/driver/no. AND a speed indicator (kph/s1/s2...)
    // Adjust the regex below if your PDF uses different column names.
    let headerIdx    = -1;
    let headerTokens = [];

    for (let i = 0; i < lines.length; i++) {
        const lo = lines[i].toLowerCase();
        const hasCarOrDriver = /\b(car|no\.?|driver)\b/.test(lo);
        const hasSpeed       = /\b(kph|km\/h|speed|s\d)\b/.test(lo);
        if (hasCarOrDriver && hasSpeed) {
            headerIdx    = i;
            headerTokens = tokenise(lines[i]);
            break;
        }
    }

    if (headerIdx === -1) {
        console.error('[ERROR] Cannot find header row in PDF.');
        console.error('        Expected a line containing car/driver AND kph/s1/s2 keywords.');
        console.error('        First 20 non-empty lines of extracted text:');
        lines.filter(l => l.trim().length > 0).slice(0, 20)
             .forEach((l, i) => console.error(`  ${i + 1}: ${l}`));
        process.exit(1);
    }

    // ── Detect speed trap column names from header ────────────────────────────
    const normHeaders = headerTokens.map(t => t.toLowerCase().trim());
    const trapCols    = [];

    normHeaders.forEach((h) => {
        const isSpeedCol = /^s\d/.test(h) || /kph|km\/h/.test(h);
        if (!isSpeedCol) return;

        // Normalise: "S1 kph" → "s1_kph", "S1" → "s1_kph", "kph" → "s1_kph"
        let name = h.replace(/\s*(kph|km\/h)/g, '').trim();
        name = /^s\d+$/.test(name) ? `${name}_kph` : `s${trapCols.length + 1}_kph`;
        trapCols.push(name);
    });

    // Fallback: assume one column after time_of_day
    if (trapCols.length === 0) {
        const todPos = normHeaders.findIndex(h => /when|time/.test(h));
        const start  = todPos >= 0 ? todPos + 1 : normHeaders.length - 1;
        for (let i = start; i < normHeaders.length; i++) {
            trapCols.push(`s${trapCols.length + 1}_kph`);
        }
    }

    // ── Parse data rows ───────────────────────────────────────────────────────
    // Data rows begin with a car number: 1–3 digits optionally followed by a letter.
    // Capped at 3 digits to exclude year numbers like 2026 being misread as car numbers.
    const rowRe = /^\s*\d{1,3}[A-Za-z]?\s/;
    const rows  = [];

    for (let i = headerIdx + 1; i < lines.length; i++) {
        const line = lines[i];
        if (!rowRe.test(line)) continue;

        const tokens = tokenise(line);

        // Expect: car, driver, vehicle, lap, time_of_day, [S# values...]
        if (tokens.length < 5) {
            rows.push(badRow(tokens, trapCols, event, session));
            continue;
        }

        const [car, driver, vehicle, lapRaw, time_of_day, ...rest] = tokens;
        const lap      = parseInt(lapRaw, 10);
        const trapVals = rest.slice(0, trapCols.length);
        const trapNums = trapVals.map(v => {
            const n = parseInt(v, 10);
            return isNaN(n) ? null : n;
        });

        const parseError = isNaN(lap) || trapNums.length === 0 || trapNums.some(v => v === null);

        const row = { event, session, car, driver, vehicle,
                      lap: isNaN(lap) ? lapRaw : lap,
                      time_of_day };
        trapCols.forEach((col, idx) => {
            row[col] = trapNums[idx] !== undefined ? trapNums[idx] : null;
        });
        row.parse_error = parseError ? 'true' : 'false';
        rows.push(row);
    }

    if (rows.length === 0) {
        console.warn('[WARN] No data rows found. The header was located but no car-number rows followed.');
        console.warn(`       Header line (${headerIdx}): ${lines[headerIdx]}`);
    }

    // ── Write CSV ─────────────────────────────────────────────────────────────
    const allCols = ['event', 'session', 'car', 'driver', 'vehicle', 'lap',
                     'time_of_day', ...trapCols, 'parse_error'];

    const csvLines = [allCols.join(',')];
    for (const row of rows) {
        const vals = allCols.map(col => {
            const v = row[col];
            if (v === undefined || v === null) return '';
            const s = String(v);
            // Quote values that contain commas or quotes
            return (s.includes(',') || s.includes('"'))
                ? `"${s.replace(/"/g, '""')}"`
                : s;
        });
        csvLines.push(vals.join(','));
    }

    fs.writeFileSync(csvOut, csvLines.join('\r\n'), 'utf8');

    // ── Summary ───────────────────────────────────────────────────────────────
    const errRows = rows.filter(r => r.parse_error === 'true');
    console.log(`[OK] Extracted ${rows.length} rows -> ${csvOut}`);
    console.log(`     Trap columns detected: ${trapCols.join(', ')}`);
    if (errRows.length > 0) {
        console.log(`[WARN] ${errRows.length} row(s) flagged with parse_error=true — review CSV before use:`);
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

function tokenise(line) {
    // Split on 2+ spaces or tabs (PDF column separator), trim each token
    return line.trim()
        .split(/\t|\s{2,}/)
        .map(t => t.trim())
        .filter(t => t.length > 0);
}

function badRow(tokens, trapCols, event, session) {
    const row = { event, session,
                  car:         tokens[0] || '',
                  driver:      '',
                  vehicle:     '',
                  lap:         '',
                  time_of_day: '' };
    trapCols.forEach(col => { row[col] = null; });
    row.parse_error = 'true';
    return row;
}
