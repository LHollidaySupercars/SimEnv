function cache = smp_compile_parallel(cfg, compile_opts, channels, channel_rules, season, driver_map, alias)
% SMP_COMPILE_PARALLEL  Scan/diff, build one job per group, launch jobs
%   throttled to cfg.n_workers concurrent processes (spawn-and-exit per
%   group — mirrors smp_save_parallel's pattern), poll, and merge.
%
%   Each group gets its own fresh MATLAB process. This trades a small
%   per-job startup cost for a clean heap per group, which avoids the
%   memory creep seen when one long-lived worker processes many groups
%   in sequence (MATLAB/Windows don't reliably return freed memory to
%   the OS mid-process, even with disciplined clear()).

    % ---- Prep tmp dir ----
    if ~exist(cfg.tmp_dir, 'dir'), mkdir(cfg.tmp_dir); end
    delete(fullfile(cfg.tmp_dir, 'partial_job*.mat'));
    delete(fullfile(cfg.tmp_dir, 'done_job*.flag'));
    delete(fullfile(cfg.tmp_dir, 'job_*.mat'));
    delete(fullfile(cfg.tmp_dir, 'worker_cfg.mat'));
    delete(fullfile(cfg.tmp_dir, 'worker_job*_log.txt'));

    fprintf('============================================\n');
    fprintf('  Parallel Compile (per-group spawn-and-exit)\n');
    fprintf('  Max concurrent : %d\n', cfg.n_workers);
    fprintf('  TMP            : %s\n', cfg.tmp_dir);
    fprintf('  Time           : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('============================================\n\n');

    % ---- Scan and diff ----
    scan_all = smp_scan_folders(cfg.compile_dir_sesh);
    if ~isempty(cfg.team_filter)
        keep     = ismember({scan_all.acronym}, cfg.team_filter);
        scan_all = scan_all(keep);
    end

    cache = smp_cache_load(cfg.compile_dir_sesh, cfg.session_filter);

    if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
    if ~isfield(cache, 'traces'), cache.traces = struct(); end
    if ~isfield(cache, 'mode'),   cache.mode   = 'stream'; end
    if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
        cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
    end

    if ~isempty(cfg.date_from)
        date_from_dn = datenum(cfg.date_from);
        for i = 1:numel(scan_all)
            files = scan_all(i).files;
            keep  = false(1, numel(files));
            for j = 1:numel(files)
                d       = dir(files{j});
                keep(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
            end
            scan_all(i).files = files(keep);
        end
        scan_all = scan_all(arrayfun(@(t) ~isempty(t.files), scan_all));
    end

    [to_load, cache] = smp_cache_diff(cache, scan_all);

    if isempty(to_load)
        fprintf('All files up to date — nothing to compile.\n\n');
        return;
    end

    fprintf('%d file(s) to process.\n', numel(to_load));

    if cfg.workshop
        groups = smp_append_stints(to_load, driver_map, alias);
    else
        groups = smp_append_stints(to_load, driver_map, alias, cfg.session_filter);
    end
 % ---- Interleave heavy (multi-file/L180) groups with light ones ----
    is_heavy = arrayfun(@(g) g.n_files > 1, groups);
    heavy_idx = find(is_heavy);
    light_idx = find(~is_heavy);
    order = [];
    hi = 1; li = 1;
    while hi <= numel(heavy_idx) || li <= numel(light_idx)
        if hi <= numel(heavy_idx)
            order(end+1) = heavy_idx(hi); hi = hi + 1; %#ok<AGROW>
        end
        for k = 1:2
            if li <= numel(light_idx)
                order(end+1) = light_idx(li); li = li + 1; %#ok<AGROW>
            end
        end
    end
    groups = groups(order);
    n_jobs = numel(groups);
    fprintf('%d group(s) -> %d job(s), %d max concurrent.\n\n', n_jobs, n_jobs, cfg.n_workers);
    % ---- Release heavy fields before the job wait ----
    cache.stats  = struct();
    cache.traces = struct();
    if isfield(cache, 'laps'), cache.laps = struct(); end
    fprintf('[MEM] Historical stats/traces released for job wait (manifest retained).\n\n');

    % ---- Write one job file per group + shared worker_cfg ----
    worker_cfg = build_worker_cfg(cfg, compile_opts, channels, channel_rules, season, driver_map, alias);
    worker_cfg.l180_mode = compile_opts.l180_mode;
    save(fullfile(cfg.tmp_dir, 'worker_cfg.mat'), 'worker_cfg');

    for j = 1:n_jobs
        job_group = groups(j); %#ok<NASGU>
        save(fullfile(cfg.tmp_dir, sprintf('job_%d.mat', j)), 'job_group');
    end

    % ---- Launch, throttled to cfg.n_workers concurrent ----
    launch_and_poll_jobs(cfg, n_jobs);

    % ---- Reload full historical cache, then merge ----
    fprintf('[MEM] Reloading full historical cache for merge...\n');
    cache = smp_cache_load(cfg.compile_dir_sesh, cfg.session_filter);
    if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
    if ~isfield(cache, 'traces'), cache.traces = struct(); end
    if ~isfield(cache, 'mode'),   cache.mode   = 'stream'; end
    if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
        cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
    end

    cache = merge_partial_caches(cfg, cache, n_jobs);
end


function worker_cfg = build_worker_cfg(cfg, compile_opts, channels, channel_rules, season, driver_map, alias)
% BUILD_WORKER_CFG  Assemble the struct saved for smp_compile_worker to load.
% (unchanged from before — no diarrhea_mode/flush_every_n needed anymore,
%  since each job IS one group now.)
    [min_lt, max_lt] = smp_season_get(season, cfg.track);

    worker_cfg.channels_to_extract = channels;
    worker_cfg.channel_rules       = channel_rules;
    worker_cfg.driver_map          = driver_map;
    worker_cfg.alias               = alias;
    worker_cfg.season              = season;
    worker_cfg.track               = cfg.track;
    worker_cfg.top_level_dir       = cfg.root_folder;
    worker_cfg.min_lt              = min_lt;
    worker_cfg.max_lt              = max_lt;
    worker_cfg.T_gated             = compile_opts.T_gated;
    worker_cfg.channel_ops_map     = cfg.channel_ops_map;   % <-- NEW
    worker_cfg.max_traces     = compile_opts.max_traces;
    worker_cfg.detect_pitlane = compile_opts.detect_pitlane;
    worker_cfg.fcy_channel    = compile_opts.fcy_channel;
    worker_cfg.br2_channel    = compile_opts.br2_channel;
    worker_cfg.br2_protocol   = compile_opts.br2_protocol;
    worker_cfg.beacon_check   = compile_opts.beacon_check;
    if isfield(compile_opts, 'all_laps'),          worker_cfg.all_laps       = compile_opts.all_laps;         end
    if isfield(compile_opts, 'load_all_channels'), worker_cfg.load_all_ch    = compile_opts.load_all_channels; end
    if isfield(compile_opts, 'concat_csv_dir'),    worker_cfg.concat_csv_dir = compile_opts.concat_csv_dir;   end
    if isfield(compile_opts, 'showConcatReport'),  worker_cfg.show_report    = compile_opts.showConcatReport; end
    if isfield(compile_opts, 'uniqueFingerprint'), worker_cfg.unique_fp      = compile_opts.uniqueFingerprint; end
end



function launch_and_poll_jobs(cfg, n_jobs)
% LAUNCH_AND_POLL_JOBS  Spawn one MATLAB process per job, throttled to
%   cfg.n_workers concurrent. Actively kills each job's window the moment
%   its done flag appears (workaround for -batch processes that finish
%   their script but don't fully exit — e.g. lingering license/background
%   threads keep the OS process alive and holding memory even though the
%   work itself is done). Also watches for jobs stuck well past a normal
%   per-group duration and warns loudly instead of silently waiting.

win_mode = 'cmd /c'; if cfg.keep_workers_open, win_mode = 'cmd /k'; end
matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');

% Watchdog threshold: how long a single group should reasonably take.
% Default 15 min; override via cfg.job_max_duration_s if you have a
% better estimate from your own logs.
max_job_duration_s = 1800;
if isfield(cfg, 'job_max_duration_s'), max_job_duration_s = cfg.job_max_duration_s; end

launched     = false(n_jobs, 1);
launch_time  = NaN(n_jobs, 1);
reaped       = false(n_jobs, 1);   % window already taskkill'd for this job
warned_stuck = false(n_jobs, 1);   % already printed a watchdog warning
active       = 0;
idx          = 1;

fprintf('Launching jobs (max %d concurrent)...\n', cfg.n_workers);

while idx <= n_jobs || active > 0
    % ---- Launch new jobs into free slots ----
    while idx <= n_jobs && active < cfg.n_workers
        sys_cmd = sprintf('start "SMP Job %d" %s ""%s" -batch "smp_compile_worker(%d, ''%s'')"', ...
            idx, win_mode, matlab_exe, idx, strrep(cfg.tmp_dir, '\', '\\'));
        system(sys_cmd);
        fprintf('  Job %d launched  (%d/%d active)\n', idx, active+1, cfg.n_workers);
        launched(idx)    = true;
        launch_time(idx) = now;
        active = active + 1;
        idx    = idx + 1;
        pause(1.5);
    end

    % ---- Reap: kill the window for any job whose done flag just appeared ----
    for j = 1:n_jobs
        if ~launched(j) || reaped(j), continue; end
        flag_file = fullfile(cfg.tmp_dir, sprintf('done_job%d.flag', j));
        if exist(flag_file, 'file')
            kill_cmd = sprintf('taskkill /FI "WINDOWTITLE eq SMP Job %d" /T /F >nul 2>&1', j);
            system(kill_cmd);
            reaped(j) = true;
            fprintf('  [REAP] Job %d done — window closed, memory reclaimed.\n', j);
        end
    end

    % ---- Watchdog: flag jobs running far longer than expected ----
    for j = 1:n_jobs
        if ~launched(j) || reaped(j) || warned_stuck(j), continue; end
        elapsed_s = (now - launch_time(j)) * 86400;
        if elapsed_s > max_job_duration_s
            fprintf('  [WATCHDOG] Job %d has been running %.0f min with no done flag — check its window/log for a hang.\n', ...
                j, elapsed_s/60);
            warned_stuck(j) = true;   % warn once, don't spam every poll cycle
        end
    end

    done_flags = dir(fullfile(cfg.tmp_dir, 'done_job*.flag'));
    n_done     = numel(done_flags);
    active     = sum(launched) - n_done;

    if idx > n_jobs && n_done >= n_jobs
        break;
    end
    pause(2);
end

fprintf('\nAll jobs finished (%d/%d).\n\n', ...
    numel(dir(fullfile(cfg.tmp_dir, 'done_job*.flag'))), n_jobs);
end

function cache = merge_partial_caches(cfg, cache, n_jobs)
% MERGE_PARTIAL_CACHES  Merge each job's partial_job<J>.mat into cache.
    fprintf('Merging results...\n');
    for j = 1:n_jobs
        partial_file = fullfile(cfg.tmp_dir, sprintf('partial_job%d.mat', j));
        if ~exist(partial_file, 'file')
            fprintf('  [WARN] Job %d produced no output — skipping.\n', j);
            continue;
        end
        loaded = load(partial_file, 'partial_cache');
        pc     = loaded.partial_cache;

        if isempty(cache.manifest)
            cache.manifest = pc.manifest;
        else
            cache.manifest = [cache.manifest; pc.manifest];
        end
        keys_st = fieldnames(pc.stats);
        for k = 1:numel(keys_st)
            cache.stats.(keys_st{k}) = pc.stats.(keys_st{k});
        end
        keys_tr = fieldnames(pc.traces);
        for k = 1:numel(keys_tr)
            cache.traces.(keys_tr{k}) = pc.traces.(keys_tr{k});
        end
        if isfield(pc, 'laps')
            if ~isfield(cache, 'laps'), cache.laps = struct(); end
            keys_lp = fieldnames(pc.laps);
            for k = 1:numel(keys_lp)
                cache.laps.(keys_lp{k}) = pc.laps.(keys_lp{k});
            end
        end
        fprintf('  Job %d — %d manifest rows, %d stats, %d traces merged\n', ...
            j, height(pc.manifest), numel(keys_st), numel(keys_tr));
        clear loaded pc;
    end

    [~, unique_idx] = unique(cache.manifest.Path, 'stable');
    cache.manifest  = cache.manifest(unique_idx, :);
    fprintf('Manifest deduplicated: %d unique rows.\n', numel(unique_idx));
end
function chunk_groups(cfg, groups)
% CHUNK_GROUPS  Greedily bin-pack groups across cfg.n_workers by weight
%   (grp.n_files, as a proxy for stint count / compute cost) instead of
%   raw group count, so race groups (multi-stint) don't pile up on one
%   worker while others get light quali-style single-stint groups.

    n_groups = numel(groups);
    n_workers = cfg.n_workers;

    if n_groups == 0
        fprintf('No groups to chunk.\n\n');
        for w = 1:n_workers
            worker_groups = groups([]); %#ok<NASGU>
            save(fullfile(cfg.tmp_dir, sprintf('chunk_%d.mat', w)), 'worker_groups');
        end
        return;
    end

    % ---- Compute weight per group ----
    weights = zeros(n_groups, 1);
    for g = 1:n_groups
        if isfield(groups(g), 'n_files') && ~isempty(groups(g).n_files)
            weights(g) = max(groups(g).n_files, 1);
        else
            weights(g) = 1;
        end
    end

    % ---- Sort groups largest-first (classic greedy bin-packing) ----
    [~, sort_idx] = sort(weights, 'descend');

    % ---- Track running load per worker bin ----
    bin_load  = zeros(n_workers, 1);
    bin_items = cell(n_workers, 1);
    for w = 1:n_workers
        bin_items{w} = [];
    end

    for i = 1:n_groups
        g_idx = sort_idx(i);
        [~, target_w] = min(bin_load);          % always fill the lightest worker
        bin_items{target_w}(end+1) = g_idx;      %#ok<AGROW>
        bin_load(target_w) = bin_load(target_w) + weights(g_idx);
    end

    fprintf('%d group(s) bin-packed across %d worker(s) by weight (n_files proxy):\n\n', ...
        n_groups, n_workers);

    for w = 1:n_workers
        idxs = bin_items{w};
        if isempty(idxs)
            worker_groups = groups([]); %#ok<NASGU>
            fprintf('Worker %d: no groups assigned  (load 0)\n', w);
        else
            worker_groups = groups(idxs); %#ok<NASGU>
            fprintf('Worker %d: %d group(s)  (load %d)  -> %s\n', ...
                w, numel(idxs), bin_load(w), ...
                strjoin(arrayfun(@(g) sprintf('%s/%s(%d)', groups(g).team_acronym, ...
                    groups(g).session, groups(g).n_files), idxs, 'UniformOutput', false), ', '));
        end
        save(fullfile(cfg.tmp_dir, sprintf('chunk_%d.mat', w)), 'worker_groups');
    end
    fprintf('\n');
end

