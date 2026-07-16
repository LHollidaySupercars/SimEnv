function smp_batch_merge(cfg)
%% smp_batch_merge(cfg)
% Batch merge all DASH_FILE / ECU_FILE pairs listed in the pairs Excel
% produced by smp_pair_sessions.
%
% For each row that has both DASH_FILE and ECU_FILE filled:
%   1. Aligns ECU to Dash via full-signal RPM xcorr
%   2. Writes a combined .ld to <session_root>/COM/
%   3. Appends session metadata channels (weather, mass)
%
% Required cfg fields:
%   cfg.pairs_excel        — path to Excel from smp_pair_sessions (Pairs sheet)
%   cfg.dash_rpm_ch        — RPM channel name in Dash files
%   cfg.ecu_rpm_ch         — RPM channel name in ECU files
%   cfg.merge_resample_hz  — xcorr grid frequency (Hz)
%   cfg.merge_max_offset_s — max plausible ECU offset (s)
%   cfg.merge_rpm_min      — RPM mask threshold
%   cfg.session_meta_file  — path to session_metadata.xlsx for weather/mass channels

% =========================================================
%  RESOLVE CONFIG
% =========================================================
SESSION_METADATA_FILE = cfg.session_meta_file;

merge_cfg.dash_rpm_channel  = cfg.dash_rpm_ch;
merge_cfg.ecu_rpm_channel   = cfg.ecu_rpm_ch;
merge_cfg.resample_hz       = cfg.merge_resample_hz;
merge_cfg.max_offset_s      = cfg.merge_max_offset_s;
merge_cfg.rpm_min           = cfg.merge_rpm_min;
merge_cfg.session_meta_file = SESSION_METADATA_FILE;
merge_cfg.show_ui           = false;

%% =========================================================
%  Read DASH_FILE / ECU_FILE pairs from xlsx
%% =========================================================

PAIRS_FILE = cfg.pairs_excel;

if ~exist(PAIRS_FILE, 'file')
    error('Pairs Excel not found:\n  %s', PAIRS_FILE);
end

fprintf('=== Reading session pairs from ===\n  %s\n\n', PAIRS_FILE);

[~, ~, raw] = xlsread(PAIRS_FILE, 'Pairs');

if size(raw, 1) < 2
    error('No data rows found in session_metadata.xlsx');
end

headers  = raw(1, :);
dash_col = find(strcmpi(headers, 'DASH_FILE'));
ecu_col  = find(strcmpi(headers, 'ECU_FILE'));

if isempty(dash_col)
    error('DASH_FILE column not found in session_metadata.xlsx');
end
if isempty(ecu_col)
    error('ECU_FILE column not found in session_metadata.xlsx');
end

% Collect valid (non-empty) pairs
pairs = {};   % Nx2 cell: {dash_file, ecu_file}
for r = 2 : size(raw, 1)
    df = raw{r, dash_col};
    ef = raw{r, ecu_col};
    if ~ischar(df) || isempty(strtrim(df)), continue; end
    if ~ischar(ef) || isempty(strtrim(ef)), continue; end
    pairs(end+1, :) = {strtrim(df), strtrim(ef)}; %#ok<AGROW>
end

n_pairs = size(pairs, 1);
fprintf('Found %d pair(s) to process.\n\n', n_pairs);

if n_pairs == 0
    fprintf('No pairs found — check that DASH_FILE and ECU_FILE columns are filled.\n');
    return;
end

%% =========================================================
%  Process each pair
%% =========================================================

results = cell(n_pairs, 1);

for p = 1 : n_pairs
    dash_file = pairs{p, 1};
    ecu_file  = pairs{p, 2};

    fprintf('══════════════════════════════════════════════════════\n');
    fprintf('Pair %d / %d\n', p, n_pairs);
    fprintf('  Dash : %s\n', dash_file);
    fprintf('  ECU  : %s\n\n', ecu_file);

    results{p} = smp_merge_ecu_dash_pair(dash_file, ecu_file, merge_cfg);

    fprintf('\n');
end

%% =========================================================
%  Summary table
%% =========================================================

fprintf('\n══════════════════════════════════════════════════════\n');
fprintf('BATCH SUMMARY  (%d pair(s))\n', n_pairs);
fprintf('══════════════════════════════════════════════════════\n');
fprintf('%-4s  %-8s  %-9s  %-5s  %-5s  %s\n', ...
    '#', 'Status', 'Offset(s)', 'Qual', 'Chans', 'Dash basename');
fprintf('%s\n', repmat('-', 1, 72));

n_ok   = 0;
n_fail = 0;

for p = 1 : n_pairs
    r = results{p};
    [~, dash_base] = fileparts(pairs{p, 1});
    if r.success
        n_ok = n_ok + 1;
        fprintf('%-4d  %-8s  %+9.3f  %.3f  %3d    %s\n', ...
            p, 'OK', r.offset_s, r.quality_score, r.n_ecu_merged, dash_base);
    else
        n_fail = n_fail + 1;
        short_err = r.error_msg;
        if numel(short_err) > 55
            short_err = [short_err(1:52) '...'];
        end
        fprintf('%-4d  %-8s  %-9s  %-5s  %-5s  %s\n  >> %s\n', ...
            p, 'FAILED', '-', '-', '-', dash_base, short_err);
    end
end

fprintf('%s\n', repmat('-', 1, 72));
fprintf('  Completed: %d   Failed: %d\n\n', n_ok, n_fail);

end  % function smp_batch_merge
