function T = smp_extract_speed_trap(pdf_path, event, session)
% SMP_EXTRACT_SPEED_TRAP  Extract pit lane speed trap data from a PDF report.
%
% Calls the Node.js PDF engine internally, reads the output CSV back as a
% MATLAB table, and merges the result into the master speed trap CSV.
%
% Usage:
%   T = smp_extract_speed_trap('E:\2026\99_seasonTiming\03_TAU\report.pdf', 'TAU', 'Race')
%
% Inputs:
%   pdf_path  - full path to the PDF file
%   event     - event code e.g. 'TAU'
%   session   - session name e.g. 'Race'
%
% Output:
%   T  - MATLAB table with columns:
%          event, session, car, driver, vehicle, lap, time_of_day,
%          s1_kph [, s2_kph, ...], parse_error
%
%   A per-event CSV is written alongside the PDF.
%   The master CSV is updated automatically.

    % ── Input validation ──────────────────────────────────────────────────────
    if nargin < 3
        error('smp_extract_speed_trap: requires three inputs — (pdf_path, event, session)');
    end
    if ~isfile(pdf_path)
        error('smp_extract_speed_trap: PDF not found:\n  %s', pdf_path);
    end

    % ── Locate the Node.js engine (same directory as this .m file) ────────────
    timing_dir  = fileparts(mfilename('fullpath'));
    node_script = fullfile(timing_dir, 'extract_speed_trap.js');

    if ~isfile(node_script)
        error('smp_extract_speed_trap: extract_speed_trap.js not found in:\n  %s', timing_dir);
    end

    % ── Verify Node.js is on PATH ─────────────────────────────────────────────
    [node_check, ~] = system('node --version');
    if node_check ~= 0
        error(['smp_extract_speed_trap: Node.js not found on PATH.\n' ...
               'Install from https://nodejs.org and restart MATLAB.']);
    end

    % ── Install npm dependencies on first run ─────────────────────────────────
    pdf_parse_dir = fullfile(timing_dir, 'node_modules', 'pdf-parse');
    if ~isfolder(pdf_parse_dir)
        fprintf('Installing Node.js dependencies (first run only)...\n');
        [npm_s, npm_o] = system(sprintf('cd /d "%s" && npm install --silent 2>&1', timing_dir));
        if npm_s ~= 0
            error('smp_extract_speed_trap: npm install failed:\n%s', npm_o);
        end
        fprintf('Dependencies installed.\n');
    end

    % ── Run the Node.js extractor ─────────────────────────────────────────────
    cmd = sprintf('node "%s" "%s" --event "%s" --session "%s" 2>&1', ...
        node_script, pdf_path, event, session);

    [status, raw_output] = system(cmd);

    % Print output lines to MATLAB console, suppressing the sentinel line
    out_lines = splitlines(string(raw_output));
    visible   = out_lines(~startsWith(out_lines, '__CSV__'));
    if any(strlength(visible) > 0)
        fprintf('%s\n', strjoin(visible(strlength(visible) > 0), newline));
    end

    if status ~= 0
        error('smp_extract_speed_trap: extractor failed (exit %d). See output above.', status);
    end

    % ── Find CSV path from sentinel line ─────────────────────────────────────
    sentinel  = out_lines(startsWith(out_lines, '__CSV__'));
    if isempty(sentinel)
        error('smp_extract_speed_trap: extractor did not report output CSV path.');
    end
    csv_path = char(strtrim(extractAfter(sentinel(1), '__CSV__')));

    if ~isfile(csv_path)
        error('smp_extract_speed_trap: expected output CSV not found:\n  %s', csv_path);
    end

    % ── Read CSV into MATLAB table ────────────────────────────────────────────
    T = readtable(csv_path, 'Delimiter', ',', 'TextType', 'string');

    % ── Upgrade session alias if filename gave a raw fallback ─────────────────
    if is_raw_session(session)
        pdf_ses = extract_sentinel(out_lines, '__SESSION__');
        if ~isempty(pdf_ses)
            better = session_alias_from_text(pdf_ses);
            if ~is_raw_session(better)
                session = better;
                fprintf('[INFO] Session alias upgraded from PDF text: %s -> %s\n', pdf_ses, better);
            else
                session = pdf_ses;  % use PDF text as-is
                fprintf('[INFO] Session set from PDF text: %s\n', pdf_ses);
            end
            T.session(:) = string(session);
            writetable(T, csv_path);  % re-save with corrected session
        end
    end

    % ── Report any parse errors ───────────────────────────────────────────────
    if ismember('parse_error', T.Properties.VariableNames)
        bad = T(strcmpi(T.parse_error, 'true'), :);
        if height(bad) > 0
            fprintf('[WARN] %d row(s) have parse_error=true — open the CSV to correct them:\n', height(bad));
            fprintf('       %s\n', csv_path);
        end
    end

    % ── Tag report type then update master CSV ──────────────────────────────
    % Speed Trap Report CSVs use trap_N_kph columns; pit lane uses s1_kph etc.
    if any(startsWith(T.Properties.VariableNames, 'trap_'))
        rpt_type = "top_speed";
    else
        rpt_type = "pit_speed";
    end
    T.report_type = repmat(rpt_type, height(T), 1);
    smp_update_master_speed_trap(T, pdf_path);

end

% ═════════════════════════════════════════════════════════════════════════════
% Local helpers
% ═════════════════════════════════════════════════════════════════════════════

function result = extract_sentinel(lines, prefix)
% Return the value after a sentinel prefix, or '' if not found.
    match = lines(startsWith(lines, prefix));
    if isempty(match)
        result = '';
    else
        result = char(strtrim(extractAfter(match(1), prefix)));
    end
end

function tf = is_raw_session(s)
% True if session string looks like a raw fallback (contains _ or doesn't match ^[A-Z]{1,3}\d{2}$)
    tf = ~isempty(regexp(s, '_', 'once')) || isempty(regexp(s, '^[A-Z]{1,3}\d{2}$', 'once'));
end

function alias = session_alias_from_text(s)
% Convert a session label string to a short alias.
% Handles: "Practice P2", "Practice 2", "Race 9", "Qualifying Q6", "Qualifying Race 8"
    prefix_map = struct( ...
        'Race',            'R',  ...
        'QualifyingRace',  'QR', ...
        'Qualifying',      'Q',  ...
        'Practice',        'P',  ...
        'WarmUp',          'W',  ...
        'Sprint',          'S'   ...
    );
    tok = regexp(strtrim(s), ...
        '^(Qualifying\s+Race|Race|Qualifying|Practice|Warm[\s_\-]?Up|Sprint)\s+[A-Z]?(\d+)$', ...
        'tokens', 'ignorecase', 'once');
    if ~isempty(tok)
        word   = regexprep(tok{1}, '[\s_\-]', '');
        word(1) = upper(word(1));
        num    = str2double(tok{2});
        if isfield(prefix_map, word)
            letter = prefix_map.(word);
        else
            letter = upper(word(1));
        end
        alias = sprintf('%s%02d', letter, num);
    else
        alias = regexprep(upper(strtrim(s)), '[^A-Z0-9]', '_');
        alias = regexprep(alias, '_+', '_');
    end
end
