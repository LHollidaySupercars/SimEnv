
function smp_compile_event_upload(top_level_dir, channels_to_extract, ...
                                   season, driver_map, alias, opts)
% SMP_COMPILE_EVENT_UPLOAD  Session-by-session compile, streamed straight
% to SQL — parallel per-session compute+upload, serial fallback.
%
% Standalone from smp_compile_event — does NOT touch the plotting cache,
% does NOT retain full-event stats in RAM, does NOT get called by or
% call into the plotting pipeline. Deliberately duplicates compute.
%
% Behaviour:
%   - Processes ONE SESSION FOLDER AT A TIME (e.g. COM\Q26, COM\R08, ...
%     under an event-wide top_level_dir, or top_level_dir itself if it IS
%     a single session folder). A session is never started until the
%     previous session's compute AND upload are both fully finished.
%   - For EACH session, opts.parallel_compute controls how that session's
%     files are processed:
%       * true  (recommended): the session's files are split across
%         opts.n_compute_workers detached matlab.exe -batch worker
%         processes (see smp_compute_upload_worker.m). Each worker
%         computes (load -> lap_slicer -> lap_stats) AND uploads its own
%         chunk directly, on its OWN SQL connection — so each worker
%         incurs its own Entra ID/MFA prompt. That is intentional: a
%         handful of prompts per session (one per worker) in exchange
%         for real parallel compute+upload, never one prompt per file or
%         per lap. The orchestrator blocks until every worker's done flag
%         is written (compute AND upload both complete) before moving on.
%       * false, or a session with too few files to bother splitting: the
%         session is computed in-process (no workers) and uploaded via a
%         single persistent connection that is opened LAZILY on first
%         actual need and reused for every serial-fallback session in the
%         run — so a run that always goes parallel never opens a main
%         connection at all, and one that sometimes falls back only ever
%         prompts once for that fallback path.
%   - NO stint/session appending: every .ld file is processed and
%     uploaded completely independently, one at a time. Files are NOT
%     grouped or concatenated by driver/session/car — if a team produces
%     multiple (even duplicate) FEE files for the same outing, each one
%     is loaded, lap-sliced and uploaded on its own. This is intentional:
%     duplicates simply produce duplicate uploaded rows for now.
%   - Metadata (driver/session/venue/car/vehicle/engine_id/manufacturer/
%     date/year) is read directly from each file's own header via
%     motec_ld_info, then resolved through the alias tables (driver,
%     session, venue). The event name itself is derived from the event
%     folder in top_level_dir (e.g. 'E09_QLR') and is stamped separately
%     from venue (the real track name, resolved via alias).
%   - CURATED channel set: only channels_to_extract (typically built via
%     smp_build_upload_channel_list — channels_SQL.xlsx whitelist union
%     plottingRequest.xlsx channels) are actually loaded from each .ld
%     file, plus a small fixed INFRA_REQUIRED set lap_slicer itself needs
%     (Lap_Number, Lap_Time, MyLaps/BR2 beacon channels, distance channel)
%     — those infra channels are loaded but not treated as extra "keep
%     everything" bloat. This keeps the uploaded table's column count
%     bounded instead of growing to match every channel ever logged.
%   - Per file: load (curated channels only) -> lap_slicer(all_laps=true)
%     -> lap_stats (fixed stat_ops applied uniformly to every loaded
%     channel — see stat_ops below). Every file/worker's raw stats are
%     MERGED into one session-scoped cache (or uploaded directly by the
%     worker that computed them, in the parallel path) before the heavy
%     flatten/melt transform runs — see smp_compute_upload_chunk.m's
%     header for why this ordering matters (avoids vertcat failures from
%     structurally inconsistent per-file tables).
%   - Maintains its own lightweight manifest-only cache
%     (smp_cache_upload_manifest.mat) purely so repeat runs skip
%     unchanged files. No stats/traces are persisted in this cache.
%
% Inputs:
%   top_level_dir        - event COM folder, e.g. 'E:\2026\E06_DAR\COM'
%   channels_to_extract  - cell array of channel names to load/stat —
%                          build with smp_build_upload_channel_list()
%   season                - from smp_season_load()
%   driver_map            - from smp_driver_alias_load()
%   alias                  - from smp_alias_load()
%   opts                   - struct:
%     .track            track acronym for lap time limits
%     .math_version     REQUIRED — manual code-version stamp, e.g. 'v1.0'
%     .target           'pocketbase' | 'azure_local' | 'azure_online'
%     .flush_rows        row-count buffer threshold for the SERIAL
%                        fallback path only (default 400) — the parallel
%                        path uploads each worker's whole chunk in one go
%                        since a chunk is already small (session's files
%                        / n_compute_workers)
%     .batch             SQL push batch size (default 200)
%     .overwrite         passed through to push opts (default false —
%                         legacy switch: true = 'replace_all', false =
%                         'add_missing'; ignored when .upload_mode is set)
%     .upload_mode       'add_missing' (default) insert only lap+channel rows
%                         not already on the server; 'replace_channels'
%                         insert new and overwrite stored lap+channel rows,
%                         keeping other channels; 'replace_all' wipe the
%                         session+driver then insert
%     .upload_channels   cellstr, replace_channels only: limit overwrite to
%                         these channel names (default {} = all uploaded)
%     .worker_dir         handoff/queue dir (default <top_level_dir>\_upload_queue)
%                         — only used by the SERIAL fallback path's
%                         flush_buffer (despatcher==true sub-case)
%     .keep_worker_open   true = cmd /k, leave window open (default false)
%     .dist_channel       (default 'Odometer')
%     .verbose            (default true)
%     .upload_samples     ADDITIVE, opt-in (default false) — also builds and
%                         uploads a per-lap time-series trace (top
%                         opts.max_traces fastest 'flying' laps of each
%                         file's own laps) to telemetry.LapSamples,
%                         alongside the existing dbo.LapStats/dbo.Laps
%                         upload. Leaves all existing behaviour/tables
%                         untouched when false (the default).
%     .max_traces         fastest laps per file to keep for sample upload
%                         (default 4 — matches cfg.max_traces in the
%                         plotting scripts' package_traces selection)
%     .dist_step          distance-bin size in metres for the common grid
%                         every uploaded lap is resampled onto (default 5
%                         — see smp_extract_lap_samples.m)
%     .max_workers        max concurrent DETACHED upload workers, only
%                         relevant to the SERIAL fallback path's
%                         flush_buffer when despatcher==true (default 4).
%                         Has no effect on opts.parallel_compute's own
%                         worker count (see .n_compute_workers below).
%     .parallel_compute   (default false) — when true, each session's
%                         files are split across .n_compute_workers
%                         detached workers that compute AND upload their
%                         own chunk directly (see behaviour above).
%     .n_compute_workers  detached compute+upload workers per session
%                         when parallel_compute is true (default 4)
%     .compute_tmp_dir    handoff dir for parallel_compute workers
%                         (default <top_level_dir>\_compute_tmp)
%     .compute_poll_s     poll interval in seconds while waiting for
%                         parallel_compute workers to finish (default 3)
%     .compute_timeout_s  max seconds to wait for a session's
%                         parallel_compute workers before erroring
%                         (default 3600)

    if nargin < 6 || isempty(opts), opts = struct(); end

    track            = get_opt(opts, 'track',            '');
    math_version     = get_opt(opts, 'math_version',      '');
    target           = get_opt(opts, 'target',            'azure_online');
    flush_rows       = get_opt(opts, 'flush_rows',         200000);
    batch_size       = get_opt(opts, 'batch',              10000);
    overwrite        = get_opt(opts, 'overwrite',          false);
    upload_mode      = get_opt(opts, 'upload_mode',       '');   % 'add_missing' | 'replace_channels' | 'replace_all'; '' = derive from overwrite
    upload_channels  = get_opt(opts, 'upload_channels',   {});   % replace_channels only: limit overwrite to these channel names

    % opts.existing is the single switch for data already on the server; it sets overwrite + upload_mode together.
    existing = get_opt(opts, 'existing', '');
    switch existing
        case ''
            % legacy: overwrite / upload_mode as given
        case {'skip', 'add'}
            upload_mode = 'add_missing';     overwrite = false;
        case 'update'
            upload_mode = 'replace_channels'; overwrite = true;
        case 'wipe'
            upload_mode = 'replace_all';     overwrite = true;
        otherwise
            error('smp_compile_event_upload: opts.existing must be ''skip'', ''add'', ''update'' or ''wipe'' (got ''%s'').', existing);
    end
    ignore_cache = get_opt(opts, 'ignore_cache', false);   % true = treat every file as new this run
    confirm_wipe = get_opt(opts, 'confirm_wipe', true);    % ask before a 'wipe' run deletes stored data
    only_teams   = upper(cellstr(get_opt(opts, 'only_teams', {})));   % team acronyms to process, e.g. {'DJR'}; {} = every team folder
    only_teams   = only_teams(:)';
    worker_dir       = get_opt(opts, 'worker_dir',         fullfile(top_level_dir, '_upload_queue'));
    keep_worker_open = get_opt(opts, 'keep_worker_open',   false);
    dist_ch          = get_opt(opts, 'dist_channel',       'Ground_Speed');
    ts_channels      = get_opt(opts, 'ts_channels',        {});   % TIM sheet whitelist for telemetry.LapSamples
    verbose          = get_opt(opts, 'verbose',            true);
    despatcher       = get_opt(opts, 'despatcher',         false);
    upload_samples   = get_opt(opts, 'upload_samples',     false);
    samples_only     = get_opt(opts, 'samples_only',       false);   % time series only: skip stats/laps push, own manifest cache
    if samples_only, upload_samples = true; end
    if upload_samples && isempty(ts_channels)
        error('smp_compile_event_upload: upload_samples needs opts.ts_channels (TIM sheet, Upload=1) — an empty list would upload every loaded channel.');
    end
    max_traces       = get_opt(opts, 'max_traces',         4);
    dist_step        = get_opt(opts, 'dist_step',          5);
    max_workers      = get_opt(opts, 'max_workers',        4);

    % ---- Session-level parallel COMPUTE options (SQL push stays serial —
    %      see the persistent-connection note below; this only controls
    %      how the load/lap_slicer/lap_stats/flatten step is fanned out
    %      across detached, no-SQL matlab.exe workers, one session
    %      folder at a time). ----
    parallel_compute   = get_opt(opts, 'parallel_compute',    false);
    preview_check      = get_opt(opts, 'preview_check',       false);  % plot + confirm each session before upload (forces serial path)
    if preview_check, parallel_compute = false; end
    n_compute_workers  = get_opt(opts, 'n_compute_workers',   4);
    compute_tmp_dir    = get_opt(opts, 'compute_tmp_dir',     fullfile(top_level_dir, '_compute_tmp'));
    compute_poll_s     = get_opt(opts, 'compute_poll_s',      3);
    compute_timeout_s  = get_opt(opts, 'compute_timeout_s',   3600);

    if isempty(math_version)
        error('smp_compile_event_upload: opts.math_version is required.');
    end

    if ~exist(worker_dir, 'dir'), mkdir(worker_dir); end

    % ------------------------------------------------------------------
    %  SQL connection strategy
    % ------------------------------------------------------------------
    % When opts.parallel_compute is on, each session's files are split
    % across N detached compute workers, and EACH WORKER now uploads its
    % own chunk directly (own smp_sql_connect call, own MFA prompt — see
    % smp_compute_upload_worker.m). That is an explicit, accepted
    % trade-off: a handful of MFA prompts per session (one per worker)
    % instead of one for the whole run, in exchange for compute AND
    % upload happening genuinely in parallel end-to-end. The main
    % process therefore does NOT open its own connection up front —
    % only the serial fallback path below (used when parallel_compute is
    % off, or a session has too few files to bother splitting) needs
    % one, and it is opened LAZILY on first actual use so a run that
    % never falls back to serial never prompts for the main process at
    % all.
    conn = [];
    conn_needed = ~despatcher && ismember(lower(target), {'azure_local', 'azure_online'});

    % ------------------------------------------------------------------
    %  Lap time limits
    % ------------------------------------------------------------------
    lap_dist = NaN;
    if ~isempty(track) && ~isempty(season)
        [min_lt, max_lt, lap_dist] = smp_season_get(season, track);
    else
        min_lt = 10; max_lt = 600;
    end

    lap_opts.min_lap_time = min_lt;
    lap_opts.max_lap_time = max_lt;
    lap_opts.detect_pitlane = false;
    lap_opts.fcy_channel    = '';
    lap_opts.br2_channel    = get_opt(opts, 'br2_channel', '');
    lap_opts.br2_protocol   = get_opt(opts, 'br2_protocol', 'auto');
    lap_opts.pit_sensor_detect = get_opt(opts, 'pit_sensor_detect', true);
    lap_opts.track_lap_distance = lap_dist;
    lap_opts.min_lap_dist_frac  = get_opt(opts, 'min_lap_dist_frac', 0.95);
    lap_opts.mylaps_channel = 'MyLaps X2TRA DeviceShortId';
    lap_opts.verbose        = false;

    % ---- Fixed op set applied uniformly to every loaded channel ----
    % (Unlike the plotting pipeline's per-channel channel_ops_map, the
    % upload table applies the same ops to every channel in
    % channels_to_extract — simpler, one schema, no per-channel branching.)
    stat_ops = {'min','max','mean','mean non zero','median','std','var', ...
                'range','change','final','initial'};

    % ---- Infra channels lap_slicer needs internally, regardless of
    %      what's in channels_to_extract — loaded but not "extra bloat"
    %      since it's a small fixed list (mirrors the plotting pipeline's
    %      own INFRA_REQUIRED pattern). ----
    INFRA_REQUIRED = {'Lap_Number', 'Lap_Time', 'Running_Lap_Time', ...
                      'Run_Lap_Time', 'Running_Lap_Timer', 'Lap_Timer', ...
                      'Beacon', 'BR2_Beacon_Number', ...
                      'C1_Air Jack', 'Driver Pit Switch', 'Ground_Speed', 'Odometer', ...
                      dist_ch, lap_opts.mylaps_channel};
    INFRA_REQUIRED = unique(INFRA_REQUIRED(~cellfun(@isempty, INFRA_REQUIRED)));

    if isempty(channels_to_extract)
        load_channels = {};   % {} = load everything (no whitelist supplied)
    else
        load_channels = union(union(channels_to_extract(:), INFRA_REQUIRED(:)), ts_channels(:));
    end

    % ------------------------------------------------------------------
    %  1. Enumerate sessions — top_level_dir either IS a single session
    %     folder (teams directly underneath — smp_scan_folders finds them
    %     immediately) or is the whole event COM folder containing one
    %     subfolder per session (e.g. COM\Q26\, COM\R08\..., as used by
    %     events like QLR). Each session is scanned, compiled and
    %     uploaded in its own turn, sequentially, one at a time — see
    %     run_parallel_compute below for how the compute step (only) is
    %     fanned out across workers *within* a session.
    % ------------------------------------------------------------------
    fprintf('\n=== SMP Compile Event UPLOAD (session-by-session, math_version=%s) ===\n', math_version);
    fprintf('Scanning: %s\n\n', top_level_dir);

    session_dirs = list_session_dirs(top_level_dir);

    % ------------------------------------------------------------------
    %  2. Load/init lightweight manifest-only cache (own file, own diff),
    %     shared and updated across every session below.
    % ------------------------------------------------------------------
    manifest_cache_path = fullfile(top_level_dir, 'smp_cache_upload_manifest.mat');
    if samples_only
        manifest_cache_path = fullfile(top_level_dir, 'smp_cache_upload_samples_manifest.mat');
    end
    if exist(manifest_cache_path, 'file') && ~ignore_cache
        s = load(manifest_cache_path, 'cache');
        up_cache = s.cache;
    else
        if ignore_cache, fprintf('ignore_cache = true: every file in %s will be treated as new.\n', top_level_dir); end
        up_cache = smp_cache_empty();
    end
    if ~ismember('GroupKey', up_cache.manifest.Properties.VariableNames)
        up_cache.manifest.GroupKey = repmat({''}, height(up_cache.manifest), 1);
    end

    % ------------------------------------------------------------------
    %  3. Event name — derived from the event folder, e.g.
    %     'F:\2026\E09_QLR\COM' -> 'E09_QLR'. Stamped on every row via
    %     smp_flatten_stats, and used as a fallback venue if a file's
    %     raw venue can't be resolved through the alias table.
    % ------------------------------------------------------------------
    event_name = derive_event_name(top_level_dir);
    fprintf('Event name: %s\n\n', event_name);

    if strcmp(upload_mode, 'replace_all') && confirm_wipe
        fprintf('WARNING: upload_mode is replace_all. Stored data for each session+driver in "%s" will be DELETED and replaced.\n', top_level_dir);
        if ~strcmpi(strtrim(input('Type YES to continue: ', 's')), 'yes')
            error('smp_compile_event_upload: cancelled before any data was deleted.');
        end
    end

    % ---- Shared compute config — identical for every session and every
    %      detached compute worker (see smp_compute_upload_chunk.m /
    %      smp_compute_upload_worker.m). ----
    compute_cfg.driver_map     = driver_map;
    compute_cfg.alias          = alias;
    compute_cfg.event_name     = event_name;
    compute_cfg.load_channels  = load_channels;
    compute_cfg.lap_opts       = lap_opts;
    compute_cfg.stat_ops       = stat_ops;
    compute_cfg.upload_samples = upload_samples;
    compute_cfg.samples_only   = samples_only;
    compute_cfg.max_traces     = max_traces;
    compute_cfg.dist_step      = dist_step;
    compute_cfg.dist_channel   = dist_ch;
    compute_cfg.ts_channels    = ts_channels;
    compute_cfg.ref_length     = lap_dist;
    compute_cfg.math_version   = math_version;

    % ---- Upload settings — ONLY read by smp_compute_upload_worker.m
    %      (each detached compute worker uploads its own chunk directly,
    %      see the SQL connection strategy note above). The serial
    %      fallback path below uses target/batch_size/overwrite directly
    %      via the module-level variables instead of this struct. ----
    compute_cfg.target    = target;
    compute_cfg.batch     = batch_size;
    compute_cfg.overwrite = overwrite;
    compute_cfg.mode      = upload_mode;
    compute_cfg.channels  = upload_channels;

    % ------------------------------------------------------------------
    %  4. Per-session loop: scan -> diff -> compute+upload (serial, ONE
    %     shared connection; or parallel, each worker uploads its own
    %     chunk on its own connection) -> save manifest cache -> move to
    %     the next session. The orchestrator ALWAYS waits for every
    %     worker to finish (compute AND upload) before advancing to the
    %     next session — no session ever starts while a previous
    %     session's workers are still uploading. NO grouping/appending
    %     across files: every file is its own independent group, exactly
    %     as before (duplicate FEE files simply produce duplicate
    %     uploaded
    %     rows — that is acceptable for now).
    % ------------------------------------------------------------------
    flush_count = 0;
    run_labels  = {};
    n_sessions  = numel(session_dirs);

    for si = 1:n_sessions
        session_dir   = session_dirs(si).path;
        session_label = session_dirs(si).label;
        run_labels{end+1} = session_label; %#ok<AGROW>

        fprintf('\n%s\n', repmat('=', 1, 60));
        fprintf('SESSION %d/%d — %s\n', si, n_sessions, session_label);
        fprintf('%s\n', repmat('=', 1, 60));

        session_scan = smp_scan_folders(session_dir);
        if isempty(session_scan)
            fprintf('  [WARN] No team folders found under %s — skipping.\n', session_dir);
            continue;
        end

        if ~isempty(only_teams)
            keep = ismember(upper({session_scan.acronym}), only_teams);
            fprintf('  only_teams = %s: %d of %d team folder(s) selected.\n', strjoin(only_teams, ', '), nnz(keep), numel(keep));
            session_scan = session_scan(keep);
            if isempty(session_scan)
                fprintf('  [WARN] None of the requested teams exist in this session — skipping.\n');
                continue;
            end
        end

        [to_load, up_cache] = smp_cache_diff(up_cache, session_scan);
        if isempty(to_load)
            fprintf('  All files up to date — nothing new for this session.\n');
            continue;
        end
        fprintf('  %d new/changed file(s) to process...\n\n', numel(to_load));

        if parallel_compute && n_compute_workers > 1 && numel(to_load) > 1
            % ---- Parallel path: each worker computes AND uploads its
            %      own chunk directly (own connection, own MFA prompt —
            %      see smp_compute_upload_worker.m). The orchestrator
            %      only gets back manifest bookkeeping rows; it does NOT
            %      merge stats/traces or touch SQL for this session at
            %      all — that already happened inside the workers by the
            %      time run_parallel_compute_and_upload returns (it polls
            %      done_*.flag until every worker, including its upload,
            %      is finished). ----
            [cache_rows, upload_summaries] = run_parallel_compute_and_upload( ...
                to_load, compute_cfg, n_compute_workers, compute_tmp_dir, ...
                compute_poll_s, compute_timeout_s, session_label);

            for r = 1:numel(cache_rows)
                row = cache_rows(r);
                up_cache = smp_cache_add(up_cache, row.file, 0, row.team_acronym, ...
                                          row.info_s, row.success, row.err_msg, row.group_key);
            end

            n_workers_used = numel(upload_summaries);
            flush_count    = flush_count + n_workers_used;
            total_rows     = sum(arrayfun(@(s) s.n_rows_uploaded, upload_summaries));
            total_laps     = sum(arrayfun(@(s) s.n_laps_uploaded, upload_summaries));
            total_samples  = sum(arrayfun(@(s) s.n_samples_uploaded, upload_summaries));
            fprintf('  Parallel upload complete: %d worker(s), %d row(s), %d lap(s), %d sample row(s) uploaded.\n', ...
                n_workers_used, total_rows, total_laps, total_samples);
        else
            % ---- Serial fallback: one in-process compute pass, one
            %      flatten/melt pass, one upload via the single lazily-
            %      opened persistent connection (opened on first actual
            %      need, so a run that always goes parallel never opens
            %      it at all). ----
            [stats_struct, traces_struct, cache_rows] = ...
                smp_compute_upload_chunk(to_load, compute_cfg);

            % ---- Apply manifest rows (success + failure) to the
            %      running, cross-session up_cache (persistent, cross-run
            %      diff cache) — sequential, same process, so no merge
            %      race. Also build a SEPARATE session-scoped manifest
            %      (success rows only) purely to feed
            %      smp_flatten_stats/smp_extract_lap_samples below —
            %      mirrors the combineDataset/plottingScript pattern of
            %      merging every piece into ONE cache before doing the
            %      heavy flatten/melt pass once (see
            %      smp_compute_upload_chunk.m's header for why). ----
            session_cache = smp_cache_empty();
            up_cache_prev = up_cache;   % restored if the preview is declined so files are retried next run
            if ~ismember('GroupKey', session_cache.manifest.Properties.VariableNames)
                session_cache.manifest.GroupKey = repmat({''}, height(session_cache.manifest), 1);
            end
            for r = 1:numel(cache_rows)
                row = cache_rows(r);
                up_cache = smp_cache_add(up_cache, row.file, 0, row.team_acronym, ...
                                          row.info_s, row.success, row.err_msg, row.group_key);
                if row.success
                    session_cache = smp_cache_add(session_cache, row.file, 0, row.team_acronym, ...
                                                   row.info_s, true, '', row.group_key);
                end
            end
            session_cache.stats  = stats_struct;
            session_cache.traces = traces_struct;

            buffer         = table();
            laps_buffer    = table();
            samples_buffer = table();
            T_session      = table();
            if ~isempty(fieldnames(stats_struct))
                T_session = smp_flatten_stats(session_cache, event_name);
                if ismember('id', T_session.Properties.VariableNames)
                    T_session = removevars(T_session, 'id');
                end
                if height(T_session) > 0
                    T_session.math_version = repmat(string(math_version), height(T_session), 1);
                    buffer      = smp_melt_lap_stats(T_session);
                    laps_buffer = smp_extract_lap_types(T_session);
                end

                if upload_samples && ~isempty(fieldnames(traces_struct))
                    samples_buffer = smp_extract_lap_samples(session_cache, event_name, ...
                        struct('dist_step', dist_step, 'dist_channel', dist_ch, ...
                               'ref_length', lap_dist, ...
                               'math_version', math_version));
                end
            end

            if samples_only
                buffer = table(); laps_buffer = table();
            end

            if preview_check && height(T_session) > 0
                [go, preview_check] = preview_laps(T_session, session_label, min_lt);
                if ~go
                    fprintf('  Session "%s" NOT uploaded (declined at preview).\n', session_label);
                    up_cache = up_cache_prev;
                    buffer = table(); laps_buffer = table(); samples_buffer = table();
                end
            end

            if (height(buffer) > 0 || height(laps_buffer) > 0 || height(samples_buffer) > 0) ...
                    && isempty(conn) && conn_needed
                fprintf('  Opening persistent SQL connection for this upload run (target=%s)...\n', target);
                conn = smp_sql_connect(target);
            end

            % ---- Chunk the main buffer into flush_rows-sized pieces
            %      (mirrors the original row-count-triggered flush
            %      cadence) rather than pushing an arbitrarily large
            %      single session buffer in one call. ----
            % Chunk per (session,driver) group: the first chunk runs the
            % MathVersion check/delete, later chunks append only.
            n_buffer_rows = height(buffer);
            if n_buffer_rows > 0
                group_keys = strcat(string(buffer.EventName), '||', string(buffer.Venue), '||', ...
                    string(buffer.SessionName), '||', string(buffer.Year), '||', ...
                    string(buffer.DriverName), '||', string(buffer.Team));
                [~, ~, gidx] = unique(group_keys, 'stable');
                can_chunk = ~despatcher && ~isempty(conn);
                for gi = 1:max(gidx)
                    G = buffer(gidx == gi, :);
                    n_g = height(G);
                    if ~can_chunk
                        flush_count = flush_count + 1;
                        flush_buffer(G, worker_dir, target, batch_size, overwrite, ...
                                      keep_worker_open, flush_count, top_level_dir, despatcher, conn, max_workers, false, '', upload_mode, upload_channels);
                        continue;
                    end
                    row_start = 1;
                    append_only = false;
                    while row_start <= n_g
                        row_end = min(row_start + flush_rows - 1, n_g);
                        flush_count = flush_count + 1;
                        [res, conn] = flush_buffer(G(row_start:row_end, :), worker_dir, target, batch_size, overwrite, ...
                                      keep_worker_open, flush_count, top_level_dir, despatcher, conn, max_workers, append_only, sprintf('%s | %s', session_label, G.DriverName{1}), upload_mode, upload_channels);
                        % NaN means flush_buffer exhausted its retries; stop instead of looping through every remaining chunk.
                        if isnan(res.n_uploaded)
                            error('smp_compile_event_upload: flush %d failed after retries — aborting. Re-run to resume (already-uploaded groups are skipped).', flush_count);
                        end
                        % First chunk inserted nothing and failed nothing => group was already current; skip the rest.
                        if ~append_only && res.n_uploaded == 0 && res.n_failed == 0
                            break;
                        end
                        append_only = true;
                        row_start = row_end + 1;
                    end
                end
            end
            if height(laps_buffer) > 0
                if ~despatcher && ~isempty(conn), conn = ensure_conn(conn, target); end
                flush_laps_buffer(laps_buffer, overwrite, despatcher, conn);
            end
            if height(samples_buffer) > 0
                if ~despatcher && ~isempty(conn), conn = ensure_conn(conn, target); end
                flush_samples_buffer(samples_buffer, overwrite, despatcher, conn, samples_only);
            end
        end

        % ---- Persist manifest cache after every session so a crash
        %      mid-event doesn't lose already-uploaded sessions' diff
        %      state. ----
        cache = up_cache; %#ok<NASGU> — 'cache' is the variable name load() expects back
        save(manifest_cache_path, 'cache');
        fprintf('  Session "%s" done. Manifest cache saved.\n', session_label);
    end

    % ---- Rebuild any LapSeries that no longer matches LapStats (covers failed or skipped rebuilds) ----
    if ~samples_only && ismember(lower(target), {'azure_local', 'azure_online'})
        try
            reconcile_lapseries(target, event_name, run_labels);
        catch ME
            warning('smp_compile_event_upload:reconcile', 'LapSeries reconcile failed: %s', ME.message);
        end
    end

    % ---- Close the persistent connection opened for this run ----
    if ~isempty(conn)
        try
            conn.close();
            fprintf('SQL connection closed.\n');
        catch ME
            fprintf('  [WARN] Could not close SQL connection cleanly: %s\n', ME.message);
        end
    end

    fprintf('\n=== smp_compile_event_upload complete: %d flush(es) queued across %d session(s) ===\n\n', ...
        flush_count, n_sessions);
end


% ======================================================================= %
%  LIST_SESSION_DIRS  Enumerate the session folders to process, in order.
%  If top_level_dir itself contains team folders directly (single-session
%  layout, e.g. a per-session upload script that already points at
%  COM\R28), it is treated as ONE session. Otherwise every immediate
%  non-reserved ('_'-prefixed) subfolder is treated as its own session
%  (e.g. COM\Q26, COM\R08, ... for whole-event COM_DIR callers like
%  E09_QLR_UploadScript.m).
% ======================================================================= %
function sessions = list_session_dirs(top_level_dir)
    sessions = struct('path', {}, 'label', {});

    direct_scan = smp_scan_folders(top_level_dir);
    if ~isempty(direct_scan)
        clean_dir = regexprep(top_level_dir, '[\\/]+$', '');
        [~, leaf] = fileparts(clean_dir);
        sessions(1).path  = top_level_dir;
        sessions(1).label = leaf;
        return;
    end

    d = dir(top_level_dir);
    d = d([d.isdir]);
    d = d(~ismember({d.name}, {'.', '..'}));
    d = d(~startsWith({d.name}, '_'));
    for i = 1:numel(d)
        sessions(end+1).path  = fullfile(top_level_dir, d(i).name); %#ok<AGROW>
        sessions(end).label   = d(i).name;
    end

    if isempty(sessions)
        error('smp_compile_event_upload: No valid team/session folders found under %s.', top_level_dir);
    end
end


% ======================================================================= %
%  RUN_PARALLEL_COMPUTE_AND_UPLOAD  Fan one session's file list out
%  across n_workers detached matlab.exe -batch worker processes (see
%  smp_compute_upload_worker.m / smp_compute_upload_chunk.m). Each worker
%  computes its own chunk AND uploads it directly on its own SQL
%  connection (its own MFA prompt) — the orchestrator does NOT merge
%  stats/traces or touch SQL here at all; it only polls done_*.flag until
%  every worker has finished BOTH computing and uploading, then collects
%  each worker's manifest bookkeeping rows (cache_rows) and upload
%  summary for logging. This intentionally accepts one MFA prompt per
%  worker per session (e.g. 4 workers = 4 prompts) in exchange for
%  compute+upload happening fully in parallel, end-to-end, with never a
%  prompt-per-file/per-lap and never a session starting before every
%  worker of the previous session (compute AND upload) is done.
% ======================================================================= %
function [cache_rows, upload_summaries] = run_parallel_compute_and_upload( ...
        to_load, compute_cfg, n_workers, tmp_dir, poll_s, timeout_s, session_label)

    if ~exist(tmp_dir, 'dir'), mkdir(tmp_dir); end
    delete(fullfile(tmp_dir, 'partial_*.mat'));
    delete(fullfile(tmp_dir, 'done_*.flag'));
    delete(fullfile(tmp_dir, 'chunk_*.mat'));
    delete(fullfile(tmp_dir, 'worker_cfg.mat'));
    delete(fullfile(tmp_dir, 'worker_*.log'));

    n_files   = numel(to_load);
    n_workers = min(n_workers, n_files);

    fprintf('  Parallel compute+upload: %d file(s) across %d worker(s) for session "%s"\n', ...
        n_files, n_workers, session_label);
    fprintf('  (each worker opens its own SQL connection — expect up to %d MFA prompt(s) for this session)\n', ...
        n_workers);

    worker_cfg = compute_cfg; %#ok<NASGU>
    save(fullfile(tmp_dir, 'worker_cfg.mat'), 'worker_cfg');

    chunk_size = ceil(n_files / n_workers);
    for w = 1:n_workers
        i_start = (w-1)*chunk_size + 1;
        i_end   = min(w*chunk_size, n_files);
        if i_start > n_files
            worker_files = to_load([]); %#ok<NASGU>
        else
            worker_files = to_load(i_start:i_end); %#ok<NASGU>
        end
        save(fullfile(tmp_dir, sprintf('chunk_%d.mat', w)), 'worker_files');
    end

    matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    for w = 1:n_workers
        sys_cmd = sprintf('start "Upload Compute Worker %d" cmd /c ""%s" -nosplash -batch "smp_compute_upload_worker(%d, ''%s'')""', ...
            w, matlab_exe, w, strrep(tmp_dir, '\', '\\'));
        system([sys_cmd ' &']);
        fprintf('    Worker %d launched\n', w);
        pause(1.5);
    end

    fprintf('  Waiting for %d compute+upload worker(s) — session will NOT advance until all are done...\n', n_workers);
    t_poll     = tic;
    last_count = -1;
    while true
        done_flags = dir(fullfile(tmp_dir, 'done_*.flag'));
        n_done     = numel(done_flags);
        if n_done ~= last_count
            fprintf('  [%s] %d / %d worker(s) done\n', datestr(now,'HH:MM:SS'), n_done, n_workers);
            last_count = n_done;
        end
        if n_done >= n_workers
            break;
        end
        if toc(t_poll) > timeout_s
            error('run_parallel_compute_and_upload: timeout after %ds waiting for session "%s" workers.', ...
                timeout_s, session_label);
        end
        pause(poll_s);
    end

    cache_rows       = struct('file', {}, 'team_acronym', {}, 'info_s', {}, ...
                               'success', {}, 'err_msg', {}, 'group_key', {});
    upload_summaries = struct('n_rows_uploaded', {}, 'n_rows_failed', {}, ...
                               'n_laps_uploaded', {}, 'n_laps_failed', {}, ...
                               'n_samples_uploaded', {}, 'n_samples_failed', {}, ...
                               'lapseries_pairs', {});

    for w = 1:n_workers
        flag_txt = '';
        try, flag_txt = strtrim(fileread(fullfile(tmp_dir, sprintf('done_%d.flag', w)))); catch, end %#ok<NOCOM>
        if ~strcmp(flag_txt, 'ok')
            fprintf('    [FAIL] Worker %d: %s  (full log: %s)\n', w, flag_txt, ...
                fullfile(tmp_dir, sprintf('worker_%d.log', w)));
        end
    end

    for w = 1:n_workers
        partial_file = fullfile(tmp_dir, sprintf('partial_%d.mat', w));
        if ~exist(partial_file, 'file')
            fprintf('    [WARN] Worker %d produced no output — skipping.\n', w);
            continue;
        end
        pl = load(partial_file, 'cache_rows', 'upload_summary');

        if ~isempty(pl.cache_rows)
            cache_rows = [cache_rows, pl.cache_rows]; %#ok<AGROW>
        end
        upload_summaries(end+1) = pl.upload_summary; %#ok<AGROW>

        fprintf('    Worker %d — %d file result(s), %d row(s)/%d lap(s)/%d sample row(s) uploaded\n', ...
            w, numel(pl.cache_rows), pl.upload_summary.n_rows_uploaded, ...
            pl.upload_summary.n_laps_uploaded, pl.upload_summary.n_samples_uploaded);
    end

    % One serial LapSeries rebuild now that no worker is writing (concurrent rebuilds were ~9x slower).
    all_pairs = zeros(0, 2);
    for k = 1:numel(upload_summaries)
        all_pairs = [all_pairs; upload_summaries(k).lapseries_pairs]; %#ok<AGROW>
    end
    rebuild_lapseries_pairs(unique(all_pairs, 'rows'), compute_cfg.target);

    delete(fullfile(tmp_dir, 'partial_*.mat'));
    delete(fullfile(tmp_dir, 'done_*.flag'));
    delete(fullfile(tmp_dir, 'chunk_*.mat'));
    delete(fullfile(tmp_dir, 'worker_cfg.mat'));
end


% ======================================================================= %
%  REBUILD_LAPSERIES_PAIRS  Refresh dbo.LapSeries (dashboard read layout)
%  for each [SessionID DriverID], one at a time on one connection.
%  A failure only warns: the dashboard falls back to dbo.LapStats.
% ======================================================================= %
function rebuild_lapseries_pairs(pairs, target)
    if isempty(pairs), return; end
    fprintf('  [%s] Rebuilding LapSeries for %d session+driver pair(s)...\n', datestr(now, 'HH:MM:SS'), size(pairs, 1));
    try
        conn = smp_sql_connect(target);
        cleaner = onCleanup(@() conn.close()); %#ok<NASGU>
        st = conn.createStatement();
        for k = 1:size(pairs, 1)
            t_ls = tic;
            st.execute(sprintf('EXEC dbo.BuildLapSeries @SessionID = %d, @DriverID = %d', pairs(k, 1), pairs(k, 2)));
            fprintf('    BuildLapSeries %d/%d (SessionID=%d DriverID=%d) done in %.1fs\n', ...
                k, size(pairs, 1), pairs(k, 1), pairs(k, 2), toc(t_ls));
        end
        st.close();
    catch ME
        warning('smp_compile_event_upload:lapseries', ...
            'LapSeries rebuild failed (dashboard falls back to LapStats): %s', ME.message);
    end
end


% ======================================================================= %
%  RECONCILE_LAPSERIES  Rebuild dbo.LapSeries for every session+driver of
%  the event that has no LapSeriesLaps row or a different series count
%  than dbo.LapStats, whichever upload path wrote the data.
% ======================================================================= %
function reconcile_lapseries(target, event_name, session_names)
    if isempty(session_names), return; end
    conn = smp_sql_connect(target);
    cleaner = onCleanup(@() conn.close()); %#ok<NASGU>
    t0 = tic;
    ps = conn.prepareStatement(['SELECT st.SessionID, st.DriverID FROM ' ...
        '(SELECT x.SessionID, x.DriverID, COUNT(*) AS n_stats FROM ' ...
        ' (SELECT DISTINCT ls.SessionID, ls.DriverID, ls.ChannelID, ls.StatType FROM dbo.LapStats ls ' ...
        '  JOIN dbo.Sessions s ON s.SessionID = ls.SessionID WHERE s.EventName = ? AND s.SessionName IN (' strjoin(repmat({'?'}, 1, numel(session_names)), ',') ')) x ' ...
        ' GROUP BY x.SessionID, x.DriverID) st ' ...
        'LEFT JOIN (SELECT SessionID, DriverID, COUNT(*) AS n_series FROM dbo.LapSeries ' ...
        ' GROUP BY SessionID, DriverID) se ON se.SessionID = st.SessionID AND se.DriverID = st.DriverID ' ...
        'LEFT JOIN dbo.LapSeriesLaps ll ON ll.SessionID = st.SessionID AND ll.DriverID = st.DriverID ' ...
        'WHERE se.n_series IS NULL OR se.n_series <> st.n_stats OR ll.SessionID IS NULL ' ...
        'ORDER BY st.SessionID, st.DriverID']);
    ps.setString(1, event_name);
    for k = 1:numel(session_names), ps.setString(k + 1, session_names{k}); end
    rs = ps.executeQuery();
    pairs = zeros(0, 2);
    while rs.next(), pairs(end+1, :) = [double(rs.getInt(1)) double(rs.getInt(2))]; end %#ok<AGROW>
    rs.close(); ps.close();
    fprintf('[%s] LapSeries check for %s: %d stale session+driver pair(s) (%.1fs).\n', ...
        datestr(now, 'HH:MM:SS'), event_name, size(pairs, 1), toc(t0));
    st = conn.createStatement();
    n_failed = 0;
    for k = 1:size(pairs, 1)
        t_ls = tic;
        try
            st.execute(sprintf('EXEC dbo.BuildLapSeries @SessionID = %d, @DriverID = %d', pairs(k, 1), pairs(k, 2)));
            fprintf('    BuildLapSeries %d/%d (SessionID=%d DriverID=%d) done in %.1fs\n', ...
                k, size(pairs, 1), pairs(k, 1), pairs(k, 2), toc(t_ls));
        catch ME
            n_failed = n_failed + 1;
            fprintf('    [WARN] BuildLapSeries failed for SessionID=%d DriverID=%d: %s\n', ...
                pairs(k, 1), pairs(k, 2), strtok(char(ME.message), newline));
        end
    end
    st.close();
    if n_failed > 0
        fprintf('  [WARN] %d pair(s) still stale; the dashboard falls back to LapStats for them. Re-run to retry.\n', n_failed);
    end
end


% ======================================================================= %
%  PREVIEW_LAPS  Plot lap times per driver, list suspicious laps, and ask
%  whether to upload. Returns go=false to skip; turns preview off if the
%  user answers 'a' (upload this and all remaining sessions unchecked).
% ======================================================================= %
function [go, keep_preview] = preview_laps(T, label, min_lap)
    go = true; keep_preview = true;
    is_fly = strcmp(T.lap_type, 'flying');
    is_untyped = cellfun(@isempty, T.lap_type);   % empty type = slicer fell back to Lap_Number (Mode C)
    med    = median(T.lap_time(is_fly & isfinite(T.lap_time)), 'omitnan');
    if isnan(med), med = median(T.lap_time, 'omitnan'); end
    suspect = is_fly & T.lap_time < min_lap;

    [drivers, ~, di] = unique(T.driver, 'stable');
    f = figure('Name', ['Upload preview - ' label], 'NumberTitle', 'off');
    hold on; grid on;
    scatter(di(~is_fly & ~is_untyped), T.lap_time(~is_fly & ~is_untyped), 25, [0.6 0.6 0.6], 'filled');
    scatter(di(is_fly & ~suspect), T.lap_time(is_fly & ~suspect), 30, 'b', 'filled');
    scatter(di(suspect), T.lap_time(suspect), 60, 'r', 'filled');
    scatter(di(is_untyped), T.lap_time(is_untyped), 40, [1 0.5 0], 'filled');
    yline(med, '--k', sprintf('median flying %.2fs', med));
    set(gca, 'XTick', 1:numel(drivers), 'XTickLabel', drivers, 'XTickLabelRotation', 60);
    ylabel('Lap time (s)'); title(sprintf('%s: grey=non-flying, blue=flying, red=suspect, orange=untyped', label), 'Interpreter', 'none');
    legend({'non-flying', 'flying', 'suspect', 'untyped'}, 'Location', 'best');
    drawnow;

    fprintf('\n  PREVIEW %s: %d laps, %d flying, %d untyped, median flying %.3fs\n', label, height(T), sum(is_fly), sum(is_untyped), med);
    for d = 1:numel(drivers)
        ty = T.lap_type(di == d);
        ty(cellfun(@isempty, ty)) = {'(untyped)'};
        [ut, ~, ui] = unique(ty);
        cnt = accumarray(ui, 1);
        parts = arrayfun(@(k) sprintf('%s=%d', ut{k}, cnt(k)), 1:numel(ut), 'UniformOutput', false);
        fprintf('    %-22s %s\n', drivers{d}, strjoin(parts, '  '));
    end
    idx = find(suspect);
    for k = 1:numel(idx)
        fprintf('    SUSPECT  %-22s lap %-3d  %.3fs\n', T.driver{idx(k)}, T.lap_number(idx(k)), T.lap_time(idx(k)));
    end
    if isempty(idx), fprintf('    no suspect flying laps.\n'); end

    ans_s = lower(strtrim(input('  Upload this session? [y]es / [n]o / [a]ll remaining without checking: ', 's')));
    if ishandle(f), close(f); end
    switch ans_s
        case 'a', keep_preview = false;
        case 'y'
        otherwise, go = false;
    end
end


% ======================================================================= %
%  ENSURE_CONN  Return a live connection, reconnecting if the old one was
%  dropped (idle timeout, sleep, network change).
% ======================================================================= %
function conn = ensure_conn(conn, target)
    ok = false;
    try, ok = ~isempty(conn) && conn.isValid(10); catch, end %#ok<NOCOM>
    if ok, return; end
    fprintf('  [%s] SQL connection no longer valid — reconnecting...\n', datestr(now, 'HH:MM:SS'));
    try, conn.close(); catch, end %#ok<NOCOM>
    conn = smp_sql_connect(target);
end


% ======================================================================= %
%  FLUSH — write buffer to disk, launch DETACHED non-blocking worker
%  (or, when a persistent connection is supplied, push in-process reusing
%  it directly — no detached process, no repeated authentication)
% ======================================================================= %
function [result, conn] = flush_buffer(T, worker_dir, target, batch_size, overwrite, keep_open, flush_id, top_level_dir, despatcher, conn, max_workers, append_only, upload_label, upload_mode, upload_channels)
    if nargin < 9 || isempty(despatcher), despatcher = false; end
    if nargin < 10, conn = []; end
    if nargin < 11 || isempty(max_workers), max_workers = 4; end
    if nargin < 12, append_only = false; end
    if nargin < 13, upload_label = ''; end
    if nargin < 14, upload_mode = ''; end
    if nargin < 15, upload_channels = {}; end
    result = struct('n_uploaded', NaN, 'n_failed', NaN, 'errors', {{}});

    ts        = datestr(now, 'yyyymmdd_HHMMSS');
    flag_file = fullfile(worker_dir, sprintf('upload_%s_%03d.done', ts, flush_id));
    log_file  = fullfile(worker_dir, sprintf('upload_%s_%03d.log',  ts, flush_id));

    % ---- Fast path: reuse the caller's already-open connection ----
    % Skips the .mat save/reload round trip (that round trip only exists
    % to hand data across a process boundary for the detached case) and
    % calls smp_push_to_sql directly with the SAME connection object used
    % by every other flush in this run — so this is the ONLY code path
    % that avoids a fresh smp_sql_connect() (and fresh Azure AD/MFA
    % prompt) per flush.
    if ~despatcher && ~isempty(conn)
        diary(log_file);
        % fprintf('[%s] smp_compile_event_upload: in-process flush %d — %d row(s) -> %s (reused connection)\n', ...
        %     datestr(now, 'HH:MM:SS'), flush_id, height(T), upper(target));
        fprintf('[%s] smp_compile_event_upload: in-process flush %d [%s] — %d row(s) -> %s (reused connection)\n', ...
            datestr(now, 'HH:MM:SS'), flush_id, upload_label, height(T), upper(target));
        opts_sql           = struct();
        opts_sql.batch     = batch_size;
        opts_sql.overwrite = overwrite;
        opts_sql.mode      = upload_mode;
        opts_sql.channels  = upload_channels;
        opts_sql.dry_run   = false;
        opts_sql.append_only = append_only;
        max_attempts = 3;
        for attempt = 1:max_attempts
            try
                conn = ensure_conn(conn, target);
                result = smp_push_to_sql(T, conn, opts_sql);
                fprintf('[%s] Complete: %d uploaded, %d failed.\n', ...
                    datestr(now, 'HH:MM:SS'), result.n_uploaded, result.n_failed);
                fid = fopen(flag_file, 'w');
                fprintf(fid, 'ok\nuploaded=%d\nfailed=%d\n', result.n_uploaded, result.n_failed);
                fclose(fid);
                break;
            catch ME
                fprintf('[%s] [ERROR] %s\n', datestr(now, 'HH:MM:SS'), ME.message);
                % smp_push_to_sql rolls back on a thrown error, so retrying the whole chunk cannot duplicate rows.
                is_conn_err = ~isempty(regexpi(ME.message, 'closed|reset|broken pipe|socket|timed out|connection', 'once'));
                if is_conn_err && attempt < max_attempts
                    fprintf('  Connection error — reconnecting and retrying (attempt %d/%d)...\n', attempt + 1, max_attempts);
                    try, conn.close(); catch, end %#ok<NOCOM>
                    pause(2 * attempt);
                    try
                        conn = smp_sql_connect(target);
                    catch ME2
                        fprintf('  [ERROR] Reconnect failed: %s\n', ME2.message);
                    end
                    continue;
                end
                fid = fopen(flag_file, 'w');
                fprintf(fid, 'error\n%s\n', ME.message);
                fclose(fid);
                break;
            end
        end
        diary off;
        return;
    end

    % ---- Fallback path: no persistent connection supplied (e.g.
    %      pocketbase target, or despatcher==true) — unchanged legacy
    %      behavior: save buffer to disk, launch/invoke smp_upload_worker,
    %      which opens its own connection. Detached mode necessarily
    %      re-authenticates per flush since each is a separate OS process. ----
    data_file = fullfile(worker_dir, sprintf('upload_%s_%03d.mat', ts, flush_id));

    upload_opts.target    = target;
    upload_opts.batch     = batch_size;
    upload_opts.overwrite = overwrite;
    upload_opts.mode      = upload_mode;
    upload_opts.channels  = upload_channels;
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
    if keep_open
        launch_mode = 'cmd /k';
    else
        launch_mode = 'cmd /c';
    end

    if despatcher
        % ---- Concurrency cap: block until fewer than max_workers detached
        %      matlab.exe jobs are in-flight before launching another one. ----
        wait_for_worker_slot(worker_dir, max_workers, flush_id);

        cmd = sprintf('%s start "" "%s" -nosplash -batch "smp_upload_worker(''%s'')"', ...
            launch_mode, matlab_exe, strrep(data_file, '\', '\\'));

        fprintf('  [FLUSH %d] %d row(s) -> detached worker (%s)\n', flush_id, height(T), target);
        system([cmd ' &']);   % '&' keeps this MATLAB session non-blocking on Windows shell
    else
        smp_upload_worker(strrep(data_file, '\', '\\'));
    end
end


% ======================================================================= %
%  WORKER THROTTLE — block until fewer than max_workers detached jobs are
%  in-flight. An "in-flight" job is one whose .mat handoff file exists in
%  worker_dir but whose .done flag has not yet been written by
%  smp_upload_worker.m on completion. Only called from the despatcher==true
%  branch above — the in-process (despatcher==false) path never spawns
%  concurrent OS processes, so no cap is needed there.
% ======================================================================= %
function wait_for_worker_slot(worker_dir, max_workers, flush_id)
    if isempty(max_workers) || ~isfinite(max_workers) || max_workers <= 0
        return; % unlimited
    end

    poll_s = 2;
    warned = false;
    while true
        data_files = dir(fullfile(worker_dir, 'upload_*.mat'));
        n_inflight = 0;
        for k = 1:numel(data_files)
            [~, name] = fileparts(data_files(k).name);
            done_file = fullfile(worker_dir, [name '.done']);
            if ~isfile(done_file)
                n_inflight = n_inflight + 1;
            end
        end

        if n_inflight < max_workers
            return;
        end

        if ~warned
            fprintf('  [FLUSH %d] %d worker(s) already in-flight (max %d) — waiting for a slot...\n', ...
                flush_id, n_inflight, max_workers);
            warned = true;
        end
        pause(poll_s);
    end
end


% ======================================================================= %
%  FLUSH LAPS — push LapType classification rows to dbo.Laps.
%  Only supported via the in-process persistent-connection path (mirrors
%  flush_buffer's fast path) — the Laps table is small and this feature
%  is new, so no detached/.mat-handoff path is implemented for it; if
%  despatcher==true or no persistent connection is available (e.g.
%  pocketbase target), this is a no-op with a warning rather than an error.
% ======================================================================= %
function flush_laps_buffer(T, overwrite, despatcher, conn)
    if despatcher || isempty(conn)
        fprintf('  [WARN] Laps upload skipped: requires despatcher=false and a persistent SQL connection (target azure_local/azure_online).\n');
        return;
    end
    try
        opts_laps           = struct();
        opts_laps.overwrite  = overwrite;
        opts_laps.dry_run    = false;
        result = smp_push_laps_to_sql(T, conn, opts_laps);
        fprintf('  [LAPS FLUSH] %d row(s): %d uploaded, %d failed.\n', ...
            height(T), result.n_uploaded, result.n_failed);
    catch ME
        fprintf('  [ERROR] Laps upload failed: %s\n', ME.message);
    end
end


% ======================================================================= %
%  FLUSH SAMPLES — push time-series lap-trace rows to telemetry.LapSamples.
%  Mirrors flush_laps_buffer exactly (in-process persistent-connection
%  path only; no detached/.mat-handoff path, same reasoning — small
%  buffer, new feature). Deliberately calls a SEPARATE push function
%  (smp_push_lap_samples_to_sql, targeting telemetry.LapSamples) from
%  flush_buffer's dbo.LapStats path — no shared code path between the two
%  tables (see smp_push_lap_samples_to_sql.m's header for the rationale).
% ======================================================================= %
function flush_samples_buffer(T, overwrite, despatcher, conn, abort_on_error)
    if nargin < 5, abort_on_error = false; end
    if despatcher || isempty(conn)
        fprintf('  [WARN] LapSamples upload skipped: requires despatcher=false and a persistent SQL connection (target azure_local/azure_online).\n');
        return;
    end
    try
        opts_samples           = struct();
        opts_samples.overwrite = overwrite;
        opts_samples.dry_run   = false;
        result = smp_push_lap_traces_to_sql(T, conn, opts_samples);
        fprintf('  [SAMPLES FLUSH] %d row(s): %d uploaded, %d failed.\n', ...
            height(T), result.n_uploaded, result.n_failed);
    catch ME
        fprintf('  [ERROR] LapSamples upload failed: %s\n', ME.message);
        if abort_on_error, rethrow(ME); end   % keep the manifest cache from marking these files done
    end
end


% ======================================================================= %
%  Trimmed local helpers — build_upload_lap_traces, build_file_group and
%  the driver/venue/session resolution helpers that used to live here
%  have MOVED to smp_compute_upload_chunk.m (they are per-file compute
%  logic, now shared between the in-process serial path and the detached
%  smp_compute_upload_worker.m processes). Only orchestration-level
%  helpers remain in this file.
% ======================================================================= %
function name = derive_event_name(top_level_dir)
% DERIVE_EVENT_NAME  Extract the event code from anywhere in top_level_dir.
%
% top_level_dir may point at the whole event's COM folder
% ('F:\2026\E09_QLR\COM') OR at a single session subfolder within it
% ('F:\2026\E09_QLR\COM\R28' — the latter is how per-session upload
% scripts, e.g. E09_QLR_UploadScript.m, actually invoke this function).
% Either way the event code (ENN_XXX, e.g. 'E09_QLR') is a path
% component, so search every component for that pattern first rather
% than assuming a fixed depth relative to 'COM'.
    d = regexprep(strtrim(top_level_dir), '[\\/]+$', '');
    parts = strsplit(d, {'\\', '/'});
    parts = parts(~cellfun(@isempty, parts));

    event_pat = '^E\d+_[A-Za-z0-9]+$';
    for i = numel(parts):-1:1
        if ~isempty(regexp(parts{i}, event_pat, 'once'))
            name = parts{i};
            return;
        end
    end

    % Fallback — no ENN_XXX component found: use the leaf folder, or its
    % parent if the leaf is a generic 'COM' container.
    [parent, leaf] = fileparts(d);
    if strcmpi(leaf, 'COM') && ~isempty(parent)
        [~, leaf] = fileparts(parent);
    end
    name = leaf;
    if isempty(name), name = 'UNKNOWN_EVENT'; end
end

function val = get_opt(s, f, default)
    if isfield(s, f) && ~isempty(s.(f)), val = s.(f);
    else,                                 val = default; end
end