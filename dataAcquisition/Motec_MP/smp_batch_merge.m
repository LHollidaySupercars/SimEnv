%% smp_batch_merge.m
% Batch merge all DASH_FILE / ECU_FILE pairs listed in session_metadata.xlsx.
%
% For each row in the spreadsheet that has both DASH_FILE and ECU_FILE filled:
%   1. Aligns ECU to Dash via full-signal RPM xcorr
%   2. Writes a combined .ld to <session_root>/COM/
%   3. Appends session metadata channels (weather, mass)
%
% Rows with a missing/empty DASH_FILE or ECU_FILE are silently skipped.
% Per-pair failures are caught, reported, and processing continues.

clear; clc; close all;

%% =========================================================
%  CONFIG
%% =========================================================

SESSION_METADATA_FILE = fullfile(fileparts(mfilename('fullpath')), ...
    'channels', 'session_metadata.xlsx');

cfg.dash_rpm_channel  = 'Engine_Speed';
cfg.ecu_rpm_channel   = 'Engine.Speed';
cfg.resample_hz       = 100;
cfg.max_offset_s      = 300;
cfg.rpm_min           = 500;
cfg.session_meta_file = SESSION_METADATA_FILE;
cfg.show_ui           = true;   % suppress msgbox / figures in batch mode

%% =========================================================
%  Read DASH_FILE / ECU_FILE pairs from xlsx
%% =========================================================

if ~exist(SESSION_METADATA_FILE, 'file')
    error('session_metadata.xlsx not found:\n  %s', SESSION_METADATA_FILE);
end

fprintf('=== Reading session pairs from ===\n  %s\n\n', SESSION_METADATA_FILE);

[~, ~, raw] = xlsread(SESSION_METADATA_FILE, 'Sheet1');

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

    results{p} = smp_merge_ecu_dash_pair(dash_file, ecu_file, cfg);

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
