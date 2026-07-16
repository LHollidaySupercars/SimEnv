function T_all = smp_extract_topspeed_folder(folder_path, force)
% SMP_EXTRACT_TOPSPEED_FOLDER  Extract top speed data from all PDFs in a folder.
%
% Processes every .pdf in the given folder (expected to be a 'top_speed\'
% subfolder e.g. E:\2026\99_seasonTiming\04_RAU\top_speed\).
%
% Infers event code from the PARENT folder name (e.g. 04_RAU → RAU, round 4)
% and the session alias from each PDF filename (e.g. "Race 9.pdf" → R09).
%
% Each PDF produces a per-session _topspeed.csv alongside the file.
% The master CSV at C:\SimEnv\dataAcquisition\timing\master_speed_trap.csv
% is updated with report_type = 'top_speed'.
%
% Usage:
%   T_all = smp_extract_topspeed_folder('E:\2026\99_seasonTiming\04_RAU\top_speed')
%
% Output:
%   T_all  - combined MATLAB table with columns:
%              event, session, car, driver, lap, kph, parse_error,
%              report_type, identifier, v8sc_name, round, source_file, extracted_at

    % ── Input validation ──────────────────────────────────────────────────────
    if nargin < 1
        error('smp_extract_topspeed_folder: requires one input — folder path');
    end
    if nargin < 2 || isempty(force)
        force = false;
    end
    if ~isfolder(folder_path)
        error('smp_extract_topspeed_folder: folder not found:\n  %s', folder_path);
    end

    % ── Infer event code from PARENT folder (e.g. 04_RAU) ────────────────────
    parent_dir  = fileparts(folder_path);
    [~, parent_name] = fileparts(parent_dir);
    [round_num, event_code] = parse_folder_name(parent_name);

    % Fallback: try the folder itself if parent doesn't match pattern
    if isempty(event_code)
        [~, folder_name] = fileparts(folder_path);
        [round_num, event_code] = parse_folder_name(folder_name);
    end

    if isempty(event_code)
        error(['smp_extract_topspeed_folder: cannot infer event code.\n' ...
               'Expected parent folder like "04_RAU". Got: %s'], parent_name);
    end

    fprintf('Folder  : %s\n', folder_path);
    fprintf('Event   : %s  (Round %s)\n', event_code, round_num);

    % ── Look up V8SC canonical name ───────────────────────────────────────────
    v8sc_name = lookup_v8sc_name(event_code, round_num);
    if isempty(v8sc_name)
        fprintf('V8SC name: (not found in eventAlias — using event code)\n');
        v8sc_name = event_code;
    else
        fprintf('V8SC name: %s\n', v8sc_name);
    end

    % ── Find all PDF files ────────────────────────────────────────────────────
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
        pdf_path      = fullfile(folder_path, pdf_files(i).name);
        [~, pdf_base] = fileparts(pdf_files(i).name);
        session_alias = filename_to_session_alias(pdf_base);
        csv_check     = fullfile(folder_path, [pdf_base '_topspeed.csv']);

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
            T = smp_extract_topspeed(pdf_path, event_code, session_alias);

            % Attach combined identifier e.g. "RAU_QR12"
            T.identifier = repmat(string(sprintf('%s_%s', event_code, session_alias)), height(T), 1);
            T.v8sc_name  = repmat(string(v8sc_name), height(T), 1);
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
% Local helpers  (shared logic with smp_extract_folder)
% ═════════════════════════════════════════════════════════════════════════════

function [round_str, event_code] = parse_folder_name(folder_name)
    tok = regexp(folder_name, '^(\d+)[_\-]([A-Za-z]+)', 'tokens', 'once');
    if isempty(tok)
        round_str  = '';
        event_code = '';
    else
        round_str  = num2str(str2double(tok{1}));
        event_code = upper(tok{2});
    end
end

function alias = filename_to_session_alias(name)
    prefix_map = struct( ...
        'Race',            'R',  ...
        'QualifyingRace',  'Q', ...
        'Qualifying',      'Q',  ...
        'Practice',        'P',  ...
        'WarmUp',          'W',  ...
        'Sprint',          'M',   ...
        'Shootout',        'S'   ...
    );

    s   = strtrim(name);
    % Also handles optional letter prefix e.g. "Practice P2", "Qualifying Q6"
    tok = regexp(s, '^(Qualifying\s+Race|Race|Qualifying|Practice|Warm[\s_\-]?Up|Sprint|Shootout)\s+[A-Z]?(\d+)$', ...
                 'tokens', 'ignorecase', 'once');

    if ~isempty(tok)
        word = regexprep(tok{1}, '[\s_\-]', '');
        word(1) = upper(word(1));
        num  = str2double(tok{2});
        if isfield(prefix_map, word)
            letter = prefix_map.(word);
        else
            letter = upper(word(1));
        end
        alias = sprintf('%s%02d', letter, num);
    else
        alias = regexprep(upper(s), '[^A-Z0-9]', '_');
        alias = regexprep(alias, '_+', '_');
        alias = strtrim(alias);
    end
end

function v8sc_name = lookup_v8sc_name(event_code, round_str)
    alias_path = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
    v8sc_name  = '';
    if ~isfile(alias_path), return; end

    try
        opts = detectImportOptions(alias_path, 'Sheet', 1);
        opts = setvartype(opts, opts.VariableNames, 'string');
        A = readtable(alias_path, opts, 'Sheet', 1);
    catch
        return;
    end

    if isempty(A) || width(A) < 1, return; end

    round_num  = str2double(round_str);
    round_code = sprintf('E%02d', round_num);
    search_terms = upper({event_code, round_code});

    col_names = A.Properties.VariableNames;
    for r = 1:height(A)
        for c = 1:numel(col_names)
            cell_val = upper(strtrim(string(A.(col_names{c})(r))));
            for s = 1:numel(search_terms)
                if strcmp(cell_val, search_terms{s})
                    v8sc_name = char(A.(col_names{1})(r));
                    return;
                end
            end
        end
    end
end

function T_out = vertcat_flexible(T_parts)
    all_cols = {};
    for i = 1:numel(T_parts)
        cols = T_parts{i}.Properties.VariableNames;
        for c = 1:numel(cols)
            if ~ismember(cols{c}, all_cols)
                all_cols{end+1} = cols{c}; %#ok<AGROW>
            end
        end
    end

    T_padded = cell(size(T_parts));
    for i = 1:numel(T_parts)
        Ti      = T_parts{i};
        missing = setdiff(all_cols, Ti.Properties.VariableNames);
        n       = height(Ti);
        for m = 1:numel(missing)
            col = missing{m};
            if any(strcmp(col, {'lap','kph','round'}))
                Ti.(col) = NaN(n, 1);
            else
                Ti.(col) = repmat("", n, 1);
            end
        end
        T_padded{i} = Ti(:, all_cols);
    end

    T_out = vertcat(T_padded{:});
end
