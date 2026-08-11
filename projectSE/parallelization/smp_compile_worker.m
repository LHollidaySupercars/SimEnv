    % function smp_compile_worker(worker_id, tmp_dir)
    % % SMP_COMPILE_WORKER  Runs in each spawned MATLAB Command Window.
    % %
    % % In TEST_MODE: sleeps to simulate processing, writes dummy results.
    % % In LIVE mode: loads its group chunk, runs the full pipeline, writes
    % %               a partial cache that mirrors smp_compile_event output exactly.
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
    %             fprintf('  [W%d] Simulating lap slice...\n', worker_id);
    %             pause(grp.sleep_s * 0.3);
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
    %         % Build opts struct that mirrors compile_opts in the main script,
    %         % using the pre-resolved min/max lap times so smp_compile_event
    %         % skips its own smp_season_get call (track is left blank).
    %         worker_opts = struct();
    %         worker_opts.mode             = 'stream';
    %         worker_opts.track            = '';           % lap limits already resolved
    %         worker_opts.verbose          = true;
    %         worker_opts.saveCache        = false;        % workers never save to disk
    %         worker_opts.groups           = groups;       % bypass scan/diff/group steps
    % 
    %         % Pass pre-resolved lap time limits via a min/max override if supported,
    %         % otherwise fall back via season + no track (uses defaults).
    %         % We inject them by temporarily patching season — or just pass TRACK so
    %         % smp_compile_event can resolve them itself from the season struct.
    %         worker_opts.track            = cfg.track;
    % 
    %         % Forward all opts that process_stream needs
    %         if isfield(cfg, 'max_traces'),     worker_opts.max_traces       = cfg.max_traces;     else, worker_opts.max_traces       = 5;              end
    %         if isfield(cfg, 'channel_rules'),  worker_opts.channel_rules    = cfg.channel_rules;  else, worker_opts.channel_rules    = [];             end
    %         if isfield(cfg, 'detect_pitlane'), worker_opts.detect_pitlane   = cfg.detect_pitlane; else, worker_opts.detect_pitlane   = false;          end
    %         if isfield(cfg, 'fcy_channel'),    worker_opts.fcy_channel      = cfg.fcy_channel;    else, worker_opts.fcy_channel      = 'FCY_Flag';     end
    %         if isfield(cfg, 'br2_channel'),    worker_opts.br2_channel      = cfg.br2_channel;    else, worker_opts.br2_channel      = 'BR2_Beacon_Number'; end
    %         if isfield(cfg, 'br2_protocol'),   worker_opts.br2_protocol     = cfg.br2_protocol;   else, worker_opts.br2_protocol     = 'standard';     end
    %         if isfield(cfg, 'beacon_check'),   worker_opts.beacon_check     = cfg.beacon_check;   else, worker_opts.beacon_check     = false;          end
    %         if isfield(cfg, 'all_laps'),       worker_opts.all_laps         = cfg.all_laps;        else, worker_opts.all_laps         = false;          end
    %         if isfield(cfg, 'load_all_ch'),    worker_opts.load_all_channels = cfg.load_all_ch;   end
    %         if isfield(cfg, 'concat_csv_dir'), worker_opts.concat_csv_dir   = cfg.concat_csv_dir; end
    %         if isfield(cfg, 'show_report'),    worker_opts.showConcatReport  = cfg.show_report;   end
    %         if isfield(cfg, 'unique_fp'),      worker_opts.uniqueFingerprint = cfg.unique_fp;     end
    %         if isfield(cfg, 'T_gated'),        worker_opts.T_gated           = cfg.T_gated;       end
    %         if isfield(cfg, 'l180_mode'),      worker_opts.l180_mode         = cfg.l180_mode;      else, worker_opts.l180_mode = 'drop_duplicate'; end
    % 
    %         partial_cache = smp_compile_event('', {}, cfg.channels_to_extract, ...
    %                             cfg.season, cfg.driver_map, cfg.alias, worker_opts);
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
    % %  LOAD AND CONCAT  (mirrors smp_compile_event exactly)
    % % ======================================================================= %
    % % function session = load_and_concat(files, channels_to_extract, verbose)
    % %     if numel(files) == 1
    % % %         session = motec_ld_reader(files{1});
    % %         session = motec_ld_reader(files{1}, channels_to_extract);
    % %         session = smp_custom_channels(session);
    % %         session = filter_channels(session, channels_to_extract);
    % %         return;
    % %     end
    % % 
    % %     all_sessions = cell(numel(files), 1);
    % %     for f = 1:numel(files)
    % %         if verbose
    % %             [~, fname] = fileparts(files{f});
    % %             fprintf('    Loading stint %d: %s\n', f, fname);
    % %         end
    % % %         s = motec_ld_reader(files{f});
    % %         s = motec_ld_reader(files{f}, channels_to_extract);
    % %         s = smp_custom_channels(s);
    % %         s = filter_channels(s, channels_to_extract);
    % %         all_sessions{f} = s;
    % %     end
    % %     session = concat_sessions(all_sessions);
    % % end
    % 
    % function session = load_and_concat(files, channels_to_extract, verbose, T_gated)
    %     if numel(files) == 1
    %         session = motec_ld_reader(files{1}, channels_to_extract);
    %         session = smp_custom_channels(session);
    %         [session, gated_names]  = smp_gated_channels(session, T_gated);
    %         channels_to_extract     = union(channels_to_extract, gated_names);
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
    %         s = motec_ld_reader(files{f}, channels_to_extract);
    %         s = smp_custom_channels(s);
    %         [s, gated_names]    = smp_gated_channels(s, T_gated);
    %         channels_to_extract = union(channels_to_extract, gated_names);
    %         s = filter_channels(s, channels_to_extract);
    %         all_sessions{f} = s;
    %     end
    %     session = concat_sessions(all_sessions);
    % end
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
    % %  PACKAGE TRACES  (mirrors smp_compile_event exactly)
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
    % %  BUILD INFO FROM GROUP  (mirrors smp_compile_event exactly)
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
    %     if isfield(driver_map, driver_name)
    %         entry_found = driver_map.(driver_name);
    %     end
    % 
    %     if isempty(entry_found)
    %         for k = 1:numel(keys)
    %             if strcmp(name_strip, regexprep(lower(keys{k}), '[^a-z0-9]', ''))
    %                 entry_found = driver_map.(keys{k});
    %                 break;
    %             end
    %         end
    %     end
    % 
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
    %         fprintf('[WARN] Driver not found in alias file: "%s"\n', driver_name);
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

%     function smp_compile_worker(worker_id, tmp_dir)
% % SMP_COMPILE_WORKER  Runs in each spawned MATLAB Command Window.
% %
% % In TEST_MODE: sleeps to simulate processing, writes dummy results.
% % In LIVE mode: loads its group chunk, then calls smp_compile_event in
% %               small batches ("diarrhea mode") so memory is flushed to
% %               disk and released frequently instead of accumulating for
% %               the whole chunk.
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
%             fprintf('  [W%d] Simulating lap slice...\n', worker_id);
%             pause(grp.sleep_s * 0.3);
%             fprintf('  [W%d] Simulating lap stats...\n', worker_id);
%             pause(grp.sleep_s * 0.3);
% 
%             result = sprintf('[W%d] %s -> %d fake laps processed  [OK]', ...
%                 worker_id, grp.label, grp.n_files * 8);
%             partial_cache.results{end+1} = result;
%             fprintf('  %s\n\n', result);
%         end
% 
%         partial_file = fullfile(tmp_dir, sprintf('partial_%d.mat', worker_id));
%         fprintf('Worker %d: saving partial cache to:\n  %s\n', worker_id, partial_file);
%         save(partial_file, 'partial_cache', '-v7.3');
% 
%     % =========================================================
%     else
%     % =========================================================
%         % ---- diarrhea mode settings ----
%         diarrhea_mode = true;   % flush to disk frequently, default on
%         if isfield(cfg, 'diarrhea_mode'), diarrhea_mode = cfg.diarrhea_mode; end
%         flush_every_n = 1;      % groups per smp_compile_event call/flush
%         if isfield(cfg, 'flush_every_n'), flush_every_n = cfg.flush_every_n; end
%         if ~diarrhea_mode
%             flush_every_n = n_groups;   % one big call, old behaviour
%         end
% 
%         % Build opts struct that mirrors compile_opts in the main script,
%         % using the pre-resolved min/max lap times so smp_compile_event
%         % skips its own smp_season_get call (track is left blank).
%         worker_opts = struct();
%         worker_opts.mode             = 'stream';
%         worker_opts.verbose          = true;
%         worker_opts.saveCache        = false;        % workers never save to disk
%         worker_opts.track            = cfg.track;
% 
%         % Forward all opts that process_stream needs
%         if isfield(cfg, 'max_traces'),     worker_opts.max_traces       = cfg.max_traces;     else, worker_opts.max_traces       = 5;              end
%         if isfield(cfg, 'channel_rules'),  worker_opts.channel_rules    = cfg.channel_rules;  else, worker_opts.channel_rules    = [];             end
%         if isfield(cfg, 'detect_pitlane'), worker_opts.detect_pitlane   = cfg.detect_pitlane; else, worker_opts.detect_pitlane   = false;          end
%         if isfield(cfg, 'fcy_channel'),    worker_opts.fcy_channel      = cfg.fcy_channel;    else, worker_opts.fcy_channel      = 'FCY_Flag';     end
%         if isfield(cfg, 'br2_channel'),    worker_opts.br2_channel      = cfg.br2_channel;    else, worker_opts.br2_channel      = 'BR2_Beacon_Number'; end
%         if isfield(cfg, 'br2_protocol'),   worker_opts.br2_protocol     = cfg.br2_protocol;   else, worker_opts.br2_protocol     = 'standard';     end
%         if isfield(cfg, 'beacon_check'),   worker_opts.beacon_check     = cfg.beacon_check;   else, worker_opts.beacon_check     = false;          end
%         if isfield(cfg, 'all_laps'),       worker_opts.all_laps         = cfg.all_laps;        else, worker_opts.all_laps         = false;          end
%         if isfield(cfg, 'load_all_ch'),    worker_opts.load_all_channels = cfg.load_all_ch;   end
%         if isfield(cfg, 'concat_csv_dir'), worker_opts.concat_csv_dir   = cfg.concat_csv_dir; end
%         if isfield(cfg, 'show_report'),    worker_opts.showConcatReport  = cfg.show_report;   end
%         if isfield(cfg, 'unique_fp'),      worker_opts.uniqueFingerprint = cfg.unique_fp;     end
%         if isfield(cfg, 'T_gated'),        worker_opts.T_gated           = cfg.T_gated;       end
%         if isfield(cfg, 'l180_mode'),      worker_opts.l180_mode         = cfg.l180_mode;      else, worker_opts.l180_mode = 'drop_duplicate'; end
% 
%         % ---- Process in batches, flushing + clearing after each ----
%         n_batches = ceil(n_groups / flush_every_n);
%         fprintf('Worker %d: %d batch(es) of up to %d group(s) each (diarrhea_mode=%d)\n\n', ...
%             worker_id, n_batches, flush_every_n, diarrhea_mode);
% 
%         for b = 1:n_batches
%             i_start = (b-1)*flush_every_n + 1;
%             i_end   = min(b*flush_every_n, n_groups);
%             batch_groups = groups(i_start:i_end);
% 
%             fprintf('[W%d] --- Batch %d/%d: group(s) %d-%d ---\n', ...
%                 worker_id, b, n_batches, i_start, i_end);
% 
%             worker_opts.groups = batch_groups;   % bypass scan/diff/group steps in smp_compile_event
% 
%             try
%                 partial_cache = smp_compile_event('', {}, cfg.channels_to_extract, ...
%                                     cfg.season, cfg.driver_map, cfg.alias, worker_opts);
%             catch ME
%                 fprintf('  [W%d] [ERROR] Batch %d failed: %s\n', worker_id, b, ME.message);
%                 fprintf('  [W%d] %s\n\n', worker_id, ME.getReport('basic'));
%                 continue;   % skip flushing this batch; next batch still attempted
%             end
% 
%             partial_file = fullfile(tmp_dir, sprintf('partial_%d_%d.mat', worker_id, b));
%             fprintf('  [W%d] [FLUSH %d/%d] saving %d manifest row(s) -> %s\n', ...
%                 worker_id, b, n_batches, height(partial_cache.manifest), partial_file);
%             save(partial_file, 'partial_cache', '-v7.3');
% 
%             clear partial_cache;   % release before next batch
%         end
%     end
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
% function write_done_flag(worker_id, tmp_dir)
%     flag_file = fullfile(tmp_dir, sprintf('done_%d.flag', worker_id));
%     fid = fopen(flag_file, 'w');
%     fprintf(fid, 'done at %s', datestr(now));
%     fclose(fid);
%     fprintf('Worker %d: done flag written.\n', worker_id);
% end

% function smp_compile_worker(worker_id, tmp_dir)
% % SMP_COMPILE_WORKER  Runs in each spawned MATLAB Command Window.
% %
% % In TEST_MODE: sleeps to simulate processing, writes dummy results.
% % In LIVE mode: loads its group chunk, then calls smp_compile_event in
% %               small batches ("diarrhea mode") so memory is flushed to
% %               disk and released frequently instead of accumulating for
% %               the whole chunk.
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
%             fprintf('  [W%d] Simulating lap slice...\n', worker_id);
%             pause(grp.sleep_s * 0.3);
%             fprintf('  [W%d] Simulating lap stats...\n', worker_id);
%             pause(grp.sleep_s * 0.3);
% 
%             result = sprintf('[W%d] %s -> %d fake laps processed  [OK]', ...
%                 worker_id, grp.label, grp.n_files * 8);
%             partial_cache.results{end+1} = result;
%             fprintf('  %s\n\n', result);
%         end
% 
%         partial_file = fullfile(tmp_dir, sprintf('partial_%d.mat', worker_id));
%         fprintf('Worker %d: saving partial cache to:\n  %s\n', worker_id, partial_file);
%         save(partial_file, 'partial_cache', '-v7.3');
% 
%     % =========================================================
%     else
%     % =========================================================
%         % ---- diarrhea mode settings ----
%         diarrhea_mode = true;   % flush to disk frequently, default on
%         if isfield(cfg, 'diarrhea_mode'), diarrhea_mode = cfg.diarrhea_mode; end
%         flush_every_n = 1;      % groups per smp_compile_event call/flush
%         if isfield(cfg, 'flush_every_n'), flush_every_n = cfg.flush_every_n; end
%         if ~diarrhea_mode
%             flush_every_n = n_groups;   % one big call, old behaviour
%         end
% 
%         % Build opts struct that mirrors compile_opts in the main script,
%         % using the pre-resolved min/max lap times so smp_compile_event
%         % skips its own smp_season_get call (track is left blank).
%         worker_opts = struct();
%         worker_opts.mode             = 'stream';
%         worker_opts.verbose          = true;
%         worker_opts.saveCache        = false;        % workers never save to disk
%         worker_opts.track            = cfg.track;
% 
%         % Forward all opts that process_stream needs
%         if isfield(cfg, 'max_traces'),     worker_opts.max_traces       = cfg.max_traces;     else, worker_opts.max_traces       = 5;              end
%         if isfield(cfg, 'channel_rules'),  worker_opts.channel_rules    = cfg.channel_rules;  else, worker_opts.channel_rules    = [];             end
%         if isfield(cfg, 'detect_pitlane'), worker_opts.detect_pitlane   = cfg.detect_pitlane; else, worker_opts.detect_pitlane   = false;          end
%         if isfield(cfg, 'fcy_channel'),    worker_opts.fcy_channel      = cfg.fcy_channel;    else, worker_opts.fcy_channel      = 'FCY_Flag';     end
%         if isfield(cfg, 'br2_channel'),    worker_opts.br2_channel      = cfg.br2_channel;    else, worker_opts.br2_channel      = 'BR2_Beacon_Number'; end
%         if isfield(cfg, 'br2_protocol'),   worker_opts.br2_protocol     = cfg.br2_protocol;   else, worker_opts.br2_protocol     = 'standard';     end
%         if isfield(cfg, 'beacon_check'),   worker_opts.beacon_check     = cfg.beacon_check;   else, worker_opts.beacon_check     = false;          end
%         if isfield(cfg, 'all_laps'),       worker_opts.all_laps         = cfg.all_laps;        else, worker_opts.all_laps         = false;          end
%         if isfield(cfg, 'load_all_ch'),    worker_opts.load_all_channels = cfg.load_all_ch;   end
%         if isfield(cfg, 'concat_csv_dir'), worker_opts.concat_csv_dir   = cfg.concat_csv_dir; end
%         if isfield(cfg, 'show_report'),    worker_opts.showConcatReport  = cfg.show_report;   end
%         if isfield(cfg, 'unique_fp'),      worker_opts.uniqueFingerprint = cfg.unique_fp;     end
%         if isfield(cfg, 'T_gated'),        worker_opts.T_gated           = cfg.T_gated;       end
%         if isfield(cfg, 'l180_mode'),      worker_opts.l180_mode         = cfg.l180_mode;      else, worker_opts.l180_mode = 'drop_duplicate'; end
% 
%         % ---- Process in batches, flushing + clearing after each ----
%         n_batches = ceil(n_groups / flush_every_n);
%         fprintf('Worker %d: %d batch(es) of up to %d group(s) each (diarrhea_mode=%d)\n\n', ...
%             worker_id, n_batches, flush_every_n, diarrhea_mode);
% 
%         for b = 1:n_batches
%             i_start = (b-1)*flush_every_n + 1;
%             i_end   = min(b*flush_every_n, n_groups);
%             batch_groups = groups(i_start:i_end);
% 
%             fprintf('[W%d] --- Batch %d/%d: group(s) %d-%d ---\n', ...
%                 worker_id, b, n_batches, i_start, i_end);
% 
%             worker_opts.groups = batch_groups;   % bypass scan/diff/group steps in smp_compile_event
% 
%             try
%                 partial_cache = smp_compile_event('', {}, cfg.channels_to_extract, ...
%                                     cfg.season, cfg.driver_map, cfg.alias, worker_opts);
%             catch ME
%                 fprintf('  [W%d] [ERROR] Batch %d failed: %s\n', worker_id, b, ME.message);
%                 fprintf('  [W%d] %s\n\n', worker_id, ME.getReport('basic'));
%                 continue;   % skip flushing this batch; next batch still attempted
%             end
% 
%             flush_partial_cache(partial_cache, worker_id, b, tmp_dir);
% 
%             clear partial_cache;   % release before next batch
%         end
%     end
% 
%     write_done_flag(worker_id, tmp_dir);
% 
%     fprintf('\n============================================\n');
%     fprintf('  Worker %d COMPLETE  [%s]\n', worker_id, datestr(now,'HH:MM:SS'));
%     fprintf('============================================\n');
% end

% function smp_compile_worker(worker_id, tmp_dir)
% % SMP_COMPILE_WORKER  Runs in each spawned MATLAB Command Window.
% %
% % In TEST_MODE: sleeps to simulate processing, writes dummy results.
% % In LIVE mode: loads its group chunk, then calls smp_compile_event in
% %               small batches ("diarrhea mode") so memory is flushed to
% %               disk and released frequently instead of accumulating for
% %               the whole chunk.
% %
% % Full console output is also captured to worker_<N>_log.txt via diary,
% % so it's available for review even if the window is set to auto-close
% % (cmd /c) or the worker finishes/crashes before you can read it.
% %
% % Called via:
% %   start "SMP Worker N" cmd /k "<matlab.exe>" -batch "smp_compile_worker(N, tmp_dir)"
% 
%     log_file = fullfile(tmp_dir, sprintf('worker_%d_log.txt', worker_id));
%     diary(log_file);
%     diary on;
% 
%     try
%         fprintf('\n============================================\n');
%         fprintf('  SMP Worker %d starting\n', worker_id);
%         fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
%         fprintf('  TMP  : %s\n', tmp_dir);
%         fprintf('  LOG  : %s\n', log_file);
%         fprintf('============================================\n\n');
% 
%         % ---- Load shared config ----
%         cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
%         if ~exist(cfg_file, 'file')
%             error('Worker %d: config file not found: %s', worker_id, cfg_file);
%         end
%         loaded = load(cfg_file, 'worker_cfg');
%         cfg    = loaded.worker_cfg;
% 
%         % ---- Load this worker's group chunk ----
%         chunk_file = fullfile(tmp_dir, sprintf('chunk_%d.mat', worker_id));
%         if ~exist(chunk_file, 'file')
%             error('Worker %d: chunk file not found: %s', worker_id, chunk_file);
%         end
%         loaded2 = load(chunk_file, 'worker_groups');
%         groups  = loaded2.worker_groups;
% 
%         n_groups = numel(groups);
%         fprintf('Worker %d: %d group(s) to process\n\n', worker_id, n_groups);
% 
%         if n_groups == 0
%             fprintf('Worker %d: nothing to do.\n', worker_id);
%             write_done_flag(worker_id, tmp_dir);
%             diary off;
%             return;
%         end
% 
%         % =========================================================
%         if cfg.test_mode
%         % =========================================================
%             partial_cache.results = {};
% 
%             for g = 1:n_groups
%                 grp = groups(g);
%                 fprintf('[W%d] [%d/%d] %s  (%d file(s), ~%ds work)\n', ...
%                     worker_id, g, n_groups, grp.label, grp.n_files, grp.sleep_s);
% 
%                 fprintf('  [W%d] Simulating load...\n', worker_id);
%                 pause(grp.sleep_s * 0.4);
%                 fprintf('  [W%d] Simulating lap slice...\n', worker_id);
%                 pause(grp.sleep_s * 0.3);
%                 fprintf('  [W%d] Simulating lap stats...\n', worker_id);
%                 pause(grp.sleep_s * 0.3);
% 
%                 result = sprintf('[W%d] %s -> %d fake laps processed  [OK]', ...
%                     worker_id, grp.label, grp.n_files * 8);
%                 partial_cache.results{end+1} = result;
%                 fprintf('  %s\n\n', result);
%             end
% 
%             partial_file = fullfile(tmp_dir, sprintf('partial_%d.mat', worker_id));
%             fprintf('Worker %d: saving partial cache to:\n  %s\n', worker_id, partial_file);
%             save(partial_file, 'partial_cache', '-v7.3');
% 
%         % =========================================================
%         else
%         % =========================================================
%             % ---- diarrhea mode settings ----
%             diarrhea_mode = true;   % flush to disk frequently, default on
%             if isfield(cfg, 'diarrhea_mode'), diarrhea_mode = cfg.diarrhea_mode; end
%             flush_every_n = 1;      % groups per smp_compile_event call/flush
%             if isfield(cfg, 'flush_every_n'), flush_every_n = cfg.flush_every_n; end
%             if ~diarrhea_mode
%                 flush_every_n = n_groups;   % one big call, old behaviour
%             end
% 
%             % Build opts struct that mirrors compile_opts in the main script,
%             % using the pre-resolved min/max lap times so smp_compile_event
%             % skips its own smp_season_get call (track is left blank).
%             worker_opts = struct();
%             worker_opts.mode             = 'stream';
%             worker_opts.verbose          = true;
%             worker_opts.saveCache        = false;        % workers never save to disk
%             worker_opts.track            = cfg.track;
% 
%             % Forward all opts that process_stream needs
%             if isfield(cfg, 'max_traces'),     worker_opts.max_traces       = cfg.max_traces;     else, worker_opts.max_traces       = 5;              end
%             if isfield(cfg, 'channel_rules'),  worker_opts.channel_rules    = cfg.channel_rules;  else, worker_opts.channel_rules    = [];             end
%             if isfield(cfg, 'detect_pitlane'), worker_opts.detect_pitlane   = cfg.detect_pitlane; else, worker_opts.detect_pitlane   = false;          end
%             if isfield(cfg, 'fcy_channel'),    worker_opts.fcy_channel      = cfg.fcy_channel;    else, worker_opts.fcy_channel      = 'FCY_Flag';     end
%             if isfield(cfg, 'br2_channel'),    worker_opts.br2_channel      = cfg.br2_channel;    else, worker_opts.br2_channel      = 'BR2_Beacon_Number'; end
%             if isfield(cfg, 'br2_protocol'),   worker_opts.br2_protocol     = cfg.br2_protocol;   else, worker_opts.br2_protocol     = 'standard';     end
%             if isfield(cfg, 'beacon_check'),   worker_opts.beacon_check     = cfg.beacon_check;   else, worker_opts.beacon_check     = false;          end
%             if isfield(cfg, 'all_laps'),       worker_opts.all_laps         = cfg.all_laps;        else, worker_opts.all_laps         = false;          end
%             if isfield(cfg, 'load_all_ch'),    worker_opts.load_all_channels = cfg.load_all_ch;   end
%             if isfield(cfg, 'concat_csv_dir'), worker_opts.concat_csv_dir   = cfg.concat_csv_dir; end
%             if isfield(cfg, 'show_report'),    worker_opts.showConcatReport  = cfg.show_report;   end
%             if isfield(cfg, 'unique_fp'),      worker_opts.uniqueFingerprint = cfg.unique_fp;     end
%             if isfield(cfg, 'T_gated'),        worker_opts.T_gated           = cfg.T_gated;       end
%             if isfield(cfg, 'l180_mode'),      worker_opts.l180_mode         = cfg.l180_mode;      else, worker_opts.l180_mode = 'drop_duplicate'; end
% 
%             % ---- Process in batches, flushing + clearing after each ----
%             n_batches = ceil(n_groups / flush_every_n);
%             fprintf('Worker %d: %d batch(es) of up to %d group(s) each (diarrhea_mode=%d)\n\n', ...
%                 worker_id, n_batches, flush_every_n, diarrhea_mode);
% 
%             for b = 1:n_batches
%                 i_start = (b-1)*flush_every_n + 1;
%                 i_end   = min(b*flush_every_n, n_groups);
%                 batch_groups = groups(i_start:i_end);
% 
%                 fprintf('[W%d] --- Batch %d/%d: group(s) %d-%d ---\n', ...
%                     worker_id, b, n_batches, i_start, i_end);
% 
%                 worker_opts.groups = batch_groups;   % bypass scan/diff/group steps in smp_compile_event
% 
%                 try
%                     partial_cache = smp_compile_event('', {}, cfg.channels_to_extract, ...
%                                         cfg.season, cfg.driver_map, cfg.alias, worker_opts);
%                 catch ME
%                     fprintf('  [W%d] [ERROR] Batch %d failed: %s\n', worker_id, b, ME.message);
%                     fprintf('  [W%d] %s\n\n', worker_id, ME.getReport('basic'));
%                     continue;   % skip flushing this batch; next batch still attempted
%                 end
% 
%                 flush_partial_cache(partial_cache, worker_id, b, tmp_dir);
% 
%                 clear partial_cache;   % release before next batch
%             end
%         end
% 
%         write_done_flag(worker_id, tmp_dir);
% 
%         fprintf('\n============================================\n');
%         fprintf('  Worker %d COMPLETE  [%s]\n', worker_id, datestr(now,'HH:MM:SS'));
%         fprintf('============================================\n');
% 
%         diary off;
% 
%     catch ME_outer
%         fprintf('\n============================================\n');
%         fprintf('  Worker %d FATAL ERROR  [%s]\n', worker_id, datestr(now,'HH:MM:SS'));
%         fprintf('============================================\n');
%         fprintf('%s\n', ME_outer.getReport('extended'));
%         diary off;
%         rethrow(ME_outer);
%     end
% end
% 
function smp_compile_worker(job_id, tmp_dir)
% SMP_COMPILE_WORKER  Runs in a spawned MATLAB process for ONE group.
%
% One job = one group = one process. Process exits after this single
% group finishes, so the OS fully reclaims its memory — no accumulation
% across groups is possible, since nothing lives long enough to accumulate.
%
% Called via:
%   start "SMP Job N" cmd /c "<matlab.exe>" -batch "smp_compile_worker(N, tmp_dir)"

log_file = fullfile(tmp_dir, sprintf('worker_job%d_log.txt', job_id));
diary(log_file);
diary on;

try
    fprintf('\n============================================\n');
    fprintf('  SMP Job %d starting\n', job_id);
    fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('  TMP  : %s\n', tmp_dir);
    fprintf('============================================\n\n');

    cfg_file = fullfile(tmp_dir, 'worker_cfg.mat');
    if ~exist(cfg_file, 'file')
        error('Job %d: config file not found: %s', job_id, cfg_file);
    end
    loaded = load(cfg_file, 'worker_cfg');
    cfg    = loaded.worker_cfg;

    job_file = fullfile(tmp_dir, sprintf('job_%d.mat', job_id));
    if ~exist(job_file, 'file')
        error('Job %d: job file not found: %s', job_id, job_file);
    end
    loaded2   = load(job_file, 'job_group');
    job_group = loaded2.job_group;

    fprintf('Job %d: %s | %s | %s | %d file(s)\n\n', ...
        job_id, job_group.team_acronym, job_group.driver, job_group.session, job_group.n_files);

    worker_opts = struct();
    worker_opts.mode      = 'stream';
    worker_opts.verbose   = true;
    worker_opts.saveCache = false;
    worker_opts.track     = cfg.track;
    worker_opts.groups    = job_group;   % single group — bypass scan/diff/group steps

    if isfield(cfg, 'max_traces'),     worker_opts.max_traces       = cfg.max_traces;     else, worker_opts.max_traces       = 5;              end
    if isfield(cfg, 'channel_rules'),  worker_opts.channel_rules    = cfg.channel_rules;  else, worker_opts.channel_rules    = [];             end
    if isfield(cfg, 'detect_pitlane'), worker_opts.detect_pitlane   = cfg.detect_pitlane; else, worker_opts.detect_pitlane   = false;          end
    if isfield(cfg, 'fcy_channel'),    worker_opts.fcy_channel      = cfg.fcy_channel;    else, worker_opts.fcy_channel      = 'FCY_Flag';     end
    if isfield(cfg, 'br2_channel'),    worker_opts.br2_channel      = cfg.br2_channel;    else, worker_opts.br2_channel      = 'BR2_Beacon_Number'; end
    if isfield(cfg, 'br2_protocol'),   worker_opts.br2_protocol     = cfg.br2_protocol;   else, worker_opts.br2_protocol     = 'standard';     end
    if isfield(cfg, 'beacon_check'),   worker_opts.beacon_check     = cfg.beacon_check;   else, worker_opts.beacon_check     = false;          end
    if isfield(cfg, 'all_laps'),       worker_opts.all_laps         = cfg.all_laps;        else, worker_opts.all_laps         = false;          end
    if isfield(cfg, 'load_all_ch'),    worker_opts.load_all_channels = cfg.load_all_ch;   end
    if isfield(cfg, 'concat_csv_dir'), worker_opts.concat_csv_dir   = cfg.concat_csv_dir; end
    if isfield(cfg, 'show_report'),    worker_opts.showConcatReport  = cfg.show_report;   end
    if isfield(cfg, 'unique_fp'),      worker_opts.uniqueFingerprint = cfg.unique_fp;     end
    if isfield(cfg, 'T_gated'),        worker_opts.T_gated           = cfg.T_gated;       end
    if isfield(cfg, 'l180_mode'),      worker_opts.l180_mode         = cfg.l180_mode;      else, worker_opts.l180_mode = 'drop_duplicate'; end
    if isfield(cfg, 'channel_ops_map'), worker_opts.channel_ops_map = cfg.channel_ops_map; end
    partial_cache = smp_compile_event('', {}, cfg.channels_to_extract, ...
        cfg.season, cfg.driver_map, cfg.alias, worker_opts);

    partial_file = fullfile(tmp_dir, sprintf('partial_job%d.mat', job_id));
    fprintf('Job %d: saving -> %s\n', job_id, partial_file);
    save(partial_file, 'partial_cache', '-v7');

    flag_file = fullfile(tmp_dir, sprintf('done_job%d.flag', job_id));
    fid = fopen(flag_file, 'w');
    fprintf(fid, 'done at %s', datestr(now));
    fclose(fid);

    fprintf('\n============================================\n');
    fprintf('  Job %d COMPLETE  [%s]\n', job_id, datestr(now,'HH:MM:SS'));
    fprintf('============================================\n');

    diary off;
    exit(0);
catch ME
    fprintf('\n============================================\n');
    fprintf('  Job %d FATAL ERROR  [%s]\n', job_id, datestr(now,'HH:MM:SS'));
    fprintf('============================================\n');
    fprintf('%s\n', ME.getReport('extended'));
    diary off;
    exit(1);    
    rethrow(ME);
end
end
% ======================================================================= %
function flush_partial_cache(partial_cache, worker_id, flush_id, tmp_dir)
% FLUSH_PARTIAL_CACHE  Save one batch's partial_cache to disk.
% Tries lightweight -v7 first (flush chunks are small); falls back to
% -v7.3 only if that fails. If BOTH fail, errors out loudly instead of
% letting the worker report a false success via write_done_flag.
    partial_file = fullfile(tmp_dir, sprintf('partial_%d_%d.mat', worker_id, flush_id));
    fprintf('  [W%d] [FLUSH %d] saving %d manifest row(s) -> %s\n', ...
        worker_id, flush_id, height(partial_cache.manifest), partial_file);

    save_ok = false;
    try
        save(partial_file, 'partial_cache', '-v7');
        save_ok = true;
    catch ME1
        fprintf('  [W%d] [WARN] -v7 save failed: %s — retrying with -v7.3...\n', worker_id, ME1.message);
        try
            save(partial_file, 'partial_cache', '-v7.3');
            save_ok = true;
        catch ME2
            fprintf('  [W%d] [ERROR] -v7.3 save also failed: %s\n', worker_id, ME2.message);
        end
    end

    if ~save_ok
        error('smp_compile_worker:flush_failed', ...
            'Worker %d: failed to save flush %d after two attempts — aborting worker (no done flag written).', ...
            worker_id, flush_id);
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

% ======================================================================= %
% function flush_partial_cache(partial_cache, worker_id, flush_id, tmp_dir)
% % FLUSH_PARTIAL_CACHE  Save one batch's partial_cache to disk.
% % Tries lightweight -v7 first (flush chunks are small); falls back to
% % -v7.3 only if that fails. If BOTH fail, errors out loudly instead of
% % letting the worker report a false success via write_done_flag.
%     partial_file = fullfile(tmp_dir, sprintf('partial_%d_%d.mat', worker_id, flush_id));
%     fprintf('  [W%d] [FLUSH %d] saving %d manifest row(s) -> %s\n', ...
%         worker_id, flush_id, height(partial_cache.manifest), partial_file);
% 
%     save_ok = false;
%     try
%         save(partial_file, 'partial_cache', '-v7');
%         save_ok = true;
%     catch ME1
%         fprintf('  [W%d] [WARN] -v7 save failed: %s — retrying with -v7.3...\n', worker_id, ME1.message);
%         try
%             save(partial_file, 'partial_cache', '-v7.3');
%             save_ok = true;
%         catch ME2
%             fprintf('  [W%d] [ERROR] -v7.3 save also failed: %s\n', worker_id, ME2.message);
%         end
%     end
% 
%     if ~save_ok
%         error('smp_compile_worker:flush_failed', ...
%             'Worker %d: failed to save flush %d after two attempts — aborting worker (no done flag written).', ...
%             worker_id, flush_id);
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