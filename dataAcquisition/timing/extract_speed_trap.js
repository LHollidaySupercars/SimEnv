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

    // ── Detect format: "SPEED TRAP REPORT" (wide, per-car) vs pit lane (per-lap) ─
    const isSpeedTrapReport = lines.some(l => /SPEED\s+TRAP\s+REPORT/i.test(l));

    let trapCols = [];
    let rows     = [];

    if (isSpeedTrapReport) {
        // ── Speed Trap Report: columns are numbered trap passes (1 2 3 … 10) ──
        // Find the numeric-only column header row (all tokens are integers, starts with 1)
        let colHeaderIdx = -1;
        for (let i = 0; i < lines.length; i++) {
            const trimmed = lines[i].trim();
            if (!trimmed) continue;
            const toks = trimmed.split(/\s+/);
            if (toks.length >= 3 && toks.every(t => /^\d+$/.test(t)) && Number(toks[0]) === 1) {
                colHeaderIdx = i;
                break;
            }
        }

        if (colHeaderIdx === -1) {
            console.error('[ERROR] Speed Trap Report: cannot find numeric column header.');
            console.error('        Expected a row of integers starting with 1 (e.g. "1  2  3  ...  10").');
            console.error('        First 20 non-empty lines:');
            lines.filter(l => l.trim()).slice(0, 20)
                 .forEach((l, i) => console.error(`  ${i + 1}: ${l}`));
            process.exit(1);
        }

        // ── Parse car rows and continuation rows ──────────────────────────────
        // Car row:          "  1 Chaz Mostert                  105   92   170 ..."
        //   → first 2+-space token is "<carNum> <DriverName>"
        // Continuation row: "                         10       243  249  247 ..."
        //   → first 2+-space token is a pure integer offset; rest are more speeds
        const carOrder = [];
        const carData  = {};   // car → { driver, speeds[] }
        let currentCar = null;

        for (let i = colHeaderIdx + 1; i < lines.length; i++) {
            const line    = lines[i];
            const trimmed = line.trim();
            if (!trimmed) continue;

            // Split on 2+ spaces to separate car+driver block from individual speeds
            const parts = trimmed.split(/\s{2,}/).map(s => s.trim()).filter(s => s);
            if (!parts.length) continue;

            // Car row: first part starts with 1-3 digits then space then a letter
            if (/^\d{1,3}[A-Za-z]?\s+[A-Za-z]/.test(parts[0])) {
                const spaceIdx = parts[0].indexOf(' ');
                const car      = parts[0].substring(0, spaceIdx).trim();
                const driver   = parts[0].substring(spaceIdx + 1).trim();
                const speeds   = parts.slice(1)
                    .flatMap(p => p.split(/\s+/))
                    .map(Number)
                    .filter(n => !isNaN(n) && n > 0);

                if (!carData[car]) {
                    carOrder.push(car);
                    carData[car] = { driver, speeds: [] };
                }
                carData[car].speeds.push(...speeds);
                currentCar = car;
                continue;
            }

            // Continuation row: first part is a pure integer (offset), rest are speeds
            if (currentCar && /^\d+$/.test(parts[0]) && parts.length >= 2) {
                const speeds = parts.slice(1)
                    .flatMap(p => p.split(/\s+/))
                    .map(Number)
                    .filter(n => !isNaN(n) && n > 0);
                carData[currentCar].speeds.push(...speeds);
            }
        }

        // ── Build trap column list based on max readings across all cars ──────
        let maxTraps = 0;
        for (const car of carOrder) maxTraps = Math.max(maxTraps, carData[car].speeds.length);
        for (let i = 1; i <= maxTraps; i++) trapCols.push(`trap_${i}_kph`);

        // ── One row per car ───────────────────────────────────────────────────
        rows = carOrder.map(car => {
            const { driver, speeds } = carData[car];
            const row = { event, session, car, driver,
                          vehicle: '', lap: '', time_of_day: '' };
            trapCols.forEach((col, idx) => {
                row[col] = speeds[idx] !== undefined ? speeds[idx] : null;
            });
            row.parse_error = speeds.length === 0 ? 'true' : 'false';
            return row;
        });

        if (rows.length === 0) {
            console.warn('[WARN] Speed Trap Report: no car rows found after numeric header.');
        }

    } else {
        // ── Pit lane speed trap format: per-lap rows with header keywords ─────
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

        // ── Detect speed trap column names from header ────────────────────────
        const normHeaders = headerTokens.map(t => t.toLowerCase().trim());

        normHeaders.forEach((h) => {
            const isSpeedCol = /^s\d/.test(h) || /kph|km\/h/.test(h);
            if (!isSpeedCol) return;
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

        // ── Parse per-lap data rows ───────────────────────────────────────────
        const rowRe = /^\s*\d{1,3}[A-Za-z]?\s/;

        for (let i = headerIdx + 1; i < lines.length; i++) {
            const line = lines[i];
            if (!rowRe.test(line)) continue;

            const tokens = tokenise(line);

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
