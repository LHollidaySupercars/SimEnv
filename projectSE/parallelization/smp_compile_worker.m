% function smp_compile_worker(worker_id, tmp_dir)
% % SMP_COMPILE_WORKER  Runs in each spawned MATLAB Command Window.
% %
% % In TEST_MODE: sleeps to simulate processing, writes dummy results.
% % In LIVE mode: loads its group chunk, runs the full pipeline, writes
% %               a partial cache (manifest + stats + traces maps).
% %
% % Called via:
% %   start "SMP Worker N" cmd /k "<matlab.exe>" -batch "smp_compile_worker(N, tmp_dir)"
% 
%     fprintf('\n============================================\n');
%     fprintf('  SMP Worker %d starting\n', worker_id);
%     fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
%     fprintf('  TMP  : %s\n', tmp_dir);
%     fprintf('============================================\n\n');
% 
%     % ---- Load shared config ----
%     cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
%     if ~exist(cfg_file, 'file')
%         error('Worker %d: config file not found: %s', worker_id, cfg_file);
%     end
%     loaded = load(cfg_file, 'worker_cfg');
%     cfg    = loaded.worker_cfg;
% 
%     % ---- Load this worker's group chunk ----
%     chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
%     if ~exist(chunk_file, 'file')
%         error('Worker %d: chunk file not found: %s', worker_id, chunk_file);
%     end
%     loaded2 = load(chunk_file, 'worker_groups');
%     groups  = loaded2.worker_groups;
% 
%     n_groups = numel(groups);
%     fprintf('Worker %d: %d group(s) to process\n\n', worker_id, n_groups);
% 
%     if n_groups == 0
%         fprintf('Worker %d: nothing to do.\n', worker_id);
%         write_done_flag(worker_id, tmp_dir);
%         return;
%     end
% 
%     % =========================================================
%     if cfg.test_mode
%     % =========================================================
%         partial_cache.results = {};
% 
%         for g = 1:n_groups
%             grp = groups(g);
%             fprintf('[W%d] [%d/%d] %s  (%d file(s), ~%ds work)\n', ...
%                 worker_id, g, n_groups, grp.label, grp.n_files, grp.sleep_s);
% 
%             fprintf('  [W%d] Simulating load...\n', worker_id);
%             pause(grp.sleep_s * 0.4);
% 
%             fprintf('  [W%d] Simulating lap slice...\n', worker_id);
%             pause(grp.sleep_s * 0.3);
% 
%             fprintf('  [W%d] Simulating lap stats...\n', worker_id);
%             pause(grp.sleep_s * 0.3);
% 
%             result = sprintf('[W%d] %s -> %d fake laps processed  [OK]', ...
%                 worker_id, grp.label, grp.n_files * 8);
%             partial_cache.results{end+1} = result;
%             fprintf('  %s\n\n', result);
%         end
% 
%     % =========================================================
%     else
%     % =========================================================
%         channels_to_extract = cfg.channels_to_extract;
%         driver_map          = cfg.driver_map;
%         min_lt              = cfg.min_lt;
%         max_lt              = cfg.max_lt;
%         max_traces          = 5;
% 
%         lap_opts.min_lap_time = min_lt;
%         lap_opts.max_lap_time = max_lt;
%         lap_opts.verbose      = false;
% 
%         stat_ops = {'max','min','mean','median','std','var','range', ...
%                     'max non zero','min non zero','mean non zero', ...
%                     'median non zero','std non zero'};
% 
%         partial_cache.manifest = table();
%         partial_cache.stats    = containers.Map('KeyType','char','ValueType','any');
%         partial_cache.traces   = containers.Map('KeyType','char','ValueType','any');
%         partial_cache.mode     = 'stream';
% 
%         for g = 1:n_groups
%             grp = groups(g);
%             fprintf('[W%d] [%d/%d] %s | %s | %s | %d file(s)\n', ...
%                 worker_id, g, n_groups, ...
%                 grp.team_acronym, grp.driver, grp.session, grp.n_files);
% 
%             try
%                 fprintf('  [W%d] Loading .ld file(s)...\n', worker_id);
%                 session = load_and_concat(grp.files, channels_to_extract, true);
% 
%                 if isempty(session)
%                     fprintf('  [W%d] [WARN] No channel data - skipping.\n', worker_id);
%                     continue;
%                 end
% 
%                 fprintf('  [W%d] Slicing laps...\n', worker_id);
%                 laps = lap_slicer(session, lap_opts);
%                 clear session;
% 
%                 if isempty(laps)
%                     fprintf('  [W%d] [WARN] No valid laps - skipping.\n', worker_id);
%                     info_s = build_info_from_group(grp, driver_map);
%                     for f = 1:numel(grp.files)
%                         partial_cache = smp_cache_add(partial_cache, grp.files{f}, ...
%                             0, grp.team_acronym, info_s, false, 'No valid laps', '');
%                     end
%                     continue;
%                 end
% 
%                 fprintf('  [W%d] %d lap(s) found. Computing stats...\n', worker_id, numel(laps));
%                 stats = lap_stats(laps, channels_to_extract, ...
%                     struct('operations', {stat_ops}));
% 
%                 fprintf('  [W%d] Packaging traces...\n', worker_id);
%                 lap_times = [laps.lap_time];
%                 [~, sort_idx] = sort(lap_times, 'ascend');
%                 top_laps      = laps(sort_idx(1:min(max_traces, numel(laps))));
%                 traces        = package_traces(top_laps, channels_to_extract);
%                 traces.lap_times   = [top_laps.lap_time];
%                 traces.lap_numbers = [top_laps.lap_number];
%                 traces.n_traces    = numel(top_laps);
% 
%                 group_key = matlab.lang.makeValidName(grp.key);
%                 partial_cache.stats(group_key)  = stats;
%                 partial_cache.traces(group_key) = traces;
% 
%                 fprintf('  [W%d] Writing manifest entries...\n', worker_id);
%                 info_s = build_info_from_group(grp, driver_map);
%                 for f = 1:numel(grp.files)
%                     partial_cache = smp_cache_add(partial_cache, grp.files{f}, ...
%                         0, grp.team_acronym, info_s, true, '', group_key);
%                 end
% 
%                 fprintf('  [W%d] Done. Fastest: %.2fs\n\n', ...
%                     worker_id, min([top_laps.lap_time]));
% 
%             catch ME
%                 fprintf('  [W%d] [ERROR] %s\n', worker_id, ME.message);
%                 fprintf('  [W%d] %s\n\n', worker_id, ME.getReport('basic'));
%                 info_s = build_info_from_group(grp, driver_map);
%                 for f = 1:numel(grp.files)
%                     partial_cache = smp_cache_add(partial_cache, grp.files{f}, ...
%                         0, grp.team_acronym, info_s, false, ME.message, '');
%                 end
%             end
%         end
%     end
% 
%     % ---- Save partial cache ----
%     partial_file = fullfile(tmp_dir, sprintf('partial_%d.mat', worker_id));
%     fprintf('Worker %d: saving partial cache to:\n  %s\n', worker_id, partial_file);
%     save(partial_file, 'partial_cache', '-v7.3');
% 
%     write_done_flag(worker_id, tmp_dir);
% 
%     fprintf('\n============================================\n');
%     fprintf('  Worker %d COMPLETE  [%s]\n', worker_id, datestr(now,'HH:MM:SS'));
%     fprintf('============================================\n');
% end
% 
% 
% % ======================================================================= %
% %  LOAD AND CONCAT  (mirrors smp_compile_event logic)
% % ======================================================================= %
% function session = load_and_concat(files, channels_to_extract, verbose)
%     if numel(files) == 1
%         session = motec_ld_reader(files{1});
%         session = smp_custom_channels(session);
%         session = filter_channels(session, channels_to_extract);
%         return;
%     end
% 
%     all_sessions = cell(numel(files), 1);
%     for f = 1:numel(files)
%         if verbose
%             [~, fname] = fileparts(files{f});
%             fprintf('    Loading stint %d: %s\n', f, fname);
%         end
%         s = motec_ld_reader(files{f});
%         s = smp_custom_channels(s);
%         s = filter_channels(s, channels_to_extract);
%         all_sessions{f} = s;
%     end
%     session = concat_sessions(all_sessions);
% end
% 
% 
% % ======================================================================= %
% function session = filter_channels(session, channels_to_extract)
%     if isempty(channels_to_extract), return; end
%     all_fields      = fieldnames(session);
%     requested_san   = cellfun(@(c) regexprep(c,'[^a-zA-Z0-9_]','_'), ...
%                               channels_to_extract, 'UniformOutput', false);
%     fields_lower    = lower(all_fields);
%     requested_lower = lower([channels_to_extract(:); requested_san(:)]);
%     keep_mask       = ismember(fields_lower, requested_lower);
%     drop            = all_fields(~keep_mask);
%     if ~isempty(drop)
%         session = rmfield(session, drop);
%     end
% end
% 
% 
% % ======================================================================= %
% function merged = concat_sessions(sessions)
%     merged    = sessions{1};
%     ch_fields = fieldnames(merged);
% 
%     for s = 2:numel(sessions)
%         s2       = sessions{s};
%         t_offset = 0;
% 
%         for c = 1:numel(ch_fields)
%             fn = ch_fields{c};
%             if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
%                ~isempty(merged.(fn).time)
%                 t_offset = merged.(fn).time(end);
%                 break;
%             end
%         end
% 
%         if isfield(merged, 'Lap_Number') && numel(merged.Lap_Number.time) > 1
%             t_offset = t_offset + median(diff(merged.Lap_Number.time));
%         else
%             t_offset = t_offset + 0.02;
%         end
% 
%         for c = 1:numel(ch_fields)
%             fn = ch_fields{c};
%             if ~isfield(s2, fn), continue; end
%             merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
%             merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
%         end
%     end
% end
% 
% 
% % ======================================================================= %
% %  PACKAGE TRACES  (mirrors smp_compile_event)
% % ======================================================================= %
% function traces = package_traces(top_laps, channels_to_extract)
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
%         is_requested = isempty(channels_to_extract) || ...
%                        any(strcmpi(fn, channels_to_extract)) || ...
%                        any(cellfun(@(ch) strcmpi(regexprep(ch,'[^a-zA-Z0-9_]','_'), fn), ...
%                                    channels_to_extract));
%         if ~is_requested, continue; end
% 
%         for k = 1:n_traces
%             lap_ch = top_laps(k).channels.(fn);
%             if ~isfield(lap_ch, 'dist') || ~isfield(lap_ch, 'data')
%                 traces.(fn)(k).data = [];
%                 traces.(fn)(k).dist = [];
%                 continue;
%             end
%             traces.(fn)(k).data = lap_ch.data(:);
%             traces.(fn)(k).dist = lap_ch.dist(:);
%         end
%     end
% end
% 
% 
% % ======================================================================= %
% %  BUILD INFO FROM GROUP  (mirrors smp_compile_event)
% % ======================================================================= %
% function info_s = build_info_from_group(grp, driver_map)
%     info_s.driver     = grp.driver;
%     info_s.car_number = grp.car;
%     info_s.session    = grp.session;
%     info_s.venue      = '';
%     info_s.log_date   = '';
%     info_s.year       = '';
%     info_s.vehicle    = '';
%     info_s.engine_id  = '';
%     info_s.run        = '';
%     info_s.date       = '';
%     info_s.time       = '';
% 
%     [mfr, team]         = resolve_driver_meta(grp.driver, driver_map);
%     info_s.manufacturer = mfr;
% 
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
%     mfr  = '';
%     team = '';
% 
%     if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name)
%         return;
%     end
% 
%     name_strip  = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]', '');
%     keys        = fieldnames(driver_map);
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
%     if isempty(entry_found)
%         fprintf('[WARN] Driver not found in alias file: "%s" — manufacturer unknown.\n', driver_name);
%         return;
%     end
% 
%     if isfield(entry_found, 'manufacturer') && ~isempty(entry_found.manufacturer)
%         mfr = entry_found.manufacturer;
%     end
%     if isfield(entry_found, 'team_tla') && ~isempty(entry_found.team_tla)
%         team = entry_found.team_tla;
%     end
% end
% 
% 
% % ======================================================================= %
% function write_done_flag(worker_id, tmp_dir)
%     flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
%     fid = fopen(flag_file, 'w');
%     fprintf(fid, 'done at %s', datestr(now));
%     fclose(fid);
%     fprintf('Worker %d: done flag written.\n', worker_id);
% end

function smp_compile_worker(worker_id, tmp_dir)
% SMP_COMPILE_WORKER  Runs in each spawned MATLAB Command Window.
%
% In TEST_MODE: sleeps to simulate processing, writes dummy results.
% In LIVE mode: loads its group chunk, runs the full pipeline, writes
%               a partial cache that mirrors smp_compile_event output exactly.
%
% Called via:
%   start "SMP Worker N" cmd /k "<matlab.exe>" -batch "smp_compile_worker(N, tmp_dir)"

    fprintf('\n============================================\n');
    fprintf('  SMP Worker %d starting\n', worker_id);
    fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('  TMP  : %s\n', tmp_dir);
    fprintf('============================================\n\n');

    % ---- Load shared config ----
    cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
    if ~exist(cfg_file, 'file')
        error('Worker %d: config file not found: %s', worker_id, cfg_file);
    end
    loaded = load(cfg_file, 'worker_cfg');
    cfg    = loaded.worker_cfg;

    % ---- Load this worker's group chunk ----
    chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
    if ~exist(chunk_file, 'file')
        error('Worker %d: chunk file not found: %s', worker_id, chunk_file);
    end
    loaded2 = load(chunk_file, 'worker_groups');
    groups  = loaded2.worker_groups;

    n_groups = numel(groups);
    fprintf('Worker %d: %d group(s) to process\n\n', worker_id, n_groups);

    if n_groups == 0
        fprintf('Worker %d: nothing to do.\n', worker_id);
        write_done_flag(worker_id, tmp_dir);
        return;
    end

    % =========================================================
    if cfg.test_mode
    % =========================================================
        partial_cache.results = {};

        for g = 1:n_groups
            grp = groups(g);
            fprintf('[W%d] [%d/%d] %s  (%d file(s), ~%ds work)\n', ...
                worker_id, g, n_groups, grp.label, grp.n_files, grp.sleep_s);

            fprintf('  [W%d] Simulating load...\n', worker_id);
            pause(grp.sleep_s * 0.4);
            fprintf('  [W%d] Simulating lap slice...\n', worker_id);
            pause(grp.sleep_s * 0.3);
            fprintf('  [W%d] Simulating lap stats...\n', worker_id);
            pause(grp.sleep_s * 0.3);

            result = sprintf('[W%d] %s -> %d fake laps processed  [OK]', ...
                worker_id, grp.label, grp.n_files * 8);
            partial_cache.results{end+1} = result;
            fprintf('  %s\n\n', result);
        end

    % =========================================================
    else
    % =========================================================
%         channels_to_extract = cfg.channels_to_extract;
%         driver_map          = cfg.driver_map;
%         min_lt              = cfg.min_lt;
%         max_lt              = cfg.max_lt;
%         max_traces          = 5;
        channels_to_extract = cfg.channels_to_extract;
        driver_map          = cfg.driver_map;
        min_lt              = cfg.min_lt;
        max_lt              = cfg.max_lt;
        max_traces          = 5;
        channel_rules       = [];
        
        if isfield(cfg, 'channel_rules')
            channel_rules = cfg.channel_rules;
        end
        
        lap_opts.min_lap_time = min_lt;
        lap_opts.max_lap_time = max_lt;
        lap_opts.verbose      = false;

        stat_ops = {'max','min','mean','median','std','var','range', ...
                    'max non zero','min non zero','mean non zero', ...
                    'median non zero','std non zero'};

        % Mirror smp_compile_event exactly — stats/traces are plain structs
        partial_cache.manifest = smp_cache_empty().manifest;
        partial_cache.manifest.GroupKey = repmat({''}, 0, 1);
        partial_cache.stats    = struct();
        partial_cache.traces   = struct();
        partial_cache.mode     = 'stream';

        for g = 1:n_groups
            grp = groups(g);
            fprintf('[W%d] [%d/%d] %s | %s | %s | %d file(s)\n', ...
                worker_id, g, n_groups, ...
                grp.team_acronym, grp.driver, grp.session, grp.n_files);

            try
                fprintf('  [W%d] Loading .ld file(s)...\n', worker_id);
                session = load_and_concat(grp.files, channels_to_extract, true);

                if isempty(session)
                    fprintf('  [W%d] [WARN] No channel data - skipping.\n', worker_id);
                    continue;
                end

                fprintf('  [W%d] Slicing laps...\n', worker_id);
                laps = lap_slicer(session, lap_opts);
                clear session;

                if isempty(laps)
                    fprintf('  [W%d] [WARN] No valid laps - skipping.\n', worker_id);
                    info_s = build_info_from_group(grp, driver_map);
                    for f = 1:numel(grp.files)
                        partial_cache = smp_cache_add(partial_cache, grp.files{f}, ...
                            0, grp.team_acronym, info_s, false, 'No valid laps', '');
                    end
                    continue;
                end

%                 fprintf('  [W%d] %d lap(s) found. Computing stats...\n', worker_id, numel(laps));
%                 stats = lap_stats(laps, channels_to_extract, ...
%                     struct('operations', {stat_ops}));
                fprintf('  [W%d] %d lap(s) found. Computing stats...\n', worker_id, numel(laps));

                % ---- Data quality filter ----
                if ~isempty(channel_rules)
                    laps = smp_data_filter(laps, channel_rules);
                end

                stats = lap_stats(laps, channels_to_extract, ...
                fprintf('  [W%d] Packaging traces...\n', worker_id);
                lap_times = [laps.lap_time];
                [~, sort_idx] = sort(lap_times, 'ascend');
                n_keep        = min(max_traces, numel(laps));
                top_laps      = laps(sort_idx(1:n_keep));
                traces        = package_traces(top_laps, channels_to_extract);
                traces.lap_times   = [top_laps.lap_time];
                traces.lap_numbers = [top_laps.lap_number];
                traces.n_traces    = n_keep;

                % Store with dot notation — mirrors smp_compile_event line 282-283
                group_key = matlab.lang.makeValidName(grp.key);
                partial_cache.stats.(group_key)  = stats;
                partial_cache.traces.(group_key) = traces;

                fprintf('  [W%d] Writing manifest entries...\n', worker_id);
                info_s = build_info_from_group(grp, driver_map);
                for f = 1:numel(grp.files)
                    partial_cache = smp_cache_add(partial_cache, grp.files{f}, ...
                        0, grp.team_acronym, info_s, true, '', group_key);
                end

                fprintf('  [W%d] Done. Fastest: %.2fs\n\n', worker_id, min(lap_times));

            catch ME
                fprintf('  [W%d] [ERROR] %s\n', worker_id, ME.message);
                fprintf('  [W%d] %s\n\n', worker_id, ME.getReport('basic'));
                info_s = build_info_from_group(grp, driver_map);
                for f = 1:numel(grp.files)
                    partial_cache = smp_cache_add(partial_cache, grp.files{f}, ...
                        0, grp.team_acronym, info_s, false, ME.message, '');
                end
            end
        end
    end

    % ---- Save partial cache ----
    partial_file = fullfile(tmp_dir, sprintf('partial_%d.mat', worker_id));
    fprintf('Worker %d: saving partial cache to:\n  %s\n', worker_id, partial_file);
    save(partial_file, 'partial_cache', '-v7.3');

    write_done_flag(worker_id, tmp_dir);

    fprintf('\n============================================\n');
    fprintf('  Worker %d COMPLETE  [%s]\n', worker_id, datestr(now,'HH:MM:SS'));
    fprintf('============================================\n');
end


% ======================================================================= %
%  LOAD AND CONCAT  (mirrors smp_compile_event exactly)
% ======================================================================= %
function session = load_and_concat(files, channels_to_extract, verbose)
    if numel(files) == 1
%         session = motec_ld_reader(files{1});
        session = motec_ld_reader(files{1}, channels_to_extract);
        session = smp_custom_channels(session);
        session = filter_channels(session, channels_to_extract);
        return;
    end

    all_sessions = cell(numel(files), 1);
    for f = 1:numel(files)
        if verbose
            [~, fname] = fileparts(files{f});
            fprintf('    Loading stint %d: %s\n', f, fname);
        end
%         s = motec_ld_reader(files{f});
        s = motec_ld_reader(files{f}, channels_to_extract);
        s = smp_custom_channels(s);
        s = filter_channels(s, channels_to_extract);
        all_sessions{f} = s;
    end
    session = concat_sessions(all_sessions);
end


% ======================================================================= %
function session = filter_channels(session, channels_to_extract)
    if isempty(channels_to_extract), return; end
    all_fields      = fieldnames(session);
    requested_san   = cellfun(@(c) regexprep(c,'[^a-zA-Z0-9_]','_'), ...
                              channels_to_extract, 'UniformOutput', false);
    fields_lower    = lower(all_fields);
    requested_lower = lower([channels_to_extract(:); requested_san(:)]);
    keep_mask       = ismember(fields_lower, requested_lower);
    drop            = all_fields(~keep_mask);
    if ~isempty(drop)
        session = rmfield(session, drop);
    end
end


% ======================================================================= %
function merged = concat_sessions(sessions)
    merged    = sessions{1};
    ch_fields = fieldnames(merged);

    for s = 2:numel(sessions)
        s2       = sessions{s};
        t_offset = 0;

        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
               ~isempty(merged.(fn).time)
                t_offset = merged.(fn).time(end);
                break;
            end
        end

        if isfield(merged, 'Lap_Number') && numel(merged.Lap_Number.time) > 1
            t_offset = t_offset + median(diff(merged.Lap_Number.time));
        else
            t_offset = t_offset + 0.02;
        end

        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if ~isfield(s2, fn), continue; end
            merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
            merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
        end
    end
end


% ======================================================================= %
%  PACKAGE TRACES  (mirrors smp_compile_event exactly)
% ======================================================================= %
function traces = package_traces(top_laps, channels_to_extract)
    traces = struct();

    if isempty(top_laps)
        traces.n_traces = 0;
        return;
    end

    n_traces  = numel(top_laps);
    ch_fields = fieldnames(top_laps(1).channels);

    for c = 1:numel(ch_fields)
        fn = ch_fields{c};

        is_requested = isempty(channels_to_extract) || ...
                       any(strcmpi(fn, channels_to_extract)) || ...
                       any(cellfun(@(ch) strcmpi(regexprep(ch,'[^a-zA-Z0-9_]','_'), fn), ...
                                   channels_to_extract));
        if ~is_requested, continue; end

        for k = 1:n_traces
            lap_ch = top_laps(k).channels.(fn);
            if ~isfield(lap_ch, 'dist') || ~isfield(lap_ch, 'data')
                traces.(fn)(k).data = [];
                traces.(fn)(k).dist = [];
                continue;
            end
            traces.(fn)(k).data = lap_ch.data(:);
            traces.(fn)(k).dist = lap_ch.dist(:);
        end
    end
end


% ======================================================================= %
%  BUILD INFO FROM GROUP  (mirrors smp_compile_event exactly)
% ======================================================================= %
function info_s = build_info_from_group(grp, driver_map)
    info_s.driver     = grp.driver;
    info_s.car_number = grp.car;
    info_s.session    = grp.session;
    info_s.venue      = '';
    info_s.log_date   = '';
    info_s.year       = '';
    info_s.vehicle    = '';
    info_s.engine_id  = '';
    info_s.run        = '';
    info_s.date       = '';
    info_s.time       = '';

    [mfr, team]         = resolve_driver_meta(grp.driver, driver_map);
    info_s.manufacturer = mfr;

    if ~isempty(team)
        info_s.team_name = team;
    else
        info_s.team_name = grp.team_acronym;
    end
end


% ======================================================================= %
function [mfr, team] = resolve_driver_meta(driver_name, driver_map)
    mfr  = '';
    team = '';

    if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name)
        return;
    end

    name_strip  = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]', '');
    keys        = fieldnames(driver_map);
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

    if isempty(entry_found)
        fprintf('[WARN] Driver not found in alias file: "%s"\n', driver_name);
        return;
    end

    if isfield(entry_found, 'manufacturer') && ~isempty(entry_found.manufacturer)
        mfr = entry_found.manufacturer;
    end
    if isfield(entry_found, 'team_tla') && ~isempty(entry_found.team_tla)
        team = entry_found.team_tla;
    end
end


% ======================================================================= %
function write_done_flag(worker_id, tmp_dir)
    flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
    fid = fopen(flag_file, 'w');
    fprintf(fid, 'done at %s', datestr(now));
    fclose(fid);
    fprintf('Worker %d: done flag written.\n', worker_id);
end