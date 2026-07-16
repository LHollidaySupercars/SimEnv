function smp_concat_ecu_per_driver_worker(worker_id, tmp_dir)
%% smp_concat_ecu_per_driver_worker(worker_id, tmp_dir)
% Thin worker shim for Phase 2 ECU concat parallelization.
% Loads assigned driver group chunk, restricts cfg to those TLAs,
% then delegates entirely to smp_concat_ecu_per_driver — no concat logic here.
%
% Called via:
%   matlab -batch "addpath(genpath('...')); smp_concat_ecu_per_driver_worker(N, 'tmp_path')"
%
% Writes done_N.flag to tmp_dir after smp_concat_ecu_per_driver returns.

fprintf('=== smp_concat_ecu_per_driver_worker  (worker %d) ===\n', worker_id);
fprintf('    TMP : %s\n\n', tmp_dir);

% ---- Load shared cfg ----
cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
if ~isfile(cfg_file)
    error('smp_concat_ecu_per_driver_worker: worker_cfg.mat not found:\n  %s', cfg_file);
end
loaded = load(cfg_file, 'worker_cfg');
cfg = loaded.worker_cfg;

% ---- Load this worker's driver chunk ----
chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
if ~isfile(chunk_file)
    error('smp_concat_ecu_per_driver_worker: chunk_%d.mat not found:\n  %s', worker_id, chunk_file);
end
chunk = load(chunk_file, 'worker_drivers');
worker_drivers = chunk.worker_drivers;

if isempty(worker_drivers)
    fprintf('Worker %d: no drivers assigned — exiting.\n', worker_id);
    return;
end

% ---- Restrict cfg to this worker's TLAs ----
% group_key format is 'S1_TLA' — extract the TLA part after the prefix
tlas = {};
for i = 1 : numel(worker_drivers)
    tla_part = regexprep(worker_drivers{i}, '^[^_]+_', '');  % 'S1_MOS' -> 'MOS'
    tlas{end+1} = tla_part; %#ok<AGROW>
end
cfg.ecu_tla_filter = unique(tlas);

fprintf('Worker %d: %d driver(s), TLAs: %s\n\n', ...
    worker_id, numel(worker_drivers), strjoin(cfg.ecu_tla_filter, ', '));

% ---- Run ECU concat — all logic lives in smp_concat_ecu_per_driver ----
smp_concat_ecu_per_driver(cfg);

% ---- Signal done ----
flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
fid = fopen(flag_file, 'w');
if fid ~= -1
    fprintf(fid, 'Worker %d completed: %s\n', worker_id, datestr(now));
    fclose(fid);
end

fprintf('\n=== Worker %d complete ===\n', worker_id);
end
