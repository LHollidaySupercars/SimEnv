function launch_parallel_workers_augment(com_dir, channels_file, cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR, driver_map)
% LAUNCH_PARALLEL_WORKERS_AUGMENT  Spawn N MATLAB workers for Phase 6 COM augmentation.
%   Recursively scans com_dir, applies driver/session filter, then splits
%   files across workers. Each worker calls smp_augment_com_worker.
    if nargin < 3, cfg = struct(); end

    % ---- Resolve tmp dir ----
    p6_tmp = TMP_DIR;
    if isempty(p6_tmp)
        p6_tmp = fullfile(cfg.root_folder, '_tmp_augment');
    end
    if ~exist(p6_tmp, 'dir'), mkdir(p6_tmp); end
    delete(fullfile(p6_tmp, 'chunk_*.mat'));
    delete(fullfile(p6_tmp, 'worker_cfg.mat'));
    delete(fullfile(p6_tmp, 'done_*.flag'));

    % ---- Recursive .ld scan + filter ----
    all_files = recursive_find_ld(com_dir);
    if isempty(all_files)
        fprintf('[WARN] launch_parallel_workers_augment: no .ld files found (recursive) in %s\n', com_dir);
        return;
    end
    all_files = filter_aug_files(all_files, cfg);
    if isempty(all_files)
        fprintf('[WARN] launch_parallel_workers_augment: no files remain after driver/session filter.\n');
        return;
    end
    n_files = numel(all_files);

    % ---- Resolve worker count ----
    if ischar(N_WORKERS) || N_WORKERS == 0
        n_workers_p6 = n_files;
    else
        n_workers_p6 = min(N_WORKERS, n_files);
    end

    fprintf('============================================\n');
    fprintf('  Parallel COM Augment\n');
    fprintf('  Files   : %d\n', n_files);
    fprintf('  Workers : %d\n', n_workers_p6);
    fprintf('  TMP     : %s\n', p6_tmp);
    fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('============================================\n\n');

    % ---- Split files across workers ----
    chunk_size_p6 = ceil(n_files / n_workers_p6);
    for w = 1:n_workers_p6
        i_start = (w-1)*chunk_size_p6 + 1;
        i_end   = min(w*chunk_size_p6, n_files);
        if i_start > n_files
            worker_files = {}; %#ok<NASGU>
        else
            worker_files = all_files(i_start:i_end); %#ok<NASGU>
            fprintf('Worker %d: files %d-%d (%d file(s))\n', w, i_start, i_end, i_end-i_start+1);
        end
        save(fullfile(p6_tmp, sprintf('chunk_%d.mat', w)), 'worker_files');
    end

    % ---- Save shared worker cfg ----
    aug_worker_cfg = cfg; %#ok<NASGU>
    aug_worker_cfg.channels_file = channels_file;
    aug_worker_cfg.driver_map    = driver_map;   % <-- add this
    save(fullfile(p6_tmp, 'worker_cfg.mat'), 'aug_worker_cfg');
    fprintf('\n');

    % ---- Launch workers ----
    motec_mp_dir = fileparts(mfilename('fullpath'));
    matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
    win_mode     = 'cmd /c';
    if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end

    fprintf('Launching %d worker(s)...\n', n_workers_p6);
    for w = 1:n_workers_p6
        sys_cmd = sprintf( ...
            'start "SMP Augment Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_augment_com_worker(%d, ''%s'')""', ...
            w, win_mode, matlab_exe, ...
            strrep(motec_mp_dir, '\', '\\'), ...
            w, strrep(p6_tmp, '\', '\\'));
        system(sys_cmd);
        fprintf('  Worker %d launched\n', w);
        pause(1.5);
    end
    fprintf('\nWorkers running — augmenting COM files concurrently.\n');
    fprintf('done_N.flag written to TMP after each worker completes.\n\n');
end

