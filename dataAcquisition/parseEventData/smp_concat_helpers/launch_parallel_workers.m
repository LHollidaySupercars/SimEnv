function n_workers_p1 = launch_parallel_workers(concat_cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR)
% LAUNCH_PARALLEL_WORKERS  Spawn one MATLAB worker per driver group (or N_WORKERS).
%   Each worker loads its assigned chunk of driver groups and calls
%   smp_concat_teamdata_worker. Done flags are written to TMP_DIR on completion.

% ---- Resolve tmp dir ----
p1_tmp = TMP_DIR;
if isempty(p1_tmp)
    p1_tmp = fullfile(concat_cfg.root_folder, '_tmp_parallel');
end
if ~exist(p1_tmp, 'dir'), mkdir(p1_tmp); end
delete(fullfile(p1_tmp, 'chunk_*.mat'));
delete(fullfile(p1_tmp, 'worker_cfg.mat'));
delete(fullfile(p1_tmp, 'done_*.flag'));

% ---- Pre-scan to enumerate driver groups (no data loaded) ----
alias_p1      = smp_alias_load(concat_cfg.event_alias_file);
driver_map_p1 = smp_driver_alias_load(concat_cfg.driver_alias_file);
scan_p1       = smp_scan_folders(concat_cfg.td_input_dir);
if ~isempty(concat_cfg.team_filter)
    keep_p1 = ismember({scan_p1.acronym}, concat_cfg.team_filter);
    scan_p1 = scan_p1(keep_p1);
end
to_load_p1 = struct('path', {}, 'team_index', {}, 'team_acronym', {});
n_tl_p1 = 0;
for t_p1 = 1 : numel(scan_p1)
    for f_p1 = 1 : numel(scan_p1(t_p1).files)
        n_tl_p1 = n_tl_p1 + 1;
        to_load_p1(n_tl_p1).path         = scan_p1(t_p1).files{f_p1};
        to_load_p1(n_tl_p1).team_index   = scan_p1(t_p1).index;
        to_load_p1(n_tl_p1).team_acronym = scan_p1(t_p1).acronym;
    end
end
groups_p1 = smp_append_stints(to_load_p1, driver_map_p1, alias_p1, concat_cfg.session_filter);
if ~isempty(concat_cfg.driver_filter)
    keep_p1   = ismember(lower({groups_p1.driver}), lower(concat_cfg.driver_filter));
    groups_p1 = groups_p1(keep_p1);
end
n_groups_p1 = numel(groups_p1);

% ---- Resolve worker count ----
if ischar(N_WORKERS) || N_WORKERS == 0
    n_workers_p1 = n_groups_p1;
else
    n_workers_p1 = min(N_WORKERS, n_groups_p1);
end

fprintf('============================================\n');
fprintf('  Parallel TeamData Concat\n');
fprintf('  Groups  : %d\n', n_groups_p1);
fprintf('  Workers : %d\n', n_workers_p1);
fprintf('  TMP     : %s\n', p1_tmp);
fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
fprintf('============================================\n\n');

% ---- Split groups across workers ----
chunk_size_p1 = ceil(n_groups_p1 / n_workers_p1);
for w = 1 : n_workers_p1
    i_start = (w-1)*chunk_size_p1 + 1;
    i_end   = min(w*chunk_size_p1, n_groups_p1);
    if i_start > n_groups_p1
        worker_groups = groups_p1([]); %#ok<NASGU>
        fprintf('Worker %d: no groups assigned\n', w);
    else
        worker_groups = groups_p1(i_start:i_end); %#ok<NASGU>
        fprintf('Worker %d: groups %d-%d  (%d group(s))\n', ...
            w, i_start, i_end, i_end - i_start + 1);
    end
    save(fullfile(p1_tmp, sprintf('chunk_%d.mat', w)), 'worker_groups');
end

% ---- Save shared worker cfg (driver_filter cleared — worker sets it) ----
worker_cfg               = concat_cfg; %#ok<NASGU>
worker_cfg.driver_filter = {};
save(fullfile(p1_tmp, 'worker_cfg.mat'), 'worker_cfg');
fprintf('\n');

% ---- Launch workers ----
motec_mp_dir = fileparts(mfilename('fullpath'));
matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
win_mode     = 'cmd /c';
if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
fprintf('Launching %d worker(s)...\n', n_workers_p1);
for w = 1 : n_workers_p1
    sys_cmd = sprintf( ...
        'start "SMP Concat Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_concat_teamdata_worker(%d, ''%s'')"', ...
        w, win_mode, matlab_exe, ...
        strrep(motec_mp_dir, '\', '\\'), ...
        w, strrep(p1_tmp, '\', '\\'));
    system(sys_cmd);
    fprintf('  Worker %d launched\n', w);
    pause(1.5);
end
fprintf('\nWorkers running — report popups will appear per driver.\n');
fprintf('done_N.flag written to TMP after each popup is dismissed.\n\n');
end

