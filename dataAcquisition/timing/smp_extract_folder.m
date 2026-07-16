function T_all = smp_extract_folder(folder_path, force)
% SMP_EXTRACT_FOLDER  Extract speed trap data from all PDFs in an event folder.
%
% Processes every .pdf file in the given folder, infers the event code from
% the folder name (e.g. 03_TAU → TAU) and the session alias from the filename
% (e.g. "Race 1.pdf" → "R01").  Looks up the V8SC canonical name from
% eventAlias.xlsx and stores it in each row.
%
% Each PDF produces a per-event CSV alongside the file, and the master CSV
% at C:\SimEnv\dataAcquisition\timing\master_speed_trap.csv is updated once
% after all files are processed.
%
% Usage:
%   T_all = smp_extract_folder('E:\2026\99_seasonTiming\03_TAU')
%
% Output:
%   T_all  - combined MATLAB table of all rows extracted from the folder.
%             Includes columns: event, session, car, driver, vehicle, lap,
%             time_of_day, s1_kph [, s2_kph ...], parse_error,
%             round, v8sc_name, source_file, extracted_at

    % ── Input validation ──────────────────────────────────────────────────────
    if nargin < 1
        error('smp_extract_folder: requires one input — folder path');
    end
    if nargin < 2 || isempty(force)
        force = false;
    end
    if ~isfolder(folder_path)
        error('smp_extract_folder: folder not found:\n  %s', folder_path);
    end

    % ── Infer event code from folder name, or fall back to parent folder ──────
    [~, folder_name] = fileparts(folder_path);
    [round_num, event_code] = parse_folder_name(folder_name);

    if isempty(event_code)
        % e.g. passed 'E:\...\04_RUA\pit_speed' — try parent '04_RUA'
        parent_dir = fileparts(folder_path);
        [~, parent_name] = fileparts(parent_dir);
        [round_num, event_code] = parse_folder_name(parent_name);
        if isempty(event_code)
            error(['smp_extract_folder: cannot infer event code from folder "%s" or its parent "%s".\n' ...
                   'Expected format: 03_TAU or similar (round_EVENTCODE).'], folder_name, parent_name);
        end
    end
    fprintf('Folder  : %s\n', folder_name);
    fprintf('Event   : %s  (Round %s)\n', event_code, round_num);

    % ── Look up V8SC canonical name from eventAlias.xlsx ─────────────────────
    v8sc_name = lookup_v8sc_name(event_code, round_num);
    if isempty(v8sc_name)
        fprintf('V8SC name: (not found in eventAlias — using event code)\n');
        v8sc_name = event_code;
    else
        fprintf('V8SC name: %s\n', v8sc_name);
    end

    % ── Find all PDF files in the folder ──────────────────────────────────────
    pdf_files = dir(fullfile(folder_path, '*.pdf'));
    if isempty(pdf_files)
        fprintf('[WARN] No PDF files found in:\n  %s\n', folder_path);
        T_all = table();
        return;
    end

    fprintf('\nFound %d PDF file(s):\n', numel(pdf_files));
    for i = 1:numel(pdf_files)
        fprintf('  %d. %s\n', i, pdf_files(i).name);
    end
    fprintf('\n');

    % ── Process each PDF ──────────────────────────────────────────────────────
    T_parts = {};
    n_ok    = 0;
    n_skip  = 0;
    n_fail  = 0;

    for i = 1:numel(pdf_files)
        pdf_path     = fullfile(folder_path, pdf_files(i).name);
        [~, pdf_base] = fileparts(pdf_files(i).name);
        session_alias = filename_to_session_alias(pdf_base);
        csv_check     = fullfile(folder_path, [pdf_base '_speed_trap.csv']);

        fprintf('─── [%d/%d] %s  →  session: %s\n', i, numel(pdf_files), pdf_files(i).name, session_alias);

        % ── Skip PDF parsing if CSV already exists ────────────────────────────
        if ~force && isfile(csv_check)
            fprintf('[SKIP] CSV exists — loading: %s\n', csv_check);
            try
                T = readtable(csv_check, 'Delimiter', ',', 'TextType', 'string');
                T.identifier = repmat(string(sprintf('%s_%s', event_code, session_alias)), height(T), 1);
                T.v8sc_name  = repmat(string(v8sc_name), height(T), 1);
                smp_update_master_speed_trap(T, pdf_path);
                T_parts{end+1} = T; %#ok<AGROW>
                n_skip = n_skip + 1;
            catch ME
                fprintf('[ERROR] Failed to load existing CSV:\n  %s\n', ME.message);
                n_fail = n_fail + 1;
            end
            fprintf('\n');
            continue;
        end

        try
            T = smp_extract_speed_trap(pdf_path, event_code, session_alias);

            % Attach combined identifier e.g. "TAU_R09"
            T.identifier = repmat(string(sprintf('%s_%s', event_code, session_alias)), height(T), 1);

            % Attach V8SC name
            T.v8sc_name = repmat(string(v8sc_name), height(T), 1);
            T_parts{end+1} = T; %#ok<AGROW>
            n_ok = n_ok + 1;
        catch ME
            fprintf('[ERROR] Failed to process %s:\n  %s\n', pdf_files(i).name, ME.message);
            n_fail = n_fail + 1;
        end
        fprintf('\n');
    end

    % ── Combine all results ───────────────────────────────────────────────────
    if isempty(T_parts)
        fprintf('[WARN] No files were successfully extracted.\n');
        T_all = table();
        return;
    end

    T_all = vertcat_flexible(T_parts);

    % ── Summary ───────────────────────────────────────────────────────────────
    n_err = sum(strcmpi(string(T_all.parse_error), 'true'));
    fprintf('════════════════════════════════════════\n');
    fprintf('Done  │  %d extracted, %d skipped (CSV exists), %d failed  /  %d total\n', n_ok, n_skip, n_fail, numel(pdf_files));
    fprintf('      │  %d total rows\n', height(T_all));
    if n_err > 0
        fprintf('      │  %d parse_error rows — review CSV files in:\n', n_err);
        fprintf('      │    %s\n', folder_path);
    end
    if n_fail > 0
        fprintf('      │  %d PDF(s) failed (see errors above)\n', n_fail);
    end

end

% ═════════════════════════════════════════════════════════════════════════════
% Local helpers
% ═════════════════════════════════════════════════════════════════════════════

function [round_str, event_code] = parse_folder_name(folder_name)
% Parse "03_TAU" → round_str="3", event_code="TAU"
% Also handles "03_TAU_extra" → "TAU"
    tok = regexp(folder_name, '^(\d+)[_\-]([A-Za-z]+)', 'tokens', 'once');
    if isempty(tok)
        round_str  = '';
        event_code = '';
    else
        round_str  = num2str(str2double(tok{1}));  % strip leading zeros
        event_code = upper(tok{2});
    end
end

function alias = filename_to_session_alias(name)
% Convert a PDF filename (without extension) to a session alias.
%
%   "Race 1"        → "R01"
%   "Race 9"        → "R09"
%   "Race 10"       → "R10"
%   "Qualifying 1"  → "Q01"
%   "Practice 1"    → "P01"
%   "Warm Up 1"     → "W01"
%   "Sprint 1"      → "S01"
%   other           → sanitised filename (underscores, uppercase)
%
    prefix_map = struct( ...
        'Race',            'R',  ...
        'QualifyingRace',  'QR', ...
        'Qualifying',      'Q',  ...
        'Practice',        'P',  ...
        'WarmUp',          'W',  ...
        'Shootout',          'S'   ...
    );

    s   = strtrim(name);
    % Check for "Qualifying Race N" first (before plain "Qualifying")
    % Also handles optional letter prefix e.g. "Practice P2", "Qualifying Q6"
    tok = regexp(s, '^(Qualifying\s+Race|Race|Qualifying|Practice|Warm[\s_\-]?Up|Sprint|Shootout)\s+[A-Z]?(\d+)$', ...
                 'tokens', 'ignorecase', 'once');

    if ~isempty(tok)
        word = regexprep(tok{1}, '[\s_\-]', '');  % "Qualifying Race" → "QualifyingRace", "Warm Up" → "WarmUp"
        word(1) = upper(word(1));
        num  = str2double(tok{2});
        if isfield(prefix_map, word)
            letter = prefix_map.(word);
        else
            letter = upper(word(1));
        end
        alias = sprintf('%s%02d', letter, num);
    else
        % Fallback: capitalise, replace non-alphanumeric with underscore
        alias = regexprep(upper(s), '[^A-Z0-9]', '_');
        alias = regexprep(alias, '_+', '_');  % collapse multiple underscores
        alias = strtrim(alias);
    end
end

function v8sc_name = lookup_v8sc_name(event_code, round_str)
% Look up the V8SC canonical name from eventAlias.xlsx.
% Searches all columns for the event_code string.
% Returns '' if not found.

    alias_path = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
    v8sc_name  = '';

    if ~isfile(alias_path)
        return;
    end

    try
        % Read all columns as strings to allow searching across alias columns
        opts = detectImportOptions(alias_path, 'Sheet', 1);
        opts = setvartype(opts, opts.VariableNames, 'string');
        A = readtable(alias_path, opts, 'Sheet', 1);
    catch
        return;
    end

    if isempty(A) || width(A) < 1
        return;
    end

    % Build a search term: match by event code or by Exx round pattern
    round_num  = str2double(round_str);
    round_code = sprintf('E%02d', round_num);  % e.g. "E03"

    search_terms = upper({event_code, round_code});

    col_names = A.Properties.VariableNames;
    n_rows    = height(A);

    for r = 1:n_rows
        for c = 1:numel(col_names)
            cell_val = upper(strtrim(string(A.(col_names{c})(r))));
            for s = 1:numel(search_terms)
                if strcmp(cell_val, search_terms{s})
                    % Return the V8SC_Name column value for this row
                    v8sc_name = char(A.(col_names{1})(r));
                    return;
                end
            end
        end
    end
end

function T_out = vertcat_flexible(T_parts)
% Vertically concatenate tables that may have different column sets.
% Missing columns filled with NaN (numeric) or "" (string).

    % Collect all unique column names in order
    all_cols = {};
    for i = 1:numel(T_parts)
        cols = T_parts{i}.Properties.VariableNames;
        for c = 1:numel(cols)
            if ~ismember(cols{c}, all_cols)
                all_cols{end+1} = cols{c}; %#ok<AGROW>
            end
        end
    end

    % Pad each table to full column set
    T_padded = cell(size(T_parts));
    for i = 1:numel(T_parts)
        Ti      = T_parts{i};
        missing = setdiff(all_cols, Ti.Properties.VariableNames);
        n       = height(Ti);
        for m = 1:numel(missing)
            col = missing{m};
            if contains(col, '_kph') || ismember(col, {'lap','round'})
                Ti.(col) = NaN(n, 1);
            else
                Ti.(col) = repmat("", n, 1);
            end
        end
        T_padded{i} = Ti(:, all_cols);
    end

    T_out = vertcat(T_padded{:});
end
