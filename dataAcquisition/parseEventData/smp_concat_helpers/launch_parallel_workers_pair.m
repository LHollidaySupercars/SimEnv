function pairs_excel = launch_parallel_workers_pair(cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR)
% LAUNCH_PARALLEL_WORKERS_PAIR  Spawn N MATLAB workers for Phase 4 pairing.
%   Each worker loads assigned candidate pairs and calls smp_pair_sessions_worker.
%   Results are aggregated from audit_N.mat files. Done flags written to TMP_DIR on completion.

% ---- Resolve tmp dir ----
p4_tmp = TMP_DIR;
if isempty(p4_tmp)
    p4_tmp = fullfile(cfg.root_folder, '_tmp_pair_phase');
end
if ~exist(p4_tmp, 'dir'), mkdir(p4_tmp); end
delete(fullfile(p4_tmp, 'chunk_*.mat'));
delete(fullfile(p4_tmp, 'worker_cfg.mat'));
delete(fullfile(p4_tmp, 'audit_*.mat'));
delete(fullfile(p4_tmp, 'done_*.flag'));

% ---- Pre-scan to enumerate candidate pairs ----
SESSION         = cfg.session;
TD_HOL_DIR      = cfg.td_hol_output_dir;
ECU_HOL_DIR     = cfg.ecu_hol_dir;
L180_HOL_DIR    = cfg.l180_hol_dir;

dash_dir = fullfile(TD_HOL_DIR, SESSION);
ecu_dir  = fullfile(ECU_HOL_DIR, SESSION);
l180_dir = fullfile(L180_HOL_DIR, SESSION);

dash_map = build_stem_map(dash_dir);
ecu_map  = build_stem_map(ecu_dir);
l180_map = build_stem_map(l180_dir);

% ---- Generate candidates table (same logic as smp_pair_sessions Phase 1-2) ----
ecu_stems  = fieldnames(ecu_map);
dash_stems = fieldnames(dash_map);

candidates  = {};
review_rows = {};

for i = 1 : numel(ecu_stems)
    stem = ecu_stems{i};
    if isfield(dash_map, stem)
        candidates(end+1, :) = {dash_map.(stem), ecu_map.(stem), stem}; %#ok<AGROW>
    else
        review_rows(end+1, :) = {ecu_map.(stem), 'ECU', 'ECU_NO_DASH', ''}; %#ok<AGROW>
    end
end

matched_dash_stems = {};
if size(candidates, 1) > 0
    matched_dash_stems = candidates(:, 3);
end
for i = 1 : numel(dash_stems)
    stem = dash_stems{i};
    if ~any(strcmp(matched_dash_stems, stem))
        review_rows(end+1, :) = {dash_map.(stem), 'Dash', 'DASH_NO_ECU', ''}; %#ok<AGROW>
    end
end

% TLA filter
if isfield(cfg, 'ecu_tla_filter') && ~isempty(cfg.ecu_tla_filter)
    keep = false(size(candidates, 1), 1);
    for i = 1 : size(candidates, 1)
        [stem_tla, ~] = extract_tla_session(candidates{i, 3});
        keep(i) = any(strcmpi(stem_tla, cfg.ecu_tla_filter));
    end
    candidates = candidates(keep, :);
end

% ---- Overwrite filter — drop candidates whose COM file already exists ----
OVERWRITE_P4 = isfield(cfg, 'overwrite') && cfg.overwrite;
if ~OVERWRITE_P4 && ~isempty(candidates)
    COM_DIR_P4 = cfg.com_dir;
    keep_cand = true(size(candidates, 1), 1);
    for i = 1 : size(candidates, 1)
        [~, dash_base, dash_ext] = fileparts(candidates{i, 1});
        com_check = fullfile(COM_DIR_P4, [dash_base '_combined' dash_ext]);
        if exist(com_check, 'file')
            keep_cand(i) = false;
        end
    end
    n_skipped_p4 = sum(~keep_cand);
    candidates   = candidates(keep_cand, :);
    if n_skipped_p4 > 0
        fprintf('  Overwrite=false: skipping %d pair(s) with existing COM files\n', n_skipped_p4);
    end
end

n_candidates = size(candidates, 1);

% ---- Extract unique TLAs — split unit (one TLA goes to exactly one worker) ----
all_tlas_p4 = {};
for i = 1 : n_candidates
    [stem_tla, ~] = extract_tla_session(candidates{i, 3});
    all_tlas_p4{end+1} = stem_tla; %#ok<AGROW>
end
all_tlas_p4 = unique(all_tlas_p4);
n_tlas_p4   = numel(all_tlas_p4);

% ---- Resolve worker count (capped by unique TLA count) ----
if ischar(N_WORKERS) || N_WORKERS == 0
    n_workers_p4 = n_tlas_p4;
else
    n_workers_p4 = min(N_WORKERS, n_tlas_p4);
end

fprintf('============================================\n');
fprintf('  Parallel Phase 4: Dash/ECU Pairing\n');
fprintf('  Candidates : %d\n', n_candidates);
fprintf('  TLAs       : %d\n', n_tlas_p4);
fprintf('  Workers    : %d\n', n_workers_p4);
fprintf('  TMP        : %s\n', p4_tmp);
fprintf('  Time       : %s\n', datestr(now, 'HH:MM:SS'));
fprintf('============================================\n\n');

% ---- Split TLAs across workers (each TLA goes to exactly one worker) ----
chunk_size_p4 = ceil(n_tlas_p4 / n_workers_p4);
for w = 1 : n_workers_p4
    i_start = (w-1)*chunk_size_p4 + 1;
    i_end   = min(w*chunk_size_p4, n_tlas_p4);
    if i_start > n_tlas_p4
        worker_tlas = all_tlas_p4([]); %#ok<NASGU>
        fprintf('Worker %d: no TLAs assigned\n', w);
    else
        worker_tlas = all_tlas_p4(i_start:i_end); %#ok<NASGU>
        fprintf('Worker %d: TLAs %d-%d  (%s)\n', ...
            w, i_start, i_end, strjoin(all_tlas_p4(i_start:i_end), ', '));
    end
    save(fullfile(p4_tmp, sprintf('chunk_%d.mat', w)), 'worker_tlas');
end

% ---- Save shared worker cfg ----
worker_cfg = cfg; %#ok<NASGU>
save(fullfile(p4_tmp, 'worker_cfg.mat'), 'worker_cfg');
fprintf('\n');

% ---- Launch workers ----
motec_mp_dir = fileparts(mfilename('fullpath'));
matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
win_mode     = 'cmd /c';
if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
fprintf('Launching %d worker(s)...\n', n_workers_p4);
for w = 1 : n_workers_p4
    sys_cmd = sprintf( ...
        'start "SMP Pair Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_pair_sessions_worker(%d, ''%s'')"', ...
        w, win_mode, matlab_exe, ...
        strrep(motec_mp_dir, '\', '\\'), ...
        w, strrep(p4_tmp, '\', '\\'));
    system(sys_cmd);
    fprintf('  Worker %d launched\n', w);
    pause(1.5);
end
fprintf('\nWorkers running — COM files written to COM_DIR concurrently.\n');
fprintf('done_N.flag written to TMP after each worker completes.\n\n');
pairs_excel = '';

end

