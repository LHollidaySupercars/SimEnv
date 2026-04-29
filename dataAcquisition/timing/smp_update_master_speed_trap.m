function smp_update_master_speed_trap(T_new, pdf_path)
% SMP_UPDATE_MASTER_SPEED_TRAP  Merge new speed trap rows into the master CSV.
%
% Called automatically by smp_extract_speed_trap. Not intended for direct use.
%
% Behaviour:
%   - Drops all existing rows matching the same event + session
%   - Appends T_new (safe to re-run — no duplicates)
%   - Handles variable S# column counts across events (pads gaps with NaN/'')
%   - Infers 'round' from the PDF parent folder name (e.g. 03_TAU → 3)
%
% Master CSV locations:
%   <timing_dir>/master_pit_speed.csv   — pit lane speed trap data
%   <timing_dir>/master_topspeed.csv    — on-track top speed data
%   where <timing_dir> is the folder containing this .m file.

    timing_dir = fileparts(mfilename('fullpath'));

    % Route to the correct master file based on report_type
    rpt = '';
    if ismember('report_type', T_new.Properties.VariableNames)
        rpt = lower(char(T_new.report_type(1)));
    end
    if strcmp(rpt, 'top_speed')
        master_path = fullfile(timing_dir, 'master_topspeed.csv');
    else
        master_path = fullfile(timing_dir, 'master_pit_speed.csv');
    end
    n           = height(T_new);

    % ── Add metadata columns ──────────────────────────────────────────────────
    T_new.round        = repmat(infer_round(pdf_path), n, 1);
    T_new.source_file  = repmat(string(pdf_path), n, 1);
    T_new.extracted_at = repmat( ...
        string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), n, 1);

    % ── First run: create master from T_new ───────────────────────────────────
    if ~isfile(master_path)
        writetable(T_new, master_path);
        fprintf('[Master] Created → %s  (%d rows)\n', master_path, n);
        return;
    end

    % ── Load existing master ──────────────────────────────────────────────────
    T_master = readtable(master_path, 'Delimiter', ',', 'TextType', 'string');

    % MATLAB may auto-parse 'extracted_at' as datetime — force back to string
    if ismember('extracted_at', T_master.Properties.VariableNames) && isdatetime(T_master.extracted_at)
        T_master.extracted_at = string(T_master.extracted_at, 'yyyy-MM-dd HH:mm:ss');
    end

    % ── Align columns across variable S# layouts ──────────────────────────────
    [T_master, T_new] = align_columns(T_master, T_new);

    % ── Drop rows matching same event + session + report_type ───────────────
    ev  = lower(string(T_new.event(1)));
    ses = lower(string(T_new.session(1)));
    rpt = lower(string(T_new.report_type(1)));

    % Backward compat: old master rows without report_type default to pit_speed
    if ~ismember('report_type', T_master.Properties.VariableNames)
        T_master.report_type = repmat("pit_speed", height(T_master), 1);
    end

    same = strcmpi(string(T_master.event),      ev)  & ...
           strcmpi(string(T_master.session),     ses) & ...
           strcmpi(string(T_master.report_type), rpt);
    n_dropped = sum(same);
    T_master  = T_master(~same, :);

    % ── Merge and save ────────────────────────────────────────────────────────
    T_out = [T_master; T_new];
    writetable(T_out, master_path);

    fprintf('[Master] +%d rows  (replaced %d existing)  |  Total: %d rows  →  %s\n', ...
        n, n_dropped, height(T_out), master_path);

end

% ── Local helpers ─────────────────────────────────────────────────────────────

function r = infer_round(pdf_path)
    % Infer round number from parent folder name.
    % e.g. E:\2026\99_seasonTiming\03_TAU\report.pdf  →  3
    parent = fileparts(pdf_path);
    [~, folder] = fileparts(parent);
    tok = regexp(folder, '^(\d+)', 'tokens', 'once');
    if ~isempty(tok)
        r = str2double(tok{1});
    else
        r = NaN;
    end
end

function [T1, T2] = align_columns(T1, T2)
    % Ensure both tables share the same column set.
    % Missing numeric columns (kph/lap/round) filled with NaN.
    % Missing string columns filled with "".
    c1       = string(T1.Properties.VariableNames);
    c2       = string(T2.Properties.VariableNames);
    all_cols = union(c1, c2, 'stable');

    T1 = pad_missing(T1, setdiff(all_cols, c1));
    T2 = pad_missing(T2, setdiff(all_cols, c2));

    % Reorder both to the same column order
    T1 = T1(:, cellstr(all_cols));
    T2 = T2(:, cellstr(all_cols));
end

function T = pad_missing(T, missing_cols)
    n = height(T);
    for i = 1:numel(missing_cols)
        col = char(missing_cols(i));
        if contains(col, '_kph') || ismember(col, {'lap','round'})
            T.(col) = NaN(n, 1);
        else
            T.(col) = repmat("", n, 1);
        end
    end
end
