function smp_concat_teamdata_worker(worker_id, tmp_dir)
%% smp_concat_teamdata_worker(worker_id, tmp_dir)
% Thin shim launched by smp_pipeline when PHASE1_MODE = 'parallel'.
%
% Loads the shared cfg and this worker's driver chunk from tmp_dir,
% restricts cfg.driver_filter to the assigned drivers, then delegates
% entirely to smp_concat_teamdata — no concat logic lives here.
%
% Called via:
%   matlab -batch "addpath(genpath('...')); smp_concat_teamdata_worker(N, 'path')"
%
% Writes done_N.flag to tmp_dir after smp_concat_teamdata returns
% (i.e. after the report popup is dismissed by the user).

fprintf('=== smp_concat_teamdata_worker  (worker %d) ===\n', worker_id);
fprintf('    TMP : %s\n\n', tmp_dir);

% ---- Load shared cfg ----
cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
if ~isfile(cfg_file)
    error('smp_concat_teamdata_worker: worker_cfg.mat not found:\n  %s', cfg_file);
end
loaded = load(cfg_file, 'worker_cfg');
cfg    = loaded.worker_cfg;

% ---- Load this worker's group chunk ----
chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
if ~isfile(chunk_file)
    error('smp_concat_teamdata_worker: chunk_%d.mat not found:\n  %s', worker_id, tmp_dir);
end
chunk         = load(chunk_file, 'worker_groups');
worker_groups = chunk.worker_groups;

if isempty(worker_groups)
    fprintf('Worker %d: no groups assigned — exiting.\n', worker_id);
    return;
end

% ---- Restrict cfg to this worker's drivers ----
cfg.driver_filter = unique({worker_groups.driver});
fprintf('Worker %d: %d driver(s): %s\n\n', ...
    worker_id, numel(cfg.driver_filter), strjoin(cfg.driver_filter, ', '));

% ---- Run concat — popup fires here if cfg.show_report = true ----
smp_concat_teamdata(cfg);

% ---- Signal done (written after popup is dismissed) ----
flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
fid = fopen(flag_file, 'w');
if fid ~= -1
    fprintf(fid, 'Worker %d completed: %s\n', worker_id, datestr(now));
    fclose(fid);
end

fprintf('\n=== Worker %d complete ===\n', worker_id);
end
