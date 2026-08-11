function launch_parallel_workers_ecu(cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR)
% LAUNCH_PARALLEL_WORKERS_ECU  Spawn N MATLAB workers for Phase 2 ECU concat.
%   Each worker loads its assigned driver group chunk and calls
%   smp_concat_ecu_per_driver. Done flags are written to TMP_DIR on completion.

% ---- Resolve tmp dir ----
p2_tmp = TMP_DIR;
if isempty(p2_tmp)
    p2_tmp = fullfile(cfg.root_folder, '_tmp_ecu_concat');
end
if ~exist(p2_tmp, 'dir')
    mkdir(p2_tmp)
end
delete(fullfile(p2_tmp, 'chunk_*.mat'));
delete(fullfile(p2_tmp, 'worker_cfg.mat'));
delete(fullfile(p2_tmp, 'done_*.flag'));

% ---- Pre-scan to enumerate ECU driver groups (no data loaded) ----
INPUT_DIR    = cfg.ecu_input_dir;
ECU_FORMAT   = cfg.ecu_format; %#ok<NASGU>
driver_map   = [];
if isfield(cfg, 'driver_alias_file') && isfile(cfg.driver_alias_file)
    try
        driver_map = smp_driver_alias_load(cfg.driver_alias_file);
    catch, end
end

% Inline recursive .ld scan (skips HOL subfolder — mirrors recursive_find_ld)
ld_files = {};
if isfolder(INPUT_DIR)
    stack = {INPUT_DIR};
    while ~isempty(stack)
        cur = stack{end}; stack(end) = [];
        d = dir(fullfile(cur, '*.ld'));
        for k = 1 : numel(d)
            if ~startsWith(d(k).name, '._')
                ld_files{end+1} = fullfile(cur, d(k).name); %#ok<AGROW>
            end
        end
        sub = dir(cur);
        for k = 1 : numel(sub)
            if sub(k).isdir && sub(k).name(1) ~= '.' && ~strcmpi(sub(k).name, 'HOL')
                stack{end+1} = fullfile(cur, sub(k).name); %#ok<AGROW>
            end
        end
    end
end

if isempty(ld_files)
    fprintf('[WARN] launch_parallel_workers_ecu: no .ld files in %s\n', INPUT_DIR);
    return;
end

group_keys = {};
for fi = 1 : numel(ld_files)
    fp = ld_files{fi};
    [~, fn, ~] = fileparts(fp);
    prefix = regexp(fn, '^([^_]+)', 'match', 'once');
    if strcmpi(prefix, 'S3'), continue; end

    group_key = fn;
    try
        hdr     = motec_ld_info(fp, false);
        raw_drv = strtrim(hdr.driver);
        % Inline resolve_driver_info: match raw_drv against alias entries
        drv_key  = raw_drv;
        if ~isempty(driver_map) && ~isempty(raw_drv)
            raw_lower = lower(raw_drv);
            keys_dm   = fieldnames(driver_map);
            for ki = 1 : numel(keys_dm)
                entry = driver_map.(keys_dm{ki});
                if any(strcmp(raw_lower, entry.aliases))
                    if ~isempty(entry.tla),       drv_key = entry.tla;
                    elseif ~isempty(entry.canonical), drv_key = entry.canonical;
                    end
                    break;
                end
            end
        end
        if ~isempty(prefix)
            group_key = [prefix '_' drv_key];
        else
            group_key = drv_key;
        end
    catch, end
    group_keys{end+1} = group_key; %#ok<AGROW>
end

all_drivers = unique(group_keys);

% Apply driver filter if set
if isfield(cfg, 'ecu_tla_filter') && ~isempty(cfg.ecu_tla_filter)
    keep_drv = false(size(all_drivers));
    for i = 1 : numel(all_drivers)
        tla_part = regexprep(all_drivers{i}, '^[^_]+_', '');
        keep_drv(i) = ismember(lower(tla_part), lower(cfg.ecu_tla_filter)) || ...
                      ismember(lower(all_drivers{i}), lower(cfg.ecu_tla_filter));
    end
    all_drivers = all_drivers(keep_drv);
end

n_drivers_p2 = numel(all_drivers);

% ---- Resolve worker count ----
if ischar(N_WORKERS) || N_WORKERS == 0
    n_workers_p2 = n_drivers_p2;
else
    n_workers_p2 = min(N_WORKERS, n_drivers_p2);
end

fprintf('============================================\n');
fprintf('  Parallel ECU Concat\n');
fprintf('  Drivers : %d\n', n_drivers_p2);
fprintf('  Workers : %d\n', n_workers_p2);
fprintf('  TMP     : %s\n', p2_tmp);
fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
fprintf('============================================\n\n');

% ---- Split drivers across workers ----
chunk_size_p2 = ceil(n_drivers_p2 / n_workers_p2);
for w = 1 : n_workers_p2
    i_start = (w-1)*chunk_size_p2 + 1;
    i_end   = min(w*chunk_size_p2, n_drivers_p2);
    if i_start > n_drivers_p2
        worker_drivers = all_drivers([]); %#ok<NASGU>
        fprintf('Worker %d: no drivers assigned\n', w);
    else
        worker_drivers = all_drivers(i_start:i_end); %#ok<NASGU>
        fprintf('Worker %d: drivers %d-%d  (%d driver(s))\n', ...
            w, i_start, i_end, i_end - i_start + 1);
    end
    save(fullfile(p2_tmp, sprintf('chunk_%d.mat', w)), 'worker_drivers');
end

% ---- Save shared worker cfg ----
worker_cfg = cfg; %#ok<NASGU>
save(fullfile(p2_tmp, 'worker_cfg.mat'), 'worker_cfg');
fprintf('\n');

% ---- Launch workers ----
motec_mp_dir = fileparts(mfilename('fullpath'));
matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
win_mode     = 'cmd /c';
if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
fprintf('Launching %d worker(s)...\n', n_workers_p2);
for w = 1 : n_workers_p2
    sys_cmd = sprintf( ...
        'start "SMP ECU Concat Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_concat_ecu_per_driver_worker(%d, ''%s'')"', ...
        w, win_mode, matlab_exe, ...
        strrep(motec_mp_dir, '\', '\\'), ...
        w, strrep(p2_tmp, '\', '\\'));
    system(sys_cmd);
    fprintf('  Worker %d launched\n', w);
    pause(1.5);
end
fprintf('\nWorkers running — ECU concat files written to ecu_concat_dir concurrently.\n');
fprintf('done_N.flag written to TMP after each worker completes.\n\n');
end

