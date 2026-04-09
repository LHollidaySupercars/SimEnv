% function cache = smp_compile_event(top_level_dir, team_filter, ...
%                                     channels_to_extract, season, ...
%                                     driver_map, alias, opts)
% % SMP_COMPILE_EVENT  Scan, load, process and cache .ld files for an event.
% %
% % This is the new top-level compiler that replaces the old bulk-load approach
% % in smp_load_teams. It supports two modes:
% %
% %   'stream'  (default) — process one .ld file group at a time.
% %             Raw channel data is cleared after stats are extracted.
% %             Peak RAM = approximately one .ld file at a time.
% %             Recommended for all machines with < 32 GB RAM.
% %
% %   'bulk'    (legacy)  — load all files then process.
% %             Same behaviour as the original smp_load_teams.
% %             Requires a password confirmation before proceeding.
% %             Only use on high-RAM workstations.
% %
% % Usage:
% %   cache = smp_compile_event(top_level_dir, team_filter, ...
% %               channels_to_extract, season, driver_map, alias)
% %   cache = smp_compile_event(..., opts)
% %
% % Inputs:
% %   top_level_dir       - path to team data folder
% %   team_filter         - cell array of team acronyms, e.g. {'T8R','WAU'}
% %                         pass {} to process all teams
% %   channels_to_extract - cell array from smp_channel_config_load()
% %   season              - struct from smp_season_load()
% %   driver_map          - struct from smp_driver_alias_load()
% %   alias               - struct from smp_alias_load()
% %   opts                - optional struct:
% %     .mode             'stream' (default) or 'bulk'
% %     .track            track acronym for lap time limits e.g. 'SMP'
% %                       (required to use season lap time limits)
% %     .max_traces       number of top-N laps to keep as traces (default: 5)
% %     .dist_n_points    distance interpolation grid points (default: 1000)
% %     .dist_channel     distance channel name (default: 'Odometer')
% %     .verbose          (default: true)
% %     .date_from        datetime/datenum — only load files on or after this date
% %                       e.g. datetime(2026,3,5)  (default: [] = all files)
% %
% % Output:
% %   cache   - compiled cache struct (stats + traces in stream mode,
% %             or raw channels in bulk mode). Also saved to disk.
% 
%     % ------------------------------------------------------------------
%     %  Defaults
%     % ------------------------------------------------------------------
%     if nargin < 7 || isempty(opts), opts = struct(); end
% 
%     mode          = get_opt(opts, 'mode',          'stream');
%     track         = get_opt(opts, 'track',         '');
%     max_traces    = get_opt(opts, 'max_traces',     5);
%     dist_npts     = get_opt(opts, 'dist_n_points',  1000);
%     dist_ch       = get_opt(opts, 'dist_channel',   'Odometer');
%     verbose       = get_opt(opts, 'verbose',        true);
%     date_from     = get_opt(opts, 'date_from',      []);
%     saveCache     = get_opt(opts, 'saveCache',      true);
% 
%     % ------------------------------------------------------------------
%     %  Lap time limits from season overview
%     % ------------------------------------------------------------------
%     if ~isempty(track) && ~isempty(season)
%         [min_lt, max_lt] = smp_season_get(season, track);
%         fprintf('Lap time limits for %s: %.1fs – %.1fs\n', track, min_lt, max_lt);
%     else
%         min_lt = 10;
%         max_lt = 600;
%         if isempty(track)
%             fprintf('[WARN] No track specified — using default lap time limits (10s / 600s).\n');
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  1. Scan folders
%     % ------------------------------------------------------------------
%     fprintf('\n=== SMP Compile Event ===\n');
%     fprintf('Mode: %s\n', upper(mode));
%     fprintf('Scanning: %s\n\n', top_level_dir);
% 
%     scan_all = smp_scan_folders(top_level_dir);
%     if isempty(scan_all)
%         error('smp_compile_event: No valid team folders found.');
%     end
% 
%     if isempty(team_filter)
%         scan_load = scan_all;
%     else
%         scan_load = filter_scan(scan_all, team_filter);
%     end
% 
%     if isempty(scan_load)
%         error('smp_compile_event: No teams matched filter: %s', ...
%             strjoin(team_filter, ', '));
%     end
% 
%     % ------------------------------------------------------------------
%     %  1b. Date filter — keep only files on or after date_from
%     % ------------------------------------------------------------------
%     if ~isempty(date_from)
%         date_from_dn = datenum(date_from);
%         for i = 1:numel(scan_load)
%             files = scan_load(i).files;
%             keep  = false(1, numel(files));
%             for j = 1:numel(files)
%                 d = dir(files{j});
%                 keep(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
%             end
%             scan_load(i).files = files(keep);
%         end
%         % Remove teams with no files remaining
%         scan_load = scan_load(arrayfun(@(t) ~isempty(t.files), scan_load));
%         if verbose
%             n_files = sum(arrayfun(@(t) numel(t.files), scan_load));
%             fprintf('date_from filter (%s): %d file(s) retained.\n\n', ...
%                 datestr(date_from_dn, 'dd-mmm-yyyy'), n_files);
%         end
%         if isempty(scan_load)
%             fprintf('No files found on or after %s — nothing to compile.\n\n', ...
%                 datestr(date_from_dn, 'dd-mmm-yyyy'));
%             cache = smp_cache_load(top_level_dir);
%             if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
%             if ~isfield(cache, 'traces'), cache.traces = struct(); end
%             return;
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  2. Load or initialise cache
%     % ------------------------------------------------------------------
%     cache = smp_cache_load(top_level_dir);
% 
%     % Backwards compatibility — old caches may lack stats/traces fields
%     if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
%     if ~isfield(cache, 'traces'), cache.traces = struct(); end
% 
%     % Old manifest won't have GroupKey column — add it as empty strings
%     if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
%         cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
%     end
% 
%     % If cached mode doesn't match requested mode, warn but don't force switch
%     if isfield(cache, 'mode') && ~strcmp(cache.mode, mode)
%         fprintf('[WARN] Existing cache was built in ''%s'' mode, but ''%s'' was requested.\n', ...
%             cache.mode, mode);
%         fprintf('       Cache will be used as-is. To switch modes, delete the cache file.\n\n');
%         mode = cache.mode;   % honour existing cache mode
%     elseif ~isfield(cache, 'mode')
%         cache.mode = mode;
%     end
% 
%     % ------------------------------------------------------------------
%     %  3. Diff against disk — find new/changed files
%     % ------------------------------------------------------------------
%     [to_load, cache] = smp_cache_diff(cache, scan_load);
% 
%     if isempty(to_load)
%         fprintf('All files up to date — nothing new to compile.\n\n');
%         return;
%     end
% 
%     fprintf('\n%d new/changed file(s) to compile...\n\n', numel(to_load));
% 
%     % ------------------------------------------------------------------
%     %  4. Group files by driver/session/car (handles multi-stint)
%     % ------------------------------------------------------------------
%     groups = smp_append_stints(to_load, driver_map, alias);
% 
%     % ------------------------------------------------------------------
%     %  5. Process based on mode
%     % ------------------------------------------------------------------
%     if strcmp(mode, 'stream')
%         cache = process_stream(cache, groups, channels_to_extract, ...
%                                min_lt, max_lt, max_traces, dist_npts, ...
%                                dist_ch, driver_map, verbose);
%     else
%         cache = process_bulk(cache, groups, channels_to_extract, verbose);
%     end
% 
%     % ------------------------------------------------------------------
%     %  6. Save cache to disk
%     % ------------------------------------------------------------------
%     fprintf('\nSaving cache...\n');
%     if saveCache 
%         tic;
%         smp_cache_save(top_level_dir, cache);
%         t_save = toc;
%         fprintf('Cache saved in %.1fs.\n\n', t_save);
%     end
% end
% 
% 
% % ======================================================================= %
% %  STREAM PROCESSING
% % ======================================================================= %
% function cache = process_stream(cache, groups, channels_to_extract, ...
%                                  min_lt, max_lt, max_traces, dist_npts, ...
%                                  dist_ch, driver_map, verbose)
% 
%     lap_opts.min_lap_time = min_lt;
%     lap_opts.max_lap_time = max_lt;
%     lap_opts.verbose      = false;
% 
%     dist_opts.distance_channel = dist_ch;
%     dist_opts.resolution       = [];      % will be set per group
%     dist_opts.common_grid      = true;
%     dist_opts.verbose          = false;
% 
%     n_groups = numel(groups);
% 
%     for g = 1:n_groups
%         grp = groups(g);
%         fprintf('[%d/%d] %s | %s | %s | %d file(s)\n', ...
%             g, n_groups, grp.team_acronym, grp.driver, grp.session, grp.n_files);
% 
%         % ---- Load and concatenate stints ----
%         try
%             session = load_and_concat(grp.files, channels_to_extract, verbose);
%         catch ME
%             fprintf('  [ERROR] Load failed: %s\n', ME.message);
%             cache = add_failed_entries(cache, grp, ME.message);
%             continue;
%         end
% 
%         if isempty(session)
%             fprintf('  [WARN] No channel data returned — skipping.\n');
%             continue;
%         end
% 
%         % ---- Lap slice ----
%         try
%             laps = lap_slicer(session, lap_opts);
%         catch ME
%             fprintf('  [ERROR] lap_slicer: %s\n', ME.message);
%             cache = add_failed_entries(cache, grp, ME.message);
%             clear session;
%             continue;
%         end
% 
%         if isempty(laps)
%             fprintf('  [WARN] No valid laps found — skipping.\n');
%             cache = add_failed_entries(cache, grp, 'No valid laps');
%             clear session;
%             continue;
%         end
% 
%         fprintf('  %d valid laps\n', numel(laps));
% 
%         % ---- Compute per-lap stats ----
%         try
%             stat_channels = channels_to_extract;
% %             stats = lap_stats(laps, stat_channels, struct('operations', ...
% %                 {{'min','max','mean','median','std','var','range'}}));
%             stats = lap_stats(laps, stat_channels, ...
%             struct('operations', {{'max','min','mean','median','std','var','range',...
%             'max non zero','min non zero','mean non zero','median non zero','std non zero','sample_rate'}}));
%         catch ME
%             fprintf('  [ERROR] lap_stats: %s\n', ME.message);
%             clear session laps;
%             continue;
%         end
% 
%         % ---- Select top-N laps by lap time ----
%         lap_times = [laps.lap_time];
%         [~, sort_idx] = sort(lap_times, 'ascend');
%         n_keep = min(max_traces, numel(laps));
%         top_idx = sort_idx(1:n_keep);
%         top_laps = laps(top_idx);
% 
%         fprintf('  Top %d lap times: %s s\n', n_keep, ...
%             strjoin(arrayfun(@(t) sprintf('%.2f', t), [top_laps.lap_time], ...
%                              'UniformOutput', false), '  '));
% 
%         % ---- Package traces (lap_slicer already enriched .dist on all channels) ----
%         traces = package_traces(top_laps, channels_to_extract);
%         traces.lap_times   = [top_laps.lap_time];
%         traces.lap_numbers = [top_laps.lap_number];
%         traces.n_traces    = n_keep;
% 
%         % ---- Store stats and traces under group key ----
%         group_key = matlab.lang.makeValidName(grp.key);
%         info_s    = build_info_from_group(grp, driver_map);
% 
%         cache.stats.(group_key)  = stats;
%         cache.traces.(group_key) = traces;
% 
%         % ---- Add manifest entry for each file in the group ----
%         for f = 1:numel(grp.files)
%             cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, ...
%                                   info_s, true, '', group_key);
%         end
% 
%         % Clear raw data immediately
%         clear session laps top_laps top_laps_dist;
%         fprintf('  Done. RAM cleared.\n');
%     end
% end
% 
% 
% % ======================================================================= %
% %  BULK PROCESSING  (legacy — loads everything into memory)
% % ======================================================================= %
% function cache = process_bulk(cache, groups, channels_to_extract, verbose)
% 
%     n_groups = numel(groups);
%     fprintf('[BULK MODE] Loading %d group(s) into memory...\n\n', n_groups);
% 
%     for g = 1:n_groups
%         grp = groups(g);
%         fprintf('[%d/%d] %s | %s | %s\n', ...
%             g, n_groups, grp.team_acronym, grp.driver, grp.session);
% 
%         try
%             session  = load_and_concat(grp.files, channels_to_extract, verbose);
%             info_s   = build_info_from_group(grp);
%             load_ok  = true;
%             err_msg  = '';
%         catch ME
%             session  = struct();
%             info_s   = build_info_from_group(grp);
%             load_ok  = false;
%             err_msg  = ME.message;
%             fprintf('  [ERROR] %s\n', ME.message);
%         end
% 
%         % Bulk: store raw channels for each file in the group
%         for f = 1:numel(grp.files)
%             % Legacy smp_cache_add signature: pass channels as arg 6
%             cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, ...
%                                   info_s, session, load_ok, err_msg);
%         end
% 
%         % Note: in bulk mode we do NOT clear session — it stays in the Map
%     end
% end
% 
% 
% % ======================================================================= %
% %  LOAD AND CONCATENATE STINTS
% %  OLD VERSION IS COMMENTED OUT 
% % ======================================================================= %
% % function session = load_and_concat(files, channels_to_extract, verbose)
% % % Load one or more .ld files and concatenate their channels in time order.
% % 
% %     if numel(files) == 1
% %         session = motec_ld_reader(files{1});
% %         session = filter_channels(session, channels_to_extract);
% %         return;
% %     end
% % 
% %     % Multi-stint: load each, extract channels, concatenate
% %     all_sessions = cell(numel(files), 1);
% %     for f = 1:numel(files)
% %         if verbose
% %             [~, fname] = fileparts(files{f});
% %             fprintf('    Loading stint %d: %s\n', f, fname);
% %         end
% %         s = motec_ld_reader(files{f});
% %         s = filter_channels(s, channels_to_extract);
% %         all_sessions{f} = s;
% %     end
% % 
% %     session = concat_sessions(all_sessions);
% % end
% 
% function session = load_and_concat(files, channels_to_extract, verbose)
% 
%     if numel(files) == 1
%         session = motec_ld_reader(files{1});
%         session = smp_custom_channels(session);        % <-- ADD HERE
%         session = filter_channels(session, channels_to_extract);
%         return;
%     end
% 
%     % Multi-stint
%     all_sessions = cell(numel(files), 1);
%     for f = 1:numel(files)
%         if verbose
%             [~, fname] = fileparts(files{f});
%             fprintf('    Loading stint %d: %s\n', f, fname);
%         end
%         totalTic = tic;
%         t0 = tic;
%         s = motec_ld_reader(files{f});
%         fprintf('  motec_ID_reader: %.2fs\n', toc(t0));
%         t0 = tic;
%         s = smp_custom_channels(s);          
%         fprintf('  smp_custom_channels: %.2fs\n', toc(t0));
%         t0 = tic;
%         s = filter_channels(s, channels_to_extract);
%         fprintf('  filter_channels: %.2fs\n', toc(t0));
%         all_sessions{f} = s;
%         fprintf('  Total Time: %.2fs\n', toc(totalTic));
% %         keyboard
%     end
% 
%     session = concat_sessions(all_sessions);
% end
% 
% % function session = filter_channels(session, channels_to_extract)
% % % Keep only requested channels in the session struct.
% %     if isempty(channels_to_extract), return; end
% % 
% %     all_fields = fieldnames(session);
% %     for i = 1:numel(all_fields)
% %         fn = all_fields{i};
% %         % Keep if it matches any requested channel (case-insensitive)
% %         keep = any(strcmpi(fn, channels_to_extract)) || ...
% %                any(cellfun(@(c) strcmpi(regexprep(c,'[^a-zA-Z0-9_]','_'), fn), channels_to_extract));
% %         if ~keep
% %             session = rmfield(session, fn);
% %         end
% %     end
% % end
% function session = filter_channels(session, channels_to_extract)
% % Keep only requested channels in the session struct.
% % Uses vectorised ismember instead of per-field cellfun loops.
% 
%     if isempty(channels_to_extract), return; end
% 
%     all_fields = fieldnames(session);
% 
%     % Sanitise ALL requested names once upfront
%     requested_san = cellfun(@(c) regexprep(c, '[^a-zA-Z0-9_]', '_'), ...
%                             channels_to_extract, 'UniformOutput', false);
% 
%     % Build lowercase versions of both lists for case-insensitive match
%     fields_lower    = lower(all_fields);
%     requested_lower = lower([channels_to_extract(:); requested_san(:)]);
% 
%     % Single vectorised lookup — much faster than nested strcmpi loop
%     keep_mask = ismember(fields_lower, requested_lower);
% 
%     % Drop all non-kept fields in ONE rmfield call (not one per field)
%     drop = all_fields(~keep_mask);
%     if ~isempty(drop)
%         session = rmfield(session, drop);
%     end
% end
% 
% function merged = concat_sessions(sessions)
% % Concatenate a cell array of session structs along their time axes.
% % The time axis of each subsequent stint is offset to follow the previous.
% 
%     merged = sessions{1};
%     ch_fields = fieldnames(merged);
% 
%     for s = 2:numel(sessions)
%         s2 = sessions{s};
% 
%         % Find time offset: end of last session
%         % Use first available channel time axis
%         t_offset = 0;
%         for c = 1:numel(ch_fields)
%             fn = ch_fields{c};
%             if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
%                ~isempty(merged.(fn).time)
%                 t_offset = merged.(fn).time(end);
%                 break;
%             end
%         end
% 
%         % Add a small gap (1 sample period) to avoid exact duplicate timestamps
%         % Use median sample period of Lap_Number channel as reference
%         if isfield(merged, 'Lap_Number') && numel(merged.Lap_Number.time) > 1
%             dt_ref = median(diff(merged.Lap_Number.time));
%             t_offset = t_offset + dt_ref;
%         else
%             t_offset = t_offset + 0.02;   % 50Hz default gap
%         end
% 
%         % Concatenate each channel
%         for c = 1:numel(ch_fields)
%             fn = ch_fields{c};
%             if ~isfield(s2, fn), continue; end
% 
%             merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
%             merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
%         end
%     end
% end
% 
% 
% % ======================================================================= %
% %  TRACES PACKAGING
% % ======================================================================= %
% function traces = package_traces(top_laps, channels_to_extract)
% % Package top-N laps into a traces struct for cache storage.
% %
% % Each lap keeps its own distance axis so lap-to-lap distance differences
% % are preserved. Structure:
% %
% %   traces.(channel_name)(k).data   - resampled data for lap k
% %   traces.(channel_name)(k).dist   - distance axis for lap k (metres)
% %   traces.lap_times                - [1 x n] lap times in seconds
% %   traces.lap_numbers              - [1 x n] lap numbers
% %   traces.n_traces                 - number of stored laps
% %
% % Resampling uses smp_resample at the natural resolution of each lap's
% % distance channel — no fixed point count.
% 
%     traces = struct();
% 
%     if isempty(top_laps)
%         traces.n_traces = 0;
%         return;
%     end
% 
%     n_traces  = numel(top_laps);
%     ch_fields = fieldnames(top_laps(1).channels);
% 
%     for c = 1:numel(ch_fields)
%         fn = ch_fields{c};
% 
%         % Only store requested channels
%         is_requested = isempty(channels_to_extract) || ...
%                        any(strcmpi(fn, channels_to_extract)) || ...
%                        any(cellfun(@(ch) strcmpi(regexprep(ch,'[^a-zA-Z0-9_]','_'), fn), ...
%                                    channels_to_extract));
%         if ~is_requested, continue; end
% 
%         for k = 1:n_traces
%             lap_ch = top_laps(k).channels.(fn);
% 
%             % .dist and .data are added by enrich_with_distance in lap_slicer
%             if ~isfield(lap_ch, 'dist') || ~isfield(lap_ch, 'data')
%                 traces.(fn)(k).data = [];
%                 traces.(fn)(k).dist = [];
%                 continue;
%             end
% 
%             d_raw   = lap_ch.dist(:);
%             v_raw   = lap_ch.data(:);
% 
%             % Resample onto uniform distance grid at natural resolution
%             [v_res, d_res] = smp_resample(v_raw, d_raw);
% 
% %             traces.(fn)(k).data = v_res;
% %             traces.(fn)(k).dist = d_res;
%             traces.(fn)(k).data = v_raw;
%             traces.(fn)(k).dist = d_raw;
%         end
%     end
% end
% 
% 
% % ======================================================================= %
% %  HELPERS
% % ======================================================================= %
% function dist = estimate_lap_distance(lap, dist_ch)
% % Estimate lap distance from a sliced lap struct.
%     ch_names = fieldnames(lap.channels);
%     DIST_CANDIDATES = {dist_ch, 'Distance', 'Odometer', 'Dist', 'Odo'};
%     for i = 1:numel(DIST_CANDIDATES)
%         for j = 1:numel(ch_names)
%             if strcmpi(ch_names{j}, DIST_CANDIDATES{i})
%                 d = lap.channels.(ch_names{j}).data;
%                 d = d - d(1);
%                 dist = d(end);
%                 return;
%             end
%         end
%     end
%     % Fallback: integrate speed
%     for j = 1:numel(ch_names)
%         if contains(lower(ch_names{j}), 'speed')
%             s  = lap.channels.(ch_names{j}).data;
%             t  = lap.channels.(ch_names{j}).time;
%             dist = trapz(t, max(s,0) / 3.6);
%             return;
%         end
%     end
%     dist = 5000;   % last resort default: 5km
% end
% 
% 
% function info_s = build_info_from_group(grp, driver_map)
%     info_s.driver     = grp.driver;
%     info_s.car_number = grp.car;
%     info_s.session    = grp.session;
%     info_s.venue      = '';
%     info_s.log_date   = '';
%     info_s.year       = '';
% 
%     % Look up manufacturer and team from driver_map using driver name as key.
%     % keyboard is called if the driver cannot be resolved so the user can
%     % add the missing alias to driverAlias.xlsx and recompile.
%     [mfr, team] = resolve_driver_meta(grp.driver, driver_map);
%     info_s.manufacturer = mfr;
% 
%     % Team: use alias file TM_TLA as source of truth.
%     % Fall back to folder acronym only if alias lookup returned nothing.
%     if ~isempty(team)
%         info_s.team_name = team;
%     else
%         info_s.team_name = grp.team_acronym;
%     end
% end
% 
% 
% % ======================================================================= %
% function [mfr, team] = resolve_driver_meta(driver_name, driver_map)
% % Resolve manufacturer (MAN) and team (TM_TLA) for a driver.
% %
% % Lookup order:
% %   1. Direct struct key match  (driver_name IS the key from resolve_driver)
% %   2. Strip-normalised key match
% %   3. Alias search
% %
% % If no match is found, keyboard is called so the user can fix the alias
% % file and recompile. The script will pause with a descriptive message.
% 
%     mfr  = '';
%     team = '';
% 
%     if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name)
%         return;
%     end
% 
%     name_strip = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]', '');
%     keys = fieldnames(driver_map);
%     entry_found = [];
% 
%     % 1. Direct key lookup
%     if isfield(driver_map, driver_name)
%         entry_found = driver_map.(driver_name);
%     end
% 
%     % 2. Strip-normalised key match
%     if isempty(entry_found)
%         for k = 1:numel(keys)
%             if strcmp(name_strip, regexprep(lower(keys{k}), '[^a-z0-9]', ''))
%                 entry_found = driver_map.(keys{k});
%                 break;
%             end
%         end
%     end
% 
%     % 3. Alias search
%     if isempty(entry_found)
%         for k = 1:numel(keys)
%             e = driver_map.(keys{k});
%             if ~isfield(e, 'aliases'), continue; end
%             for a = 1:numel(e.aliases)
%                 if strcmp(name_strip, regexprep(e.aliases{a}, '[^a-z0-9]', ''))
%                     entry_found = e;
%                     break;
%                 end
%             end
%             if ~isempty(entry_found), break; end
%         end
%     end
% 
%     % No match — pause so user can fix the alias file
%     if isempty(entry_found)
%         fprintf('\n========================================================\n');
%         fprintf('  DRIVER NOT FOUND IN ALIAS FILE: "%s"\n', driver_name);
%         fprintf('  Add this driver to driverAlias.xlsx with MAN and TM_TLA\n');
%         fprintf('  then delete the cache and recompile.\n');
%         fprintf('  Type "dbcont" to skip this driver and continue.\n');
%         fprintf('========================================================\n');
%         keyboard;
%         return;
%     end
% 
%     % Extract manufacturer (prefer MAN full name over MAN_TLA)
%     if isfield(entry_found, 'manufacturer') && ~isempty(entry_found.manufacturer)
%         mfr = entry_found.manufacturer;
%     end
% 
%     % Extract team TLA
%     if isfield(entry_found, 'team_tla') && ~isempty(entry_found.team_tla)
%         team = entry_found.team_tla;
%     end
% end
% 
% 
% function cache = add_failed_entries(cache, grp, err_msg)
%     info_s = build_info_from_group(grp, []);
%     for f = 1:numel(grp.files)
%         cache = smp_cache_add(cache, grp.files{f}, 0, grp.team_acronym, ...
%                               info_s, false, err_msg);
%     end
% end
% 
% 
% function scan_filtered = filter_scan(scan_all, team_filter)
%     scan_filtered = struct('index',{},'acronym',{},'folder',{},'files',{});
%     n = 0;
%     for t = 1:numel(scan_all)
%         idx_str = sprintf('%02d', scan_all(t).index);
%         acro    = scan_all(t).acronym;
%         for f = 1:numel(team_filter)
%             key = upper(strtrim(team_filter{f}));
%             if strcmp(key, idx_str) || strcmp(key, acro)
%                 n = n + 1;
%                 scan_filtered(n) = scan_all(t);
%                 break;
%             end
%         end
%     end
% end
% 
% 
% function val = get_opt(s, f, default)
%     if isfield(s, f) && ~isempty(s.(f)), val = s.(f);
%     else,                                 val = default; end
% end

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
    max_traces    = get_opt(opts, 'max_traces',      5);
    dist_npts     = get_opt(opts, 'dist_n_points',   1000);
    dist_ch       = get_opt(opts, 'dist_channel',    'Odometer');
    verbose       = get_opt(opts, 'verbose',         true);
    date_from     = get_opt(opts, 'date_from',       []);
%     saveCache     = get_opt(opts, 'saveCache',       true);
    saveCache     = get_opt(opts, 'saveCache',      true);
    channel_rules = get_opt(opts, 'channel_rules',  []);
    save_mode     = get_opt(opts, 'save_mode',       'legacy');
    session_filter = get_opt(opts, 'session_filter', {});

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
        cache = process_stream(cache, groups, channels_to_extract, ...
                               min_lt, max_lt, max_traces, dist_npts, ...
                               dist_ch, driver_map, verbose, channel_rules);
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
                                 dist_ch, driver_map, verbose, channel_rules)
    if nargin < 11, channel_rules = []; end
    lap_opts.min_lap_time = min_lt;
    lap_opts.max_lap_time = max_lt;
    lap_opts.verbose      = false;

    dist_opts.distance_channel = dist_ch;
    dist_opts.resolution       = [];
    dist_opts.common_grid      = true;
    dist_opts.verbose          = false;

    n_groups = numel(groups);

    for g = 1:n_groups
        grp = groups(g);
        fprintf('[%d/%d] %s | %s | %s | %d file(s)\n', ...
            g, n_groups, grp.team_acronym, grp.driver, grp.session, grp.n_files);

        % ---- Load and concatenate stints ----
        try
            session = load_and_concat(grp.files, channels_to_extract, verbose);
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

%         fprintf('  %d valid laps\n', numel(laps));
        fprintf('  %d valid laps\n', numel(laps));

        % ---- Data quality filter (NaN bad samples before stats) ----
        if ~isempty(channel_rules)
            laps = smp_data_filter(laps, channel_rules);
        end

        % ---- Compute per-lap stats ----
        % ---- Compute per-lap stats ----
        try
            stat_channels = channels_to_extract;
%             stats = lap_stats(laps, stat_channels, struct('operations', ...
%                 {{'min','max','mean','median','std','var','range'}}));
            stats = lap_stats(laps, stat_channels, ...
            struct('operations', {{'max','min','mean','median','std','var','range',...
            'max non zero','min non zero','mean non zero','median non zero','std non zero','sample_rate'}}));
        catch ME
            fprintf('  [ERROR] lap_stats: %s\n', ME.message);
            clear session laps;
            continue;
        end

        % ---- Select top-N laps by lap time ----
        lap_times = [laps.lap_time];
        [~, sort_idx] = sort(lap_times, 'ascend');
        n_keep = min(max_traces, numel(laps));
        top_idx = sort_idx(1:n_keep);
        top_laps = laps(top_idx);

        fprintf('  Top %d lap times: %s s\n', n_keep, ...
            strjoin(arrayfun(@(t) sprintf('%.2f', t), [top_laps.lap_time], ...
                             'UniformOutput', false), '  '));

        % ---- Package traces (lap_slicer already enriched .dist on all channels) ----
        traces = package_traces(top_laps, channels_to_extract);
        traces.lap_times   = [top_laps.lap_time];
        traces.lap_numbers = [top_laps.lap_number];
        traces.n_traces    = n_keep;

        % ---- Store stats and traces under group key ----
        group_key = matlab.lang.makeValidName(grp.key);
        info_s    = build_info_from_group(grp, driver_map);

        cache.stats.(group_key)  = stats;
        cache.traces.(group_key) = traces;

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

function session = load_and_concat(files, channels_to_extract, verbose)

    if numel(files) == 1
        session = motec_ld_reader(files{1}, channels_to_extract);
        session = smp_custom_channels(session);
        session = filter_channels(session, channels_to_extract);
        return;
    end

    % Multi-stint
    all_sessions = cell(numel(files), 1);
    for f = 1:numel(files)
        if verbose
            [~, fname] = fileparts(files{f});
            fprintf('    Loading stint %d: %s\n', f, fname);
        end
        totalTic = tic;
        t0 = tic;
        s = motec_ld_reader(files{f}, channels_to_extract);
        fprintf('  motec_ID_reader: %.2fs\n', toc(t0));
        t0 = tic;
        s = smp_custom_channels(s);
        fprintf('  smp_custom_channels: %.2fs\n', toc(t0));
        t0 = tic;
        s = filter_channels(s, channels_to_extract);
        fprintf('  filter_channels: %.2fs\n', toc(t0));
        all_sessions{f} = s;
        fprintf('  Total Time: %.2fs\n', toc(totalTic));
    end

    session = concat_sessions(all_sessions);
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

function merged = concat_sessions(sessions)
% Concatenate a cell array of session structs along their time axes.
% The time axis of each subsequent stint is offset to follow the previous.

    merged = sessions{1};
    ch_fields = fieldnames(merged);

    for s = 2:numel(sessions)
        s2 = sessions{s};

        % Find time offset: end of last session
        % Use first available channel time axis
        t_offset = 0;
        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
               ~isempty(merged.(fn).time)
                t_offset = merged.(fn).time(end);
                break;
            end
        end

        % Add a small gap (1 sample period) to avoid exact duplicate timestamps
        % Use median sample period of Lap_Number channel as reference
        if isfield(merged, 'Lap_Number') && numel(merged.Lap_Number.time) > 1
            dt_ref = median(diff(merged.Lap_Number.time));
            t_offset = t_offset + dt_ref;
        else
            t_offset = t_offset + 0.02;   % 50Hz default gap
        end

        % Concatenate each channel
        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if ~isfield(s2, fn), continue; end

            merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
            merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
        end
    end
end


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

        % Only store requested channels
        is_requested = isempty(channels_to_extract) || ...
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
    info_s.driver     = grp.driver;
    info_s.car_number = grp.car;
    info_s.session    = grp.session;
    info_s.venue      = '';
    info_s.log_date   = '';
    info_s.year       = '';

    % Look up manufacturer and team from driver_map using driver name as key.
    % keyboard is called if the driver cannot be resolved so the user can
    % add the missing alias to driverAlias.xlsx and recompile.
    [mfr, team] = resolve_driver_meta(grp.driver, driver_map);
    info_s.manufacturer = mfr;

    % Team: use alias file TM_TLA as source of truth.
    % Fall back to folder acronym only if alias lookup returned nothing.
    if ~isempty(team)
        info_s.team_name = team;
    else
        info_s.team_name = grp.team_acronym;
    end
end


% ======================================================================= %
function [mfr, team] = resolve_driver_meta(driver_name, driver_map)
% Resolve manufacturer (MAN) and team (TM_TLA) for a driver.
%
% Lookup order:
%   1. Direct struct key match  (driver_name IS the key from resolve_driver)
%   2. Strip-normalised key match
%   3. Alias search
%
% If no match is found, keyboard is called so the user can fix the alias
% file and recompile. The script will pause with a descriptive message.

    mfr  = '';
    team = '';

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