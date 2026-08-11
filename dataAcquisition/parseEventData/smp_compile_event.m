function cache = smp_compile_event(top_level_dir, team_filter, ...
                                    channels_to_extract, season, ...
                                    driver_map, alias, opts)
% SMP_COMPILE_EVENT  Scan, load, process and cache .ld files for an event.
%
% This is the new top-level compiler that replaces the old bulk-load approach
% in smp_load_teams. It supports two modes:
%
%   'stream'  (default) — process one .ld file group at a time.
%             Raw channel data is cleared after stats are extracted.
%             Peak RAM = approximately one .ld file at a time.
%             Recommended for all machines with < 32 GB RAM.
%
%   'bulk'    (legacy)  — load all files then process.
%             Same behaviour as the original smp_load_teams.
%             Requires a password confirmation before proceeding.
%             Only use on high-RAM workstations.
%
% Usage:
%   cache = smp_compile_event(top_level_dir, team_filter, ...
%               channels_to_extract, season, driver_map, alias)
%   cache = smp_compile_event(..., opts)
%
% Inputs:
%   top_level_dir       - path to team data folder
%   team_filter         - cell array of team acronyms, e.g. {'T8R','WAU'}
%                         pass {} to process all teams
%   channels_to_extract - cell array from smp_channel_config_load()
%   season              - struct from smp_season_load()
%   driver_map          - struct from smp_driver_alias_load()
%   alias               - struct from smp_alias_load()
%   opts                - optional struct:
%     .mode             'stream' (default) or 'bulk'
%     .track            track acronym for lap time limits e.g. 'SMP'
%                       (required to use season lap time limits)
%     .max_traces       number of top-N laps to keep as traces (default: 5)
%     .dist_n_points    distance interpolation grid points (default: 1000)
%     .dist_channel     distance channel name (default: 'Odometer')
%     .verbose          (default: true)
%     .date_from        datetime/datenum — only load files on or after this date
%                       e.g. datetime(2026,3,5)  (default: [] = all files)
%     .detect_pitlane   enable pit-lane detection via beacon channel (default: false)
%     .fcy_channel      FCY flag channel name (default: 'FCY_Flag')
%
% Output:
%   cache   - compiled cache struct (stats + traces in stream mode,
%             or raw channels in bulk mode). Also saved to disk.

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 7 || isempty(opts), opts = struct(); end

    mode          = get_opt(opts, 'mode',           'stream');
    track         = get_opt(opts, 'track',          '');
    max_traces    = get_opt(opts, 'max_traces',      inf);
    all_laps      = get_opt(opts, 'all_laps',         false);
    dist_npts     = get_opt(opts, 'dist_n_points',   1000);
    dist_ch       = get_opt(opts, 'dist_channel',    'Odometer');
    verbose       = get_opt(opts, 'verbose',         true);
    date_from     = get_opt(opts, 'date_from',       []);
%     saveCache     = get_opt(opts, 'saveCache',       true);
    saveCache     = get_opt(opts, 'saveCache',      true);
    channel_rules  = get_opt(opts, 'channel_rules',   []);
    save_mode      = get_opt(opts, 'save_mode',        'stream');
    session_filter = get_opt(opts, 'session_filter',   {});
    detect_pitlane = get_opt(opts, 'detect_pitlane',   false);
    fcy_channel    = get_opt(opts, 'fcy_channel',      'FCY_Flag');
    br2_channel    = get_opt(opts, 'br2_channel',      'BR2_Beacon_Number');
    br2_protocol   = get_opt(opts, 'br2_protocol',     'standard');
    beacon_check   = get_opt(opts, 'beacon_check',     false);
    l180_mode      = get_opt(opts, 'l180_mode',        'drop_duplicate');
    unique_fp      = get_opt(opts, 'uniqueFingerprint',  false);
    show_report    = get_opt(opts, 'showConcatReport',   false);
    concat_csv_dir = get_opt(opts, 'concat_csv_dir',     '');
    load_all_ch    = get_opt(opts, 'load_all_channels',  false);
    T_gated        = get_opt(opts, 'T_gated',            table());
    pre_groups     = get_opt(opts, 'groups',             []);

    % ------------------------------------------------------------------
    %  Lap time limits from season overview
    % ------------------------------------------------------------------
    if ~isempty(track) && ~isempty(season)
        [min_lt, max_lt] = smp_season_get(season, track);
        fprintf('Lap time limits for %s: %.1fs – %.1fs\n', track, min_lt, max_lt);
    else
        min_lt = 10;
        max_lt = 600;
        if isempty(track)
            fprintf('[WARN] No track specified — using default lap time limits (10s / 600s).\n');
        end
    end

    % ------------------------------------------------------------------
    %  Worker shortcut: pre-built groups supplied — skip scan/diff/group
    %  (used by smp_compile_worker so process_stream is the single source
    %   of truth for both serial and parallel paths)
    % ------------------------------------------------------------------
if ~isempty(pre_groups)
    cache = smp_cache_empty();
    cache.stats  = struct();
    cache.traces = struct();
    cache.laps   = struct();
    cache.mode   = 'stream';
    if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
        cache.manifest.GroupKey = repmat({''}, 0, 1);
    end
    % cache = process_stream(cache, pre_groups, channels_to_extract, ...
    %                        min_lt, max_lt, max_traces, dist_npts, ...
    %                        dist_ch, driver_map, verbose, channel_rules, ...
    %                        detect_pitlane, fcy_channel, ...
    %                        br2_channel, br2_protocol, ...
    %                        unique_fp, show_report, concat_csv_dir, all_laps, load_all_ch, T_gated, l180_mode);
    cache = process_stream(cache, pre_groups, channels_to_extract, ...
        min_lt, max_lt, max_traces, dist_npts, ...
        dist_ch, driver_map, verbose, channel_rules, ...
        detect_pitlane, fcy_channel, ...
        br2_channel, br2_protocol, ...
        unique_fp, show_report, concat_csv_dir, all_laps, load_all_ch, T_gated, l180_mode, ...
        get_opt(opts, 'channel_ops_map', []));   % <-- NEW — this is where get_opt(opts,...) belongs
    return;
end
    % ------------------------------------------------------------------
    %  1. Scan folders
    % ------------------------------------------------------------------
    fprintf('\n=== SMP Compile Event ===\n');
    fprintf('Mode: %s\n', upper(mode));
    fprintf('Scanning: %s\n\n', top_level_dir);

    scan_all = smp_scan_folders(top_level_dir);
    if isempty(scan_all)
        error('smp_compile_event: No valid team folders found.');
    end

    if isempty(team_filter)
        scan_load = scan_all;
    else
        scan_load = filter_scan(scan_all, team_filter);
    end

    if isempty(scan_load)
        error('smp_compile_event: No teams matched filter: %s', ...
            strjoin(team_filter, ', '));
    end

    % ------------------------------------------------------------------
    %  1b. Date filter — keep only files on or after date_from
    % ------------------------------------------------------------------
    if ~isempty(date_from)
        date_from_dn = datenum(date_from);
        for i = 1:numel(scan_load)
            files = scan_load(i).files;
            keep  = false(1, numel(files));
            for j = 1:numel(files)
                d = dir(files{j});
                keep(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
            end
            scan_load(i).files = files(keep);
        end
        % Remove teams with no files remaining
        scan_load = scan_load(arrayfun(@(t) ~isempty(t.files), scan_load));
        if verbose
            n_files = sum(arrayfun(@(t) numel(t.files), scan_load));
            fprintf('date_from filter (%s): %d file(s) retained.\n\n', ...
                datestr(date_from_dn, 'dd-mmm-yyyy'), n_files);
        end
        if isempty(scan_load)
            fprintf('No files found on or after %s — nothing to compile.\n\n', ...
                datestr(date_from_dn, 'dd-mmm-yyyy'));
            cache = smp_cache_load(top_level_dir, session_filter);
            if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
            if ~isfield(cache, 'traces'), cache.traces = struct(); end
            return;
        end
    end

    % ------------------------------------------------------------------
    %  2. Load or initialise cache
    % ------------------------------------------------------------------
    cache = smp_cache_load(top_level_dir, session_filter);

    % Backwards compatibility — old caches may lack stats/traces fields
    if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
    if ~isfield(cache, 'traces'), cache.traces = struct(); end

    % Old manifest won't have GroupKey column — add it as empty strings
    if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
        cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
    end

    % If cached mode doesn't match requested mode, warn but don't force switch
    if isfield(cache, 'mode') && ~strcmp(cache.mode, mode)
        fprintf('[WARN] Existing cache was built in ''%s'' mode, but ''%s'' was requested.\n', ...
            cache.mode, mode);
        fprintf('       Cache will be used as-is. To switch modes, delete the cache file.\n\n');
        mode = cache.mode;   % honour existing cache mode
    elseif ~isfield(cache, 'mode')
        cache.mode = mode;
    end

    % ------------------------------------------------------------------
    %  3. Diff against disk — find new/changed files
    % ------------------------------------------------------------------
    [to_load, cache] = smp_cache_diff(cache, scan_load);

    if isempty(to_load)
        fprintf('All files up to date — nothing new to compile.\n\n');
        return;
    end

    fprintf('\n%d new/changed file(s) to compile...\n\n', numel(to_load));

    % ------------------------------------------------------------------
    %  4. Group files by driver/session/car (handles multi-stint)
    % ------------------------------------------------------------------
    groups = smp_append_stints(to_load, driver_map, alias, session_filter);

    % ------------------------------------------------------------------
    %  5. Process based on mode
    % ------------------------------------------------------------------
%     if strcmp(mode, 'stream')
%         cache = process_stream(cache, groups, channels_to_extract, ...
%                                min_lt, max_lt, max_traces, dist_npts, ...
%                                dist_ch, driver_map, verbose);
    if strcmp(mode, 'stream')
        % cache = process_stream(cache, groups, channels_to_extract, ...
        %                min_lt, max_lt, max_traces, dist_npts, ...
        %                dist_ch, driver_map, verbose, channel_rules, ...
        %                detect_pitlane, fcy_channel, ...
        %                br2_channel, br2_protocol, ...
        %                unique_fp, show_report, concat_csv_dir, all_laps, load_all_ch, T_gated, l180_mode);
        cache = process_stream(cache, groups, channels_to_extract, ...
            min_lt, max_lt, max_traces, dist_npts, ...
            dist_ch, driver_map, verbose, channel_rules, ...
            detect_pitlane, fcy_channel, ...
            br2_channel, br2_protocol, ...
            unique_fp, show_report, concat_csv_dir, all_laps, load_all_ch, T_gated, l180_mode, ...
            get_opt(opts, 'channel_ops_map', []));   % <-- NEW — this is where get_opt(opts,...) belongs
        
    else
        cache = process_bulk(cache, groups, channels_to_extract, verbose);
    end

    % ------------------------------------------------------------------
    %  6. Save cache to disk
    % ------------------------------------------------------------------
    fprintf('\nSaving cache...\n');
    if saveCache
        tic;
        smp_cache_save(top_level_dir, cache, save_mode, alias);
        t_save = toc;
        fprintf('Cache saved in %.1fs.\n\n', t_save);
    end
end


% ======================================================================= %
%  STREAM PROCESSING
% ======================================================================= %
% function cache = process_stream(cache, groups, channels_to_extract, ...
%                                  min_lt, max_lt, max_traces, dist_npts, ...
%                                  dist_ch, driver_map, verbose)
function cache = process_stream(cache, groups, channels_to_extract, ...
                                 min_lt, max_lt, max_traces, dist_npts, ...
                                 dist_ch, driver_map, verbose, channel_rules, ...
                                 detect_pitlane, fcy_channel, ...
                                 br2_channel, br2_protocol, ...
                                 unique_fp, show_report, concat_csv_dir, all_laps, load_all_ch, T_gated, l180_mode, channel_ops_map)
    if nargin < 11, channel_rules  = [];                  end
    if nargin < 12, detect_pitlane = false;               end
    if nargin < 13, fcy_channel    = 'FCY_Flag';          end
    if nargin < 14, br2_channel    = 'BR2_Beacon_Number'; end
    if nargin < 15, br2_protocol   = 'standard';          end
    if nargin < 16, unique_fp      = false;               end
    if nargin < 17, show_report    = false;               end
    if nargin < 18, concat_csv_dir = '';                  end
    if nargin < 19, all_laps       = false;               end
    if nargin < 20, load_all_ch    = false;               end
    if nargin < 21, T_gated        = table();             end
    if nargin < 22, l180_mode      = 'drop_duplicate';    end
    if nargin < 23, channel_ops_map = [];                 end   % <-- NEW
    MYLAPS_CH_DEFAULT        = 'MyLaps X2TRA DeviceShortId';
    lap_opts.min_lap_time    = min_lt;
    lap_opts.max_lap_time    = max_lt;
    lap_opts.detect_pitlane  = detect_pitlane;
    lap_opts.fcy_channel     = fcy_channel;
    lap_opts.br2_channel     = br2_channel;
    lap_opts.br2_protocol    = br2_protocol;
    lap_opts.mylaps_channel  = MYLAPS_CH_DEFAULT;
    lap_opts.verbose         = false;

    dist_opts.distance_channel = dist_ch;
    dist_opts.resolution       = [];
    dist_opts.common_grid      = true;
    dist_opts.verbose          = false;

    groups   = split_l180_groups(groups, l180_mode, verbose);
    n_groups = numel(groups);

    for g = 1:n_groups
        grp = groups(g);
        fprintf('[%d/%d] %s | %s | %s | %d file(s)\n', ...
            g, n_groups, grp.team_acronym, grp.driver, grp.session, grp.n_files);

        % ---- Load and concatenate stints ----
        % Inject beacon/FCY channels into the extraction list so
        % filter_channels doesn't strip them before lap_slicer runs.
        required_ch = {};
        if detect_pitlane
            required_ch{end+1} = lap_opts.mylaps_channel;
        end
        if ~isempty(fcy_channel)
            required_ch{end+1} = fcy_channel;
        end
        if ~isempty(br2_channel)
            required_ch{end+1} = br2_channel;
        end
        ch_extract_full = unique([channels_to_extract(:); required_ch(:)]);
        try
            session = load_and_concat(grp.files, ch_extract_full, verbose, ...
                          unique_fp, show_report, grp.key, concat_csv_dir, load_all_ch, driver_map, T_gated, l180_mode);
        catch ME
            fprintf('  [ERROR] Load failed: %s\n', ME.message);
            cache = add_failed_entries(cache, grp, ME.message);
            continue;
        end

        if isempty(session)
            fprintf('  [WARN] No channel data returned — skipping.\n');
            continue;
        end

        % ---- Lap slice ----
        try

            laps = lap_slicer(session, lap_opts);
        catch ME
            fprintf('  [ERROR] lap_slicer: %s\n', ME.message);
            cache = add_failed_entries(cache, grp, ME.message);
            clear session;
            continue;
        end

        if isempty(laps)
            fprintf('  [WARN] No valid laps found — skipping.\n');
            cache = add_failed_entries(cache, grp, 'No valid laps');
            clear session;
            continue;
        end

        fprintf('  %d valid laps\n', numel(laps));

        % ---- Data quality filter (NaN bad samples before stats) ----
        if ~isempty(channel_rules)
            laps = smp_data_filter(laps, channel_rules);
        end

        % ---- Compute per-lap stats ----
        % ---- Compute per-lap stats ----
        try
            % Detect custom channels added by smp_custom_channels / smp_gated_channels
            all_session_fields = fieldnames(session);
            raw_fields_san     = cellfun(@(c) regexprep(c, '[^a-zA-Z0-9_]', '_'), ...
                                         channels_to_extract, 'UniformOutput', false);
            raw_fields_lower   = lower([channels_to_extract(:); raw_fields_san(:)]);
            custom_fields      = all_session_fields( ...
                ~ismember(lower(all_session_fields), raw_fields_lower));

            gated_names = {};
            if ~isempty(T_gated) && istable(T_gated) && ...
               ismember('CHANNEL_NAME', T_gated.Properties.VariableNames)
                gated_names = T_gated.CHANNEL_NAME(:);
            end

            stat_channels = unique([channels_to_extract(:); gated_names(:); custom_fields(:)]);

            % ---- Original (pre-optimization) call, kept for easy revert ----
            % stats = lap_stats(laps, stat_channels, ...
            %     struct('operations', {{'max','min','mean','median','std','var','range',...
            %     'max non zero','min non zero','mean non zero','median non zero','std non zero','sample_rate','change'}}));

            stat_ops = {'max','min','mean','median','std','var','range',...
                        'max non zero','min non zero','mean non zero','median non zero','std non zero','sample_rate','change'};

            if ~isempty(channel_ops_map)
                stats_channels = keys(channel_ops_map);
                lap_stats_opts = struct('per_channel_ops', channel_ops_map);
            else
                stats_channels = stat_channels;
                lap_stats_opts = struct('operations', {stat_ops});
            end

            t0_stats = tic;
            stats = lap_stats(laps, stats_channels, lap_stats_opts);
            fprintf('  lap_stats: %.2fs\n', toc(t0_stats));
        catch ME
            fprintf('  [ERROR] lap_stats: %s\n', ME.message);
            clear session laps;
            continue;
        end

        % ---- Select top-N laps by lap time (flying only, or all if all_laps=true) ----
        if all_laps
            flying_laps = laps;
        else
            flying_mask = strcmp({laps.lap_type}, 'flying');
            flying_laps = laps(flying_mask);
        end
        if isempty(flying_laps)
            fprintf('  [WARN] No laps found — skipping traces.\n');
            traces = struct('lap_times', [], 'lap_numbers', [], 'n_traces', 0);
        else
            lap_times = [flying_laps.lap_time];
            [~, sort_idx] = sort(lap_times, 'ascend');
            n_keep   = min(max_traces, numel(flying_laps));
            top_idx  = sort_idx(1:n_keep);
            top_laps = flying_laps(top_idx);

            fprintf('  Top %d lap times: %s s\n', n_keep, ...
                strjoin(arrayfun(@(t) sprintf('%.2f', t), [top_laps.lap_time], ...
                                 'UniformOutput', false), '  '));

            % ---- Package traces ----
            traces = package_traces(top_laps, stat_channels);
            traces.lap_times   = [top_laps.lap_time];
            traces.lap_numbers = [top_laps.lap_number];
            traces.lap_types   = {top_laps.lap_type};
            traces.n_traces    = n_keep;
        end

        % ---- Store stats and traces under group key ----
        group_key = matlab.lang.makeValidName(grp.key);
        info_s    = build_info_from_group(grp, driver_map);

        cache.stats.(group_key)  = stats;
        cache.traces.(group_key) = traces;

        % ---- Persist lap summary ----
        if ~isempty(laps)
            lap_summary.lap_number = [laps.lap_number];
            lap_summary.lap_time   = [laps.lap_time];
            lap_summary.lap_type   = {laps.lap_type};
            lap_summary.t_start    = [laps.t_start];
            lap_summary.t_end      = [laps.t_end];
            cache.laps.(group_key) = lap_summary;
        end

        % ---- Add manifest entry for each file in the group ----
        for f = 1:numel(grp.files)
            cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, ...
                                  info_s, true, '', group_key);
        end

        % Clear raw data immediately
        clear session laps top_laps top_laps_dist;
        fprintf('  Done. RAM cleared.\n');
    end
end


% ======================================================================= %
%  BULK PROCESSING  (legacy — loads everything into memory)
% ======================================================================= %
function cache = process_bulk(cache, groups, channels_to_extract, verbose)

    n_groups = numel(groups);
    fprintf('[BULK MODE] Loading %d group(s) into memory...\n\n', n_groups);

    for g = 1:n_groups
        grp = groups(g);
        fprintf('[%d/%d] %s | %s | %s\n', ...
            g, n_groups, grp.team_acronym, grp.driver, grp.session);

        try
            session  = load_and_concat(grp.files, channels_to_extract, verbose);
            info_s   = build_info_from_group(grp);
            load_ok  = true;
            err_msg  = '';
        catch ME
            session  = struct();
            info_s   = build_info_from_group(grp);
            load_ok  = false;
            err_msg  = ME.message;
            fprintf('  [ERROR] %s\n', ME.message);
        end

        % Bulk: store raw channels for each file in the group
        for f = 1:numel(grp.files)
            % Legacy smp_cache_add signature: pass channels as arg 6
            cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, ...
                                  info_s, session, load_ok, err_msg);
        end

        % Note: in bulk mode we do NOT clear session — it stays in the Map
    end
end


% ======================================================================= %
%  LOAD AND CONCATENATE STINTS
%  OLD VERSION IS COMMENTED OUT 
% ======================================================================= %
% function session = load_and_concat(files, channels_to_extract, verbose)
% % Load one or more .ld files and concatenate their channels in time order.
% 
%     if numel(files) == 1
%         session = motec_ld_reader(files{1});
%         session = filter_channels(session, channels_to_extract);
%         return;
%     end
% 
%     % Multi-stint: load each, extract channels, concatenate
%     all_sessions = cell(numel(files), 1);
%     for f = 1:numel(files)
%         if verbose
%             [~, fname] = fileparts(files{f});
%             fprintf('    Loading stint %d: %s\n', f, fname);
%         end
%         s = motec_ld_reader(files{f});
%         s = filter_channels(s, channels_to_extract);
%         all_sessions{f} = s;
%     end
% 
%     session = concat_sessions(all_sessions);
% end

% function session = load_and_concat(files, channels_to_extract, verbose, unique_fp, show_report, label, csv_out_dir, load_all, driver_map, T_gated, l180_mode)
%     if nargin < 4,  unique_fp    = false;   end
%     if nargin < 5,  show_report  = false;   end
%     if nargin < 6,  label        = '';      end
%     if nargin < 7,  csv_out_dir  = '';      end
%     if nargin < 8,  load_all     = false;   end
%     if nargin < 9,  driver_map   = [];      end
%     if nargin < 10, T_gated      = table(); end
%     if nargin < 11, l180_mode = 'drop_duplicate'; end
%     % When load_all=true, pass {} to motec_ld_reader (reads every channel)
%     % and skip filter_channels so the full file is available downstream.
% 
%     files = dedupe_prefer_l180(files, verbose, l180_mode);
% 
%     if load_all
%         rd_channels = {};
%     else
%         rd_channels = channels_to_extract;
%     end
% 
%     if numel(files) == 1
%         session = motec_ld_reader(files{1}, rd_channels);
%         session.info = read_file_info(files{1}, driver_map);
%         % Augmentation (smp_custom_channels + smp_gated_channels) removed —
%         % VCH channels are now pre-baked into COM files by VCS Phase 6.
%         if ~load_all
%             session = filter_channels(session, channels_to_extract);
%         end
%         return;
%     end
% 
%     % Multi-stint — incremental concat to limit peak memory usage.
%     % Each file is loaded, processed, filtered, then immediately merged
%     % into the accumulated session before being cleared from memory.
%     concat_opts.uniqueFingerprint = unique_fp;
%     session   = [];
%     fp_report = struct('session_idx', {}, 'status', {}, 'reason', {}, ...
%                        'matched_idx', {}, 'tag',    {}, ...
%                        'fp_start',    {}, 'fp_end', {});
% 
%     for f = 1:numel(files)
%         if verbose
%             [~, fname] = fileparts(files{f});
%             fprintf('    Loading stint %d/%d: %s\n', f, numel(files), fname);
%         end
%         totalTic = tic;
%         t0 = tic;
%         s = motec_ld_reader(files{f}, rd_channels);
%         s.info = read_file_info(files{f}, driver_map);
%         fprintf('  motec_ID_reader: %.2fs\n', toc(t0));
%         % Augmentation (smp_custom_channels + smp_gated_channels) removed —
%         % VCH channels are now pre-baked into COM files by VCS Phase 6.
%         if ~load_all
%             t0 = tic;
%             s = filter_channels(s, channels_to_extract);
%             fprintf('  filter_channels: %.2fs\n', toc(t0));
%         end
% 
%         if isempty(session)
%             session = s;
%         else
%             [session, rep] = concat_sessions({session, s}, concat_opts);
%             if ~isempty(rep)
%                 fp_report = [fp_report, rep(:)'];  %#ok<AGROW>
%             end
%         end
%         clear s;
%         fprintf('  Total Time: %.2fs\n', toc(totalTic));
%     end
% 
%     if show_report && ~isempty(fp_report)
%         smp_show_concat_report(fp_report, label, files, {}, session);
%     end
%     n_dropped = sum(strcmp({fp_report.status}, 'dropped'));
%     if n_dropped > 0 && ~isempty(csv_out_dir)
%         if ~exist(csv_out_dir, 'dir'), mkdir(csv_out_dir); end
%         ts       = datestr(now, 'yyyymmdd_HHMMSS');
%         csv_path = fullfile(csv_out_dir, sprintf('concat_report_%s.csv', ts));
%         n_rep    = numel(fp_report);
%         file_col = repmat({''}, n_rep, 1);
%         for ri = 1:n_rep
%             if ri <= numel(files), file_col{ri} = files{ri}; end
%         end
%         T = table((1:n_rep)', file_col, ...
%                   {fp_report.status}', {fp_report.reason}', ...
%                   [fp_report.matched_idx]', {fp_report.tag}', ...
%                   'VariableNames', {'session_idx','file','status','reason','matched_idx','tag'});
%         writetable(T, csv_path);
%         fprintf('  [concat] CSV saved: %s\n', csv_path);
%     end
% end
function session = load_and_concat(files, channels_to_extract, verbose, unique_fp, show_report, label, csv_out_dir, load_all, driver_map, T_gated, l180_mode)
% LOAD_AND_CONCAT  Load one or more .ld files and concatenate their
%   channels in time order.
%
%   Augmentation (smp_custom_channels + smp_gated_channels) removed —
%   VCH channels are now pre-baked into COM files by VCS Phase 6. This
%   step only loads, filters, and concatenates already-augmented data;
%   it does not recompute derived channels.

    if nargin < 4,  unique_fp   = false;         end
    if nargin < 5,  show_report = false;         end
    if nargin < 6,  label       = '';            end
    if nargin < 7,  csv_out_dir = '';             end
    if nargin < 8,  load_all    = false;         end
    if nargin < 9,  driver_map  = [];            end
    if nargin < 10, T_gated     = table();       end
    if nargin < 11, l180_mode   = 'drop_duplicate'; end

    % When load_all=true, pass {} to motec_ld_reader (reads every channel)
    % and skip filter_channels so the full file is available downstream.
    files = dedupe_prefer_l180(files, verbose, l180_mode);

    if load_all
        rd_channels = {};
    else
        rd_channels = channels_to_extract;
    end

    % ---- Single file ----
    if numel(files) == 1
        session      = motec_ld_reader(files{1}, rd_channels);
        session.info = read_file_info(files{1}, driver_map);

        if ~load_all
            session = filter_channels(session, channels_to_extract);
        end
        return;
    end

    % ---- Multi-stint — incremental concat to limit peak memory usage ----
    % Each file is loaded, filtered, then immediately merged into the
    % accumulated session before being cleared from memory.
    concat_opts.uniqueFingerprint = unique_fp;
    session   = [];
    fp_report = struct('session_idx', {}, 'status', {}, 'reason', {}, ...
                        'matched_idx', {}, 'tag',    {}, ...
                        'fp_start',    {}, 'fp_end', {});

    for f = 1:numel(files)
        if verbose
            [~, fname] = fileparts(files{f});
            fprintf('    Loading stint %d/%d: %s\n', f, numel(files), fname);
        end

        totalTic = tic;
        t0 = tic;
        s      = motec_ld_reader(files{f}, rd_channels);
        s.info = read_file_info(files{f}, driver_map);
        fprintf('  motec_ID_reader: %.2fs\n', toc(t0));

        if ~load_all
            t0 = tic;
            s  = filter_channels(s, channels_to_extract);
            fprintf('  filter_channels: %.2fs\n', toc(t0));
        end

        if isempty(session)
            session = s;
        else
            [session, rep] = concat_sessions({session, s}, concat_opts);
            if ~isempty(rep)
                fp_report = [fp_report, rep(:)'];  %#ok<AGROW>
            end
        end

        clear s;
        fprintf('  Total Time: %.2fs\n', toc(totalTic));
    end

    if show_report && ~isempty(fp_report)
        smp_show_concat_report(fp_report, label, files, {}, session);
    end

    % ---- Optional CSV export of dropped/duplicate stints ----
    n_dropped = sum(strcmp({fp_report.status}, 'dropped'));
    if n_dropped > 0 && ~isempty(csv_out_dir)
        if ~exist(csv_out_dir, 'dir'), mkdir(csv_out_dir); end

        ts       = datestr(now, 'yyyymmdd_HHMMSS');
        csv_path = fullfile(csv_out_dir, sprintf('concat_report_%s.csv', ts));

        n_rep    = numel(fp_report);
        file_col = repmat({''}, n_rep, 1);
        for ri = 1:n_rep
            if ri <= numel(files), file_col{ri} = files{ri}; end
        end

        T = table((1:n_rep)', file_col, ...
                  {fp_report.status}', {fp_report.reason}', ...
                  [fp_report.matched_idx]', {fp_report.tag}', ...
                  'VariableNames', {'session_idx','file','status','reason','matched_idx','tag'});
        writetable(T, csv_path);
        fprintf('  [concat] CSV saved: %s\n', csv_path);
    end
end

% ======================================================================= %
function info = read_file_info(filepath, driver_map)
% Read file header metadata via motec_ld_info (quiet — no console output).
% If manufacturer is empty after header read, fall back to driver alias lookup.
% Returns an empty struct on failure so callers don't crash.
    if nargin < 2, driver_map = []; end
    try
        info = motec_ld_info(filepath, false);
    catch
        info = struct();
    end
    % Fallback: resolve manufacturer from driver alias when vehicle string
    % doesn't match any known pattern (returns '' from infer_manufacturer).
    if (~isfield(info, 'manufacturer') || isempty(info.manufacturer)) && ...
       isfield(info, 'driver') && ~isempty(info.driver)
        mfr = resolve_driver_meta(info.driver, driver_map);
        if ~isempty(mfr)
            info.manufacturer = mfr;
        end
    end
end

% function session = filter_channels(session, channels_to_extract)
% % Keep only requested channels in the session struct.
%     if isempty(channels_to_extract), return; end
% 
%     all_fields = fieldnames(session);
%     for i = 1:numel(all_fields)
%         fn = all_fields{i};
%         % Keep if it matches any requested channel (case-insensitive)
%         keep = any(strcmpi(fn, channels_to_extract)) || ...
%                any(cellfun(@(c) strcmpi(regexprep(c,'[^a-zA-Z0-9_]','_'), fn), channels_to_extract));
%         if ~keep
%             session = rmfield(session, fn);
%         end
%     end
% end
function session = filter_channels(session, channels_to_extract)
% Keep only requested channels in the session struct.
% Uses vectorised ismember instead of per-field cellfun loops.

    if isempty(channels_to_extract), return; end

    all_fields = fieldnames(session);

    % Sanitise ALL requested names once upfront
    requested_san = cellfun(@(c) regexprep(c, '[^a-zA-Z0-9_]', '_'), ...
                            channels_to_extract, 'UniformOutput', false);

    % Build lowercase versions of both lists for case-insensitive match
    fields_lower    = lower(all_fields);
    requested_lower = lower([channels_to_extract(:); requested_san(:)]);

    % Single vectorised lookup — much faster than nested strcmpi loop
    keep_mask = ismember(fields_lower, requested_lower);

    % Drop all non-kept fields in ONE rmfield call (not one per field)
    drop = all_fields(~keep_mask);
    if ~isempty(drop)
        session = rmfield(session, drop);
    end
end

% concat_sessions is defined in concat_sessions.m (parseEventData/).
% Extracted to a top-level function file so it can be unit-tested directly.


% ======================================================================= %
%  TRACES PACKAGING
% ======================================================================= %
function traces = package_traces(top_laps, channels_to_extract)
% Package top-N laps into a traces struct for cache storage.
%
% Each lap keeps its own distance axis so lap-to-lap distance differences
% are preserved. Structure:
%
%   traces.(channel_name)(k).data   - resampled data for lap k
%   traces.(channel_name)(k).dist   - distance axis for lap k (metres)
%   traces.lap_times                - [1 x n] lap times in seconds
%   traces.lap_numbers              - [1 x n] lap numbers
%   traces.n_traces                 - number of stored laps
%
% Resampling uses smp_resample at the natural resolution of each lap's
% distance channel — no fixed point count.

    traces = struct();

    if isempty(top_laps)
        traces.n_traces = 0;
        return;
    end

    n_traces  = numel(top_laps);
    ch_fields = fieldnames(top_laps(1).channels);

    for c = 1:numel(ch_fields)
        fn = ch_fields{c};

        % Always keep MyLaps beacon channel (needed for speed trap windowing)
        is_mylaps = ~isempty(regexpi(fn, 'mylaps', 'once'));

        % Only store requested channels (or always-keep channels)
        is_requested = is_mylaps || ...
                       isempty(channels_to_extract) || ...
                       any(strcmpi(fn, channels_to_extract)) || ...
                       any(cellfun(@(ch) strcmpi(regexprep(ch,'[^a-zA-Z0-9_]','_'), fn), ...
                                   channels_to_extract));
        if ~is_requested, continue; end

        for k = 1:n_traces
            lap_ch = top_laps(k).channels.(fn);

            % .dist and .data are added by enrich_with_distance in lap_slicer
            if ~isfield(lap_ch, 'dist') || ~isfield(lap_ch, 'data')
                traces.(fn)(k).data = [];
                traces.(fn)(k).dist = [];
                continue;
            end

            d_raw   = lap_ch.dist(:);
            v_raw   = lap_ch.data(:);

            % Resample onto uniform distance grid at natural resolution
            [v_res, d_res] = smp_resample(v_raw, d_raw);

%             traces.(fn)(k).data = v_res;
%             traces.(fn)(k).dist = d_res;
            traces.(fn)(k).data = v_raw;
            traces.(fn)(k).dist = d_raw;
        end
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %
function dist = estimate_lap_distance(lap, dist_ch)
% Estimate lap distance from a sliced lap struct.
    ch_names = fieldnames(lap.channels);
    DIST_CANDIDATES = {dist_ch, 'Distance', 'Odometer', 'Dist', 'Odo'};
    for i = 1:numel(DIST_CANDIDATES)
        for j = 1:numel(ch_names)
            if strcmpi(ch_names{j}, DIST_CANDIDATES{i})
                d = lap.channels.(ch_names{j}).data;
                d = d - d(1);
                dist = d(end);
                return;
            end
        end
    end
    % Fallback: integrate speed
    for j = 1:numel(ch_names)
        if contains(lower(ch_names{j}), 'speed')
            s  = lap.channels.(ch_names{j}).data;
            t  = lap.channels.(ch_names{j}).time;
            dist = trapz(t, max(s,0) / 3.6);
            return;
        end
    end
    dist = 5000;   % last resort default: 5km
end


function info_s = build_info_from_group(grp, driver_map)
    info_s.driver  = grp.driver;
    info_s.session = grp.session;

    % Venue — from binary (resolved through alias in smp_append_stints)
    info_s.venue = safe_grp(grp, 'venue', '');

    % Date / time / run — binary header or filename-derived
    info_s.log_date = safe_grp(grp, 'log_date', '');
    info_s.time     = safe_grp(grp, 'time_str', '');
    info_s.run      = safe_grp(grp, 'run_number', '');

    % Year from log_date (YYYY-MM-DD)
    ld = info_s.log_date;
    if numel(ld) >= 4
        info_s.year = ld(1:4);
    else
        info_s.year = '';
    end

    % date field formatted for smp_cache_add (DD/MM/YYYY -> keep raw)
    info_s.date = info_s.log_date;

    % Car number — from driver_map NUM column (race number).
    % Fallback: raw binary device-code digits (same ECU serial for all cars).
    [mfr, team, car_num] = resolve_driver_meta(grp.driver, driver_map);
    if ~isempty(car_num)
        info_s.car_number = car_num;
    else
        info_s.car_number = safe_grp(grp, 'car', '');
        if ~isempty(info_s.car_number)
            fprintf('  [WARN] car_number fallback to binary device-code for driver "%s"\n', grp.driver);
        end
    end

    info_s.manufacturer = mfr;

    % Team: alias TM_TLA is source of truth; fallback to folder acronym.
    if ~isempty(team)
        info_s.team_name = team;
    else
        info_s.team_name = grp.team_acronym;
    end
end


% ======================================================================= %
function v = safe_grp(grp, field, default)
    if isfield(grp, field) && ~isempty(grp.(field))
        v = grp.(field);
    else
        v = default;
    end
end


% ======================================================================= %
function [mfr, team, car_num] = resolve_driver_meta(driver_name, driver_map)
% Resolve manufacturer (MAN), team (TM_TLA), and car number (NUM) for a driver.
%
% Lookup order:
%   1. Direct struct key match
%   2. Strip-normalised key match
%   3. Alias search

    mfr     = '';
    team    = '';
    car_num = '';

    if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name)
        return;
    end

    name_strip = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]', '');
    keys = fieldnames(driver_map);
    entry_found = [];

    % 1. Direct key lookup
    if isfield(driver_map, driver_name)
        entry_found = driver_map.(driver_name);
    end

    % 2. Strip-normalised key match
    if isempty(entry_found)
        for k = 1:numel(keys)
            if strcmp(name_strip, regexprep(lower(keys{k}), '[^a-z0-9]', ''))
                entry_found = driver_map.(keys{k});
                break;
            end
        end
    end

    % 3. Alias search
    if isempty(entry_found)
        for k = 1:numel(keys)
            e = driver_map.(keys{k});
            if ~isfield(e, 'aliases'), continue; end
            for a = 1:numel(e.aliases)
                if strcmp(name_strip, regexprep(e.aliases{a}, '[^a-z0-9]', ''))
                    entry_found = e;
                    break;
                end
            end
            if ~isempty(entry_found), break; end
        end
    end

    % No match — pause so user can fix the alias file
    if isempty(entry_found)
        fprintf('\n========================================================\n');
        fprintf('  DRIVER NOT FOUND IN ALIAS FILE: "%s"\n', driver_name);
        fprintf('  Add this driver to driverAlias.xlsx with MAN and TM_TLA\n');
        fprintf('  then delete the cache and recompile.\n');
        fprintf('  Type "dbcont" to skip this driver and continue.\n');
        fprintf('========================================================\n');
        keyboard;
        return;
    end

    % Extract manufacturer (prefer MAN full name over MAN_TLA)
    if isfield(entry_found, 'manufacturer') && ~isempty(entry_found.manufacturer)
        mfr = entry_found.manufacturer;
    end

    % Extract team TLA
    if isfield(entry_found, 'team_tla') && ~isempty(entry_found.team_tla)
        team = entry_found.team_tla;
    end

    % Extract car race number from NUM column
    if isfield(entry_found, 'num') && ~isempty(entry_found.num)
        car_num = entry_found.num;
    end
end


function cache = add_failed_entries(cache, grp, err_msg)
    info_s = build_info_from_group(grp, []);
    for f = 1:numel(grp.files)
        cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, ...
                              info_s, false, err_msg);
    end
end


function scan_filtered = filter_scan(scan_all, team_filter)
    scan_filtered = struct('index',{},'acronym',{},'folder',{},'files',{});
    n = 0;
    for t = 1:numel(scan_all)
        idx_str = sprintf('%02d', scan_all(t).index);
        acro    = scan_all(t).acronym;
        for f = 1:numel(team_filter)
            key = upper(strtrim(team_filter{f}));
            if strcmp(key, idx_str) || strcmp(key, acro)
                n = n + 1;
                scan_filtered(n) = scan_all(t);
                break;
            end
        end
    end
end


function val = get_opt(s, f, default)
    if isfield(s, f) && ~isempty(s.(f)), val = s.(f);
    else,                                 val = default; end
end

% function files_out = dedupe_prefer_l180(files, verbose)
% % DEDUPE_PREFER_L180  When two files in a group are the same stint logged
% % by different loggers (one plain, one L180-tagged), keep only the L180
% % one. Matching is done on filename with any 'L180' token stripped out,
% % so e.g. "FEE_2026_Q20_combined.ld" and "FEE_2026_Q20_combined_L180.ld"
% % are recognised as the same stint.
% if nargin < 2, verbose = false; end
% n = numel(files);
% if n < 2, files_out = files; return; end
% 
% keys    = cell(n, 1);
% is_l180 = false(n, 1);
% for i = 1:n
%     [~, fname] = fileparts(files{i});
%     is_l180(i) = ~isempty(regexpi(fname, 'L180', 'once'));
%     keys{i}    = upper(regexprep(fname, '_?L180_?', '', 'ignorecase'));
% end
% 
% keep = true(n, 1);
% for i = 1:n
%     if ~keep(i), continue; end
%     for j = i+1:n
%         if ~keep(j), continue; end
%         if strcmp(keys{i}, keys{j})
%             if is_l180(i) && ~is_l180(j)
%                 keep(j) = false;
%                 if verbose
%                     fprintf('  [DEDUPE] Dropping non-L180 duplicate: %s\n', files{j});
%                 end
%             elseif is_l180(j) && ~is_l180(i)
%                 keep(i) = false;
%                 if verbose
%                     fprintf('  [DEDUPE] Dropping non-L180 duplicate: %s\n', files{i});
%                 end
%             end
%             % if neither or both are L180, leave both — not a match
%             % we're confident enough to auto-resolve.
%         end
%     end
% end
% files_out = files(keep);
% end
function files_out = dedupe_prefer_l180(files, verbose, mode)
% DEDUPE_PREFER_L180  When two files in a group are the same stint logged
% by different loggers (one plain, one L180-tagged):
%
%   mode = 'drop_duplicate' (default) — keep only the L180 copy, drop the plain one.
%   mode = 'keep_separate'            — no-op here; splitting into distinct,
%                                       independently-processed groups is
%                                       handled upstream in process_stream
%                                       via split_l180_groups.
if nargin < 2, verbose = false;            end
if nargin < 3, mode    = 'drop_duplicate';   end

if strcmp(mode, 'keep_separate')
    files_out = files;
    return;
end

n = numel(files);
if n < 2, files_out = files; return; end

keys    = cell(n, 1);
is_l180 = false(n, 1);
for i = 1:n
    [~, fname] = fileparts(files{i});
    is_l180(i) = ~isempty(regexpi(fname, 'L180', 'once'));
    keys{i}    = upper(regexprep(fname, '_?L180_?', '', 'ignorecase'));
end

keep = true(n, 1);
for i = 1:n
    if ~keep(i), continue; end
    for j = i+1:n
        if ~keep(j), continue; end
        if strcmp(keys{i}, keys{j})
            if is_l180(i) && ~is_l180(j)
                keep(j) = false;
                if verbose, fprintf('  [DEDUPE] Dropping non-L180 duplicate: %s\n', files{j}); end
            elseif is_l180(j) && ~is_l180(i)
                keep(i) = false;
                if verbose, fprintf('  [DEDUPE] Dropping non-L180 duplicate: %s\n', files{i}); end
            end
        end
    end
end
files_out = files(keep);
end

function groups_out = split_l180_groups(groups, l180_mode, verbose)
% In 'keep_separate' mode, any group whose .files contains a plain/L180
% pair (same stem, one tagged L180) is split into two independent groups,
% each processed as its own session with its own lap stats — no combining,
% no shared timebase, no shared GroupKey.
if ~strcmp(l180_mode, 'keep_separate')
    groups_out = groups;
    return;
end

groups_out = groups([]);   % empty struct array with same fields
for g = 1:numel(groups)
    grp   = groups(g);
    files = grp.files;
    n     = numel(files);

    if n < 2
        groups_out(end+1) = grp; %#ok<AGROW>
        continue;
    end

    keys    = cell(n, 1);
    is_l180 = false(n, 1);
    for i = 1:n
        [~, fname] = fileparts(files{i});
        is_l180(i) = ~isempty(regexpi(fname, 'L180', 'once'));
        keys{i}    = upper(regexprep(fname, '_?L180_?', '', 'ignorecase'));
    end

    used = false(n, 1);
    for i = 1:n
        if used(i), continue; end
        paired_j = 0;
        for j = i+1:n
            if used(j), continue; end
            if strcmp(keys{i}, keys{j}) && (is_l180(i) ~= is_l180(j))
                paired_j = j;
                break;
            end
        end

        if paired_j > 0
            sub1 = grp; sub1.files = files(i);
            sub2 = grp; sub2.files = files(paired_j);

            if is_l180(i), tag1 = 'L180'; tag2 = 'Plain';
            else,          tag1 = 'Plain'; tag2 = 'L180';
            end

            % sub1.session = [grp.session '_' tag1];
            % sub2.session = [grp.session '_' tag2];
            if isfield(grp, 'key')
                sub1.key = [grp.key '_' tag1];
                sub2.key = [grp.key '_' tag2];
            end
            sub1.n_files = 1;
            sub2.n_files = 1;

            groups_out(end+1) = sub1; %#ok<AGROW>
            groups_out(end+1) = sub2; %#ok<AGROW>
            used(i) = true; used(paired_j) = true;

            if verbose
                fprintf('  [SPLIT] %s -> %s (%s) + %s (%s)\n', ...
                    grp.session, sub1.session, tag1, sub2.session, tag2);
            end
        else
            sub = grp; sub.files = files(i);
            sub.n_files = 1;
            groups_out(end+1) = sub; %#ok<AGROW>
            used(i) = true;
        end
    end
end
end