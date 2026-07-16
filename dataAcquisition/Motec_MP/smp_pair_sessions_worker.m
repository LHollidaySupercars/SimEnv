function smp_pair_sessions_worker(worker_id, tmp_dir)
%% smp_pair_sessions_worker(worker_id, tmp_dir)
% Thin worker shim for Phase 4 parallelization.
% Loads assigned candidates chunk, restricts cfg to those TLAs,
% then delegates entirely to smp_pair_sessions — no pairing logic here.
%
% Called via:
%   matlab -batch "addpath(genpath('...')); smp_pair_sessions_worker(N, 'tmp_path')"
%
% Writes done_N.flag to tmp_dir after smp_pair_sessions returns.

fprintf('=== smp_pair_sessions_worker  (worker %d) ===\n', worker_id);
fprintf('    TMP : %s\n\n', tmp_dir);

% ---- Load shared cfg ----
cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
if ~isfile(cfg_file)
    error('smp_pair_sessions_worker: worker_cfg.mat not found:\n  %s', cfg_file);
end
loaded = load(cfg_file, 'worker_cfg');
cfg = loaded.worker_cfg;

% ---- Load this worker's TLA chunk ----
chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
if ~isfile(chunk_file)
    error('smp_pair_sessions_worker: chunk_%d.mat not found:\n  %s', worker_id, chunk_file);
end
chunk = load(chunk_file, 'worker_tlas');
worker_tlas = chunk.worker_tlas;

if isempty(worker_tlas)
    fprintf('Worker %d: no TLAs assigned — exiting.\n', worker_id);
    return;
end

% ---- Restrict cfg to this worker's TLAs ----
cfg.ecu_tla_filter = worker_tlas;

fprintf('Worker %d: %d TLA(s): %s\n\n', ...
    worker_id, numel(cfg.ecu_tla_filter), strjoin(cfg.ecu_tla_filter, ', '));

% ---- Run pairing — all logic lives in smp_pair_sessions ----
smp_pair_sessions(cfg);

% ---- Signal done ----
flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
fid = fopen(flag_file, 'w');
if fid ~= -1
    fprintf(fid, 'Worker %d completed: %s\n', worker_id, datestr(now));
    fclose(fid);
end

fprintf('\n=== Worker %d complete ===\n', worker_id);
end


function [pair_rows, review_rows] = run_phase3_xcorr_merge(cfg, candidates)
% Phase 3 logic extracted: xcorr + merge for assigned candidates only.

ECU_FORMAT      = isfield(cfg, 'ecu_format') && cfg.ecu_format;
COM_DIR         = cfg.com_dir;
SESSION         = cfg.session;
QUALITY_MIN     = cfg.quality_min;
DASH_RPM        = cfg.dash_rpm_ch;
ECU_RPM         = cfg.ecu_rpm_ch;
RESAMPLE_HZ     = cfg.resample_hz;
MAX_OFFSET_S    = cfg.max_offset_s;
RPM_MIN         = cfg.rpm_min;
OVERWRITE       = isfield(cfg, 'overwrite') && cfg.overwrite;

pair_rows       = {};
review_rows     = {};

n_confirmed  = 0;
n_skipped    = 0;
n_xcorr_fail = 0;

xcorr_cfg.resample_hz  = RESAMPLE_HZ;
xcorr_cfg.max_offset_s = MAX_OFFSET_S;
xcorr_cfg.rpm_min      = RPM_MIN;
xcorr_cfg.b_ecu_format = false;

fprintf('--- Phase 3: xcorr alignment + merge ---\n');

for i = 1 : size(candidates, 1)
    dash_file = candidates{i, 1};
    ecu_file  = candidates{i, 2};
    stem      = candidates{i, 3};

    [~, tla] = extract_tla_session(stem);

    fprintf('  [%d/%d] %s\n', i, size(candidates, 1), stem);
    fprintf('    Dash : %s\n', dash_file);
    fprintf('    ECU  : %s\n', ecu_file);

    % --- Overwrite check ---
    [~, dash_base, dash_ext] = fileparts(dash_file);
    com_file_expected = fullfile(COM_DIR, [dash_base '_combined' dash_ext]);

    if ~OVERWRITE && exist(com_file_expected, 'file')
        fprintf('    [SKIP] COM file exists, overwrite=false\n');
        pair_rows(end+1, :) = {dash_file, ecu_file, '', tla, SESSION, ...
            NaN, NaN, NaN, NaN, com_file_expected, 'EXISTS'}; %#ok<AGROW>
        n_confirmed = n_confirmed + 1;
        continue;
    end

    % --- xcorr ---
    xcorr_cfg.b_ecu_format = ECU_FORMAT;
    [q, off, err_msg, seg_offsets] = xcorr_quality(dash_file, ecu_file, ...
        DASH_RPM, ECU_RPM, xcorr_cfg);

    % --- User skipped in segment UI ---
    if ischar(seg_offsets) && strcmp(seg_offsets, 'SKIP')
        fprintf('    [SKIP] User skipped in segment alignment UI\n');
        review_rows(end+1, :) = {ecu_file, 'ECU', 'SKIP_USER', ''}; %#ok<AGROW>
        n_skipped = n_skipped + 1;
        continue;
    end

    % --- xcorr error ---
    if ~isempty(err_msg)
        fprintf('    [WARN] xcorr: %s\n', err_msg);
        review_rows(end+1, :) = {ecu_file, 'ECU', ['XCORR_ERROR: ' err_msg], ...
            sprintf('%.4f', q)}; %#ok<AGROW>
        n_xcorr_fail = n_xcorr_fail + 1;
        continue;
    end

    fprintf('    ECU  quality=%.4f  offset=%+.3fs\n', q, off);

    if q < QUALITY_MIN
        review_rows(end+1, :) = {ecu_file, 'ECU', ...
            sprintf('XCORR_FAIL q=%.4f (min=%.4f)', q, QUALITY_MIN), ...
            sprintf('%.4f', q)}; %#ok<AGROW>
        fprintf('    [FAIL] quality %.4f below threshold %.4f\n', q, QUALITY_MIN);
        n_xcorr_fail = n_xcorr_fail + 1;
        continue;
    end

    % --- Merge ---
    merge_cfg                  = cfg;
    merge_cfg.offset_s         = off;
    merge_cfg.quality_score    = q;
    merge_cfg.seg_offsets      = seg_offsets;
    merge_cfg.show_ui          = false;
    merge_cfg.dash_rpm_channel = DASH_RPM;
    merge_cfg.ecu_rpm_channel  = ECU_RPM;
    merge_cfg.ecu_format       = ECU_FORMAT;
    merge_cfg.com_dir          = COM_DIR;

    fprintf('    -> Merging...\n');
    res = smp_merge_ecu_dash_pair(dash_file, ecu_file, merge_cfg);

    if res.success
        pair_rows(end+1, :) = {dash_file, ecu_file, '', tla, SESSION, ...
            off, q, NaN, NaN, res.com_file, 'MERGED'}; %#ok<AGROW>
        n_confirmed = n_confirmed + 1;
        fprintf('    -> OK: %s\n', res.com_file);
    else
        review_rows(end+1, :) = {ecu_file, 'ECU', ...
            ['MERGE_ERROR: ' res.error_msg], sprintf('%.4f', q)}; %#ok<AGROW>
        fprintf('    [MERGE ERROR] %s\n', res.error_msg);
        n_xcorr_fail = n_xcorr_fail + 1;
    end
end

fprintf('\n  Confirmed: %d  |  Skipped: %d  |  Failed: %d\n\n', ...
    n_confirmed, n_skipped, n_xcorr_fail);

end


% =========================================================================
%  HELPER FUNCTIONS
% =========================================================================

function [tla, session] = extract_tla_session(stem)
% EXTRACT_TLA_SESSION  Parse stem as TLA_YEAR_SESSION pattern.
% Returns: TLA = three-letter acronym, SESSION = remainder after TLA_YEAR
    parts = strsplit(stem, '_');
    if numel(parts) >= 1, tla = parts{1}; else, tla = stem; end
    if numel(parts) >= 3, session = strjoin(parts(3:end), '_'); else, session = ''; end
end


function stem = extract_stem(filepath)
% EXTRACT_STEM  Get MATLAB-safe filename stem (without .ld extension).
    [~, name] = fileparts(filepath);
    stem = matlab.lang.makeValidName(name);
end
