function smp_compile_event_upload(top_level_dir, channels_to_extract, ...
                                   season, driver_map, alias, opts)
% SMP_COMPILE_EVENT_UPLOAD  Whole-event compile, streamed straight to SQL.
%
% Standalone from smp_compile_event — does NOT touch the plotting cache,
% does NOT retain full-event stats in RAM, does NOT get called by or
% call into the plotting pipeline. Deliberately duplicates compute.
%
% Behaviour:
%   - Scans every team folder under top_level_dir, every session (no
%     session_filter — event-wide).
%   - For each file-group: load -> lap_slicer(all_laps=true) -> lap_stats
%     (full stat_ops, no channel_ops_map curation) -> flatten -> append
%     to a row buffer.
%   - Buffer is checked after every group; once it reaches
%     opts.flush_rows, that slice is handed off to a DETACHED, 
%     non-blocking MATLAB worker process for the actual SQL push, and
%     the buffer is cleared. This function never blocks on a DB call.
%   - Maintains its own lightweight manifest-only cache
%     (smp_cache_upload_manifest.mat) purely so repeat runs skip
%     unchanged files. No stats/traces are persisted in this cache.
%
% Inputs:
%   top_level_dir        - event COM folder, e.g. 'E:\2026\E06_DAR\COM'
%   channels_to_extract  - from smp_channel_config_load()
%   season                - from smp_season_load()
%   driver_map            - from smp_driver_alias_load()
%   alias                  - from smp_alias_load()
%   opts                   - struct:
%     .track            track acronym for lap time limits
%     .math_version     REQUIRED — manual code-version stamp, e.g. 'v1.0'
%     .target           'pocketbase' | 'azure_local' | 'azure_online'
%     .flush_rows        row-count buffer threshold (default 400)
%     .batch             SQL push batch size (default 200)
%     .overwrite         passed through to push opts (default false —
%                         math_version comparison decides overwrite,
%                         this is a blunt fallback only)
%     .worker_dir         handoff/queue dir (default <top_level_dir>\_upload_queue)
%     .keep_worker_open   true = cmd /k, leave window open (default false)
%     .dist_channel       (default 'Odometer')
%     .verbose            (default true)

    if nargin < 6 || isempty(opts), opts = struct(); end

    track            = get_opt(opts, 'track',            '');
    math_version     = get_opt(opts, 'math_version',      '');
    target           = get_opt(opts, 'target',            'azure_online');
    flush_rows       = get_opt(opts, 'flush_rows',         400);
    batch_size       = get_opt(opts, 'batch',              200);
    overwrite        = get_opt(opts, 'overwrite',          false);
    worker_dir       = get_opt(opts, 'worker_dir',         fullfile(top_level_dir, '_upload_queue'));
    keep_worker_open = get_opt(opts, 'keep_worker_open',   false);
    dist_ch          = get_opt(opts, 'dist_channel',       'Odometer');
    verbose          = get_opt(opts, 'verbose',            true);

    if isempty(math_version)
        error('smp_compile_event_upload: opts.math_version is required.');
    end

    if ~exist(worker_dir, 'dir'), mkdir(worker_dir); end

    % ------------------------------------------------------------------
    %  Lap time limits
    % ------------------------------------------------------------------
    if ~isempty(track) && ~isempty(season)
        [min_lt, max_lt] = smp_season_get(season, track);
    else
        min_lt = 10; max_lt = 600;
    end

    lap_opts.min_lap_time = min_lt;
    lap_opts.max_lap_time = max_lt;
    lap_opts.detect_pitlane = false;
    lap_opts.fcy_channel    = '';
    lap_opts.br2_channel    = '';
    lap_opts.br2_protocol   = 'standard';
    lap_opts.mylaps_channel = 'MyLaps X2TRA DeviceShortId';
    lap_opts.verbose        = false;

    stat_ops = {'max','min','mean','median','std','var','range', ...
                'max non zero','min non zero','mean non zero', ...
                'median non zero','std non zero','sample_rate','change'};

    % ------------------------------------------------------------------
    %  1. Scan whole event — every team, every session
    % ------------------------------------------------------------------
    fprintf('\n=== SMP Compile Event UPLOAD (event-wide, math_version=%s) ===\n', math_version);
    fprintf('Scanning: %s\n\n', top_level_dir);

    scan_all = smp_scan_folders(top_level_dir);
    if isempty(scan_all)
        error('smp_compile_event_upload: No valid team folders found.');
    end

    % ------------------------------------------------------------------
    %  2. Load/init lightweight manifest-only cache (own file, own diff)
    % ------------------------------------------------------------------
    manifest_cache_path = fullfile(top_level_dir, 'smp_cache_upload_manifest.mat');
    if exist(manifest_cache_path, 'file')
        s = load(manifest_cache_path, 'cache');
        up_cache = s.cache;
    else
        up_cache = smp_cache_empty();
    end
    if ~ismember('GroupKey', up_cache.manifest.Properties.VariableNames)
        up_cache.manifest.GroupKey = repmat({''}, height(up_cache.manifest), 1);
    end

    [to_load, up_cache] = smp_cache_diff(up_cache, scan_all);
    if isempty(to_load)
        fprintf('All files up to date — nothing new to upload.\n\n');
        return;
    end
    fprintf('%d new/changed file(s) to process for upload...\n\n', numel(to_load));

    % ------------------------------------------------------------------
    %  3. Group — no session_filter, whole event
    % ------------------------------------------------------------------
    groups = smp_append_stints(to_load, driver_map, alias, {});
    n_groups = numel(groups);

    % ------------------------------------------------------------------
    %  4. Stream compile + buffer + flush
    % ------------------------------------------------------------------
    buffer      = table();
    flush_count = 0;

    for g = 1:n_groups
        grp = groups(g);
        fprintf('[%d/%d] %s | %s | %s | %d file(s)\n', ...
            g, n_groups, grp.team_acronym, grp.driver, grp.session, grp.n_files);

        try
            session = load_and_concat_upload(grp.files, channels_to_extract, verbose, driver_map);
        catch ME
            fprintf('  [ERROR] Load failed: %s\n', ME.message);
            up_cache = add_failed_entries_upload(up_cache, grp, ME.message);
            continue;
        end

        if isempty(session)
            fprintf('  [WARN] No channel data — skipping.\n');
            continue;
        end

        try
            laps = lap_slicer(session, lap_opts);
        catch ME
            fprintf('  [ERROR] lap_slicer: %s\n', ME.message);
            up_cache = add_failed_entries_upload(up_cache, grp, ME.message);
            clear session;
            continue;
        end

        if isempty(laps)
            fprintf('  [WARN] No valid laps — skipping.\n');
            clear session;
            continue;
        end

        % ---- ALL laps, ALL channels, ALL stats — no curation ----
        try
            all_fields    = fieldnames(session);
            stat_channels = unique(all_fields);
            t0 = tic;
            stats = lap_stats(laps, stat_channels, struct('operations', {stat_ops}));
            fprintf('  lap_stats: %.2fs (%d laps x %d channels)\n', ...
                toc(t0), numel(laps), numel(stat_channels));
        catch ME
            fprintf('  [ERROR] lap_stats: %s\n', ME.message);
            clear session laps;
            continue;
        end

        group_key = matlab.lang.makeValidName(grp.key);
        info_s    = build_info_from_group_upload(grp, driver_map);

        % ---- Manifest entry (diff cache only — no stats retained) ----
        for f = 1:numel(grp.files)
            up_cache = smp_cache_add(up_cache, grp.files{f}, 0, grp.team_acronym, ...
                                      info_s, true, '', group_key);
        end

        % ---- Flatten this group only, stamp math_version, append ----
        mini_cache.stats            = struct();
        mini_cache.stats.(group_key) = stats;
        mini_cache.manifest          = up_cache.manifest(strcmp(up_cache.manifest.GroupKey, group_key), :);

        T_group = smp_flatten_stats(mini_cache, info_s.venue);
        if ismember('id', T_group.Properties.VariableNames)
            T_group = removevars(T_group, 'id');
        end
        T_group.math_version = repmat(string(math_version), height(T_group), 1);

        buffer = [buffer; T_group]; %#ok<AGROW>

        clear session laps stats mini_cache T_group;
        fprintf('  Done. RAM cleared. Buffer: %d row(s).\n', height(buffer));

        % ---- Flush check — row-count triggered, independent of group boundary ----
        if height(buffer) >= flush_rows
            flush_count = flush_count + 1;
            flush_buffer(buffer, worker_dir, target, batch_size, overwrite, ...
                          keep_worker_open, flush_count, top_level_dir);
            buffer = table();
        end
    end

    % ---- Final partial flush ----
    if height(buffer) > 0
        flush_count = flush_count + 1;
        flush_buffer(buffer, worker_dir, target, batch_size, overwrite, ...
                      keep_worker_open, flush_count, top_level_dir);
    end

    % ---- Save manifest-only cache for next run's diff ----
    save(manifest_cache_path, 'cache');
    fprintf('\nUpload manifest cache saved: %s\n', manifest_cache_path);
    fprintf('=== smp_compile_event_upload complete: %d flush(es) queued ===\n\n', flush_count);
end


% ======================================================================= %
%  FLUSH — write buffer to disk, launch DETACHED non-blocking worker
% ======================================================================= %
function flush_buffer(T, worker_dir, target, batch_size, overwrite, keep_open, flush_id, top_level_dir)
    ts        = datestr(now, 'yyyymmdd_HHMMSS');
    data_file = fullfile(worker_dir, sprintf('upload_%s_%03d.mat', ts, flush_id));
    flag_file = fullfile(worker_dir, sprintf('upload_%s_%03d.done', ts, flush_id));
    log_file  = fullfile(worker_dir, sprintf('upload_%s_%03d.log',  ts, flush_id));

    upload_opts.target    = target;
    upload_opts.batch     = batch_size;
    upload_opts.overwrite = overwrite;
    upload_opts.flag_file = flag_file;
    upload_opts.log_file  = log_file;

    save(data_file, 'T', 'upload_opts');

    worker_script = which('smp_upload_worker.m');
    if isempty(worker_script)
        warning('smp_upload_worker.m not found on path — flush %d NOT launched (data saved to %s).', ...
            flush_id, data_file);
        return;
    end

    matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    cmd_flag   = 'ifelse';
    if keep_open
        launch_mode = 'cmd /k';
    else
        launch_mode = 'cmd /c';
    end

    cmd = sprintf('%s start "" %s "%s" -nosplash -batch "smp_upload_worker(''%s'')"', ...
        launch_mode, matlab_exe, data_file, strrep(data_file, '\', '\\'));

    fprintf('  [FLUSH %d] %d row(s) -> detached worker (%s)\n', flush_id, height(T), target);
    system([cmd ' &']);   % '&' keeps this MATLAB session non-blocking on Windows shell
end


% ======================================================================= %
%  Trimmed local helpers (session load + info build only — no traces,
%  no channel_rules curation, no filter_channels — deliberately "all")
% ======================================================================= %
function session = load_and_concat_upload(files, channels_to_extract, verbose, driver_map)
    session = [];
    for f = 1:numel(files)
        d = motec_ld_reader(files{f}, {});   % {} = load ALL channels
        if isempty(d), continue; end
        if isempty(session)
            session = d;
        else
            session = smp_concat_sessions(session, d);   % existing helper, assumed on path
        end
    end
end

function info_s = build_info_from_group_upload(grp, driver_map)
    info_s.driver     = grp.driver;
    info_s.car_number = grp.car;
    info_s.session     = grp.session;
    info_s.venue        = '';
    info_s.log_date     = '';
    info_s.year          = '';
    [mfr, team] = resolve_driver_meta_upload(grp.driver, driver_map);
    info_s.manufacturer = mfr;
    if ~isempty(team)
        info_s.team_name = team;
    else
        info_s.team_name = grp.team_acronym;
    end
end

function [mfr, team] = resolve_driver_meta_upload(driver_name, driver_map)
    mfr = ''; team = '';
    if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name), return; end
    name_strip = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]', '');
    keys = fieldnames(driver_map);
    entry_found = [];
    if isfield(driver_map, driver_name)
        entry_found = driver_map.(driver_name);
    end
    if isempty(entry_found)
        for k = 1:numel(keys)
            if strcmp(name_strip, regexprep(lower(keys{k}), '[^a-z0-9]', ''))
                entry_found = driver_map.(keys{k});
                break;
            end
        end
    end
    if isempty(entry_found), return; end   % upload path: skip silently, no keyboard() pause
    if isfield(entry_found, 'manufacturer'), mfr  = entry_found.manufacturer; end
    if isfield(entry_found, 'team_tla'),      team = entry_found.team_tla;    end
end

function cache = add_failed_entries_upload(cache, grp, err_msg)
    info_s = build_info_from_group_upload(grp, []);
    for f = 1:numel(grp.files)
        cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, info_s, false, err_msg);
    end
end

function val = get_opt(s, f, default)
    if isfield(s, f) && ~isempty(s.(f)), val = s.(f);
    else,                                 val = default; end
end