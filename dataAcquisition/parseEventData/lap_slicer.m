% function laps = lap_slicer(session, opts)
% % LAP_SLICER  Slice a MoTeC session struct into per-lap channel data.
% %
% % The session struct is expected to have the form produced by motec_ld_reader,
% % where each field is a channel:
% %   session.ChannelName.data        (Nx1 double)
% %   session.ChannelName.time        (Nx1 double, seconds)
% %   session.ChannelName.units       (char)
% %   session.ChannelName.sample_rate (double, Hz)
% %   session.ChannelName.raw_name    (char)
% %
% % Lap boundaries are detected from the Lap_Number channel.
% % Lap duration is read from the Lap_Time channel (1Hz, seconds) using the
% % mode of values within the lap window — avoids picking up the previous
% % lap's value at the start or a late write at the end.
% % Falls back to boundary difference if Lap_Time channel is not found.
% %
% % Usage:
% %   laps = lap_slicer(session)
% %   laps = lap_slicer(session, opts)
% %
% % Options (all optional):
% %   opts.lap_channel      Channel name for lap number   (default: 'Lap_Number')
% %   opts.min_lap_time     Minimum valid lap time in s   (default: 10)
% %   opts.max_lap_time     Maximum valid lap time in s   (default: 600)
% %   opts.lap_range        [first last] lap numbers to keep, e.g. [2 20]
% %                         (default: all laps)
% %   opts.exclude_laps     Array of lap numbers to exclude, e.g. [1 15]
% %                         (default: [])
% %   opts.verbose          Print lap summary             (default: true)
% %
% % Returns:
% %   laps    Struct array (one element per valid lap).
% %           laps(k).lap_number      (integer)
% %           laps(k).lap_time        (seconds)
% %           laps(k).t_start         (session time at lap start, s)
% %           laps(k).t_end           (session time at lap end, s)
% %           laps(k).channels        Struct of sliced channels, same field
% %                                   names as the input session.
% %           laps(k).channels.X.data      Sliced data for that lap
% %           laps(k).channels.X.time      Lap-relative time (starts at 0, s)
% %           laps(k).channels.X.time_abs  Absolute session time
% %           laps(k).channels.X.units, .sample_rate, .raw_name  (copied)
% 
%     % ------------------------------------------------------------------
%     %  Defaults
%     % ------------------------------------------------------------------
%     if nargin < 2, opts = struct(); end
%     lap_ch       = get_opt(opts, 'lap_channel',  'Lap_Number');
%     min_lap_time = get_opt(opts, 'min_lap_time', 10);
%     max_lap_time = get_opt(opts, 'max_lap_time', 600);
%     lap_range    = get_opt(opts, 'lap_range',    []);
%     excl_laps    = get_opt(opts, 'exclude_laps', []);
%     verbose      = get_opt(opts, 'verbose',      true);
% 
%     % ------------------------------------------------------------------
%     %  Find the Lap_Number channel
%     % ------------------------------------------------------------------
%     ch_names  = fieldnames(session);
%     lap_field = find_channel(session, lap_ch, ch_names);
%     if isempty(lap_field)
%         error('lap_slicer: cannot find lap channel "%s".\nAvailable channels:\n%s', ...
%               lap_ch, strjoin(ch_names, ', '));
%     end
% 
%     lap_num_data  = session.(lap_field).data;
%     lap_num_time  = session.(lap_field).time;
%     t_session_end = lap_num_time(end);
% 
%     % ------------------------------------------------------------------
%     %  Find Lap_Time channel (1Hz, seconds, holds completed lap time)
%     %  Mode of values within the lap window gives the stable lap time —
%     %  avoids the previous lap's value at the start and any late write
%     %  at the end.
%     % ------------------------------------------------------------------
%     LAP_TIME_CANDIDATES = {'Lap_Time', 'Lap Time', 'LapTime', 'Lap_Timer'};
%     lt_field = '';
%     for i = 1:numel(LAP_TIME_CANDIDATES)
%         lt_field = find_channel(session, LAP_TIME_CANDIDATES{i}, ch_names);
%         if ~isempty(lt_field), break; end
%     end
% 
%     if verbose
%         if ~isempty(lt_field)
%             fprintf('  [lap_slicer] Lap time channel: %s\n', lt_field);
%         else
%             fprintf('  [lap_slicer] No Lap_Time channel found — using boundary difference.\n');
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Detect lap boundary timestamps (two-pass build)
%     %  Pass 1: t_start of lap N = first sample time where Lap_Number == N
%     %  Pass 2: t_end of lap N   = t_start of lap N+1 (or session end)
%     % ------------------------------------------------------------------
%     lap_nums = unique(round(lap_num_data));
%     lap_nums = lap_nums(lap_nums > -1);   % keep lap 0+ (lap 0 = outlap)
% 
%     boundaries = NaN(numel(lap_nums), 2);
% 
%     for k = 1:numel(lap_nums)
%         n        = lap_nums(k);
%         mask     = round(lap_num_data) == n;
%         t_in_lap = lap_num_time(mask);
%         if ~isempty(t_in_lap)
%             boundaries(k, 1) = t_in_lap(1);
%         end
%     end
% 
%     for k = 1:numel(lap_nums)
%         if isnan(boundaries(k, 1)), continue; end
%         if k < numel(lap_nums) && ~isnan(boundaries(k+1, 1))
%             boundaries(k, 2) = boundaries(k+1, 1);
%         else
%             boundaries(k, 2) = t_session_end;
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Filter — coarse boundary duration, range, exclusion, NaN
%     % ------------------------------------------------------------------
%     durations  = boundaries(:,2) - boundaries(:,1);
%     valid_mask = (durations >= min_lap_time) & (durations <= max_lap_time);
%     valid_mask = valid_mask & ~any(isnan(boundaries), 2);
% 
%     if ~isempty(lap_range)
%         valid_mask = valid_mask & ...
%             (lap_nums(:) >= lap_range(1)) & (lap_nums(:) <= lap_range(2));
%     end
% 
%     if ~isempty(excl_laps)
%         for k = 1:numel(excl_laps)
%             valid_mask = valid_mask & (lap_nums(:) ~= excl_laps(k));
%         end
%     end
% 
%     lap_nums_valid   = lap_nums(valid_mask);
%     boundaries_valid = boundaries(valid_mask, :);
%     n_valid          = numel(lap_nums_valid);
% 
%     if verbose
%         fprintf('\n=== Lap Slicer ===\n');
%         fprintf('Total lap numbers detected : %d\n', numel(lap_nums));
%         fprintf('Valid laps after filtering  : %d\n', n_valid);
%         fprintf('%-8s  %-12s  %-12s  %-12s\n', 'Lap', 't_start(s)', 't_end(s)', 'Duration(s)');
%         fprintf('%s\n', repmat('-', 1, 48));
%     end
% 
%     % ------------------------------------------------------------------
%     %  Slice all channels for each valid lap
%     % ------------------------------------------------------------------
%     LOOKBACK_S = 1.5;   % look back before t_start to capture pre-beacon data
% 
%     laps = struct('lap_number', cell(1, n_valid), ...
%                   'lap_time',   cell(1, n_valid), ...
%                   't_start',    cell(1, n_valid), ...
%                   't_end',      cell(1, n_valid), ...
%                   'channels',   cell(1, n_valid));
% 
%     for k = 1:n_valid
%         lap_n = lap_nums_valid(k);
%         t_s   = boundaries_valid(k, 1);
%         t_e   = boundaries_valid(k, 2);
% 
%         % ---- Lap time from mode of Lap_Time channel ----
%         % Lap_Time is 1Hz and holds the completed lap time. The window
%         % contains the previous lap's value at the start and may catch
%         % the next lap's value at the end — mode picks the stable value.
%         dur = t_e - t_s;   % fallback
%         if ~isempty(lt_field)
%             lt_data = session.(lt_field).data;
%             lt_time = session.(lt_field).time;
%             lt_mask = lt_time >= t_s & lt_time < t_e;
%             lt_vals = lt_data(lt_mask);
%             lt_vals = lt_vals(isfinite(lt_vals) & lt_vals > 0);
%             if ~isempty(lt_vals)
%                 % Take the most frequent value directly — avoids bin centre arithmetic
%                 [~, ~, ic] = unique(lt_vals);
%                 counts      = accumarray(ic, 1);
%                 [~, idx]    = max(counts);
%                 dur         = lt_vals(find(ic == idx, 1));
%                 laps(k).lap_time   = dur;
%             else
%                 laps(k).lap_time   = dur * 1.1;
%             end
%         end
% 
%         laps(k).lap_number = lap_n;
%         laps(k).lap_time   = dur;
%         laps(k).t_start    = t_s;
%         laps(k).t_end      = t_e;
%         laps(k).channels   = struct();
% 
%         % ---- Slice all channels ----
%         for c = 1:numel(ch_names)
%             fn  = ch_names{c};
%             ch  = session.(fn);
%             t   = ch.time;
% 
%             msk = t >= (t_s - LOOKBACK_S) & t < t_e;
% 
%             sliced          = ch;
%             sliced.data     = ch.data(msk);
%             sliced.time_abs = t(msk);
%             sliced.time     = t(msk) - t_s;   % lap-relative; negative = before beacon
% 
%             laps(k).channels.(fn) = sliced;
%         end
% 
%         if verbose
%             fprintf('  Lap %-4d  t_start=%8.2f  t_end=%8.2f  dur=%8.3f s\n', ...
%                 lap_n, t_s, t_e, dur);
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Stage 2 — drop laps whose Lap_Time-derived duration falls outside
%     %  the accurate min/max filter
%     % ------------------------------------------------------------------
%     keep = true(1, numel(laps));
%     for k = 1:numel(laps)
%         lt = laps(k).lap_time;
%         if lt < min_lap_time || lt > max_lap_time
%             keep(k) = false;
%             if verbose
%                 fprintf('  [FILTER] Lap %d dropped: %.3fs outside [%.1f, %.1f]\n', ...
%                     laps(k).lap_number, lt, min_lap_time, max_lap_time);
%             end
%         end
%     end
%     laps = laps(keep);
% 
%     if verbose
%         fprintf('\nSliced %d valid laps.\n\n', numel(laps));
%     end
% 
%     % Enrich all channels with .dist field
%     laps = enrich_with_distance(laps, verbose);
% end
% 
% 
% % ======================================================================= %
% function laps = enrich_with_distance(laps, verbose)
% % ENRICH_WITH_DISTANCE  Add .dist to every channel and resample onto
% %                       the master distance channel time grid.
% %
% % Distance source priority:
% %   1. Lap_Distance  — resets to 0 at beacon, most accurate alignment
% %   2. Corr_Dist     — corrected cumulative distance
% %   3. Odometer      — cumulative, zeroed at lap start
% %   4. Ground_Speed  — integrated as last resort
% 
%     DIST_CANDIDATES  = {'Lap_Distance', 'Corr_Dist', 'Odometer'};
%     SPEED_CANDIDATES = {'Ground_Speed'};
%     USE_SPEED_FIRST  = false;
% 
%     if isempty(laps), return; end
% 
%     for k = 1:numel(laps)
%         ch_names = fieldnames(laps(k).channels);
% 
%         % ---- Find master distance channel ----
%         dist_field      = '';
%         dist_source     = '';
%         use_integration = false;
% 
%         if USE_SPEED_FIRST
%             for i = 1:numel(SPEED_CANDIDATES)
%                 f = find_ch_field_local(laps(k).channels, SPEED_CANDIDATES{i});
%                 if ~isempty(f)
%                     dist_field      = f;
%                     dist_source     = SPEED_CANDIDATES{i};
%                     use_integration = true;
%                     break;
%                 end
%             end
%         end
% 
%         if isempty(dist_field)
%             for i = 1:numel(DIST_CANDIDATES)
%                 f = find_ch_field_local(laps(k).channels, DIST_CANDIDATES{i});
%                 if ~isempty(f)
%                     dist_field  = f;
%                     dist_source = DIST_CANDIDATES{i};
%                     break;
%                 end
%             end
%         end
% 
%         % Last resort — speed integration
%         if isempty(dist_field)
%             for i = 1:numel(SPEED_CANDIDATES)
%                 f = find_ch_field_local(laps(k).channels, SPEED_CANDIDATES{i});
%                 if ~isempty(f)
%                     dist_field      = f;
%                     dist_source     = SPEED_CANDIDATES{i};
%                     use_integration = true;
%                     break;
%                 end
%             end
%         end
% 
%         if isempty(dist_field)
%             if verbose
%                 fprintf('  [WARN] Lap %d: no distance or speed channel — .dist not added.\n', ...
%                     laps(k).lap_number);
%             end
%             continue;
%         end
% 
%         % ---- Build master distance vector ----
%         dist_ch  = laps(k).channels.(dist_field);
%         t_master = dist_ch.time(:);
%         d_raw    = dist_ch.data(:);
% 
%         if use_integration
%             zero_idx = find(t_master >= 0, 1);
%             if isempty(zero_idx), zero_idx = 1; end
%             speed_ms = max(d_raw, 0) / 3.6;
%             d_master = cumtrapz(t_master, speed_ms);
%             d_master = d_master - d_master(zero_idx);
%             if verbose && k == 1
%                 fprintf('  [INFO] Distance: integrating %s (%.1f Hz)\n', ...
%                     dist_source, laps(k).channels.(dist_field).sample_rate);
%             end
%         else
%             if strcmpi(dist_source, 'Lap_Distance')
%                 zero_idx = find(t_master >= 0, 1);
%                 if isempty(zero_idx), zero_idx = 1; end
%                 d_master = d_raw - d_raw(zero_idx);
%             else
%                 d_master = d_raw - d_raw(1);
%             end
%             if verbose && k == 1
%                 fprintf('  [INFO] Distance source: %s\n', dist_source);
%             end
%         end
% 
%         % Enforce monotonically increasing distance
%         mono_mask = [true; diff(d_master) > 0];
%         t_master  = t_master(mono_mask);
%         d_master  = d_master(mono_mask);
% 
%         if numel(t_master) < 2
%             if verbose
%                 fprintf('  [WARN] Lap %d: distance channel has < 2 monotonic points.\n', ...
%                     laps(k).lap_number);
%             end
%             continue;
%         end
% 
%         % ---- Resample all channels onto master time grid ----
%         for c = 1:numel(ch_names)
%             fn   = ch_names{c};
%             ch   = laps(k).channels.(fn);
%             t_ch = ch.time(:);
%             d_ch = ch.data(:);
% 
%             if numel(t_ch) < 2
%                 laps(k).channels.(fn).dist = NaN(size(d_ch));
%                 continue;
%             end
% 
%             [t_ch_u, ia] = unique(t_ch, 'stable');
%             d_ch_u = d_ch(ia);
% 
%             t_lo = max(t_master(1),  t_ch_u(1));
%             t_hi = min(t_master(end), t_ch_u(end));
% 
%             data_full = NaN(numel(t_master), 1);
% 
%             if t_lo < t_hi
%                 in_range = t_master >= t_lo & t_master <= t_hi;
%                 data_full(in_range) = interp1(t_ch_u, d_ch_u, ...
%                     t_master(in_range), 'linear', NaN);
%             end
% 
%             laps(k).channels.(fn).data = data_full;
%             laps(k).channels.(fn).time = t_master;
%             laps(k).channels.(fn).dist = d_master;
%         end
%     end
% end
% 
% 
% % ======================================================================= %
% function field = find_ch_field_local(channels_struct, name)
%     if isfield(channels_struct, name), field = name; return; end
%     san = regexprep(name, '[^a-zA-Z0-9_]', '_');
%     if isfield(channels_struct, san),  field = san;  return; end
%     all_f = fieldnames(channels_struct);
%     for i = 1:numel(all_f)
%         if strcmpi(all_f{i}, name) || strcmpi(all_f{i}, san)
%             field = all_f{i};
%             return;
%         end
%     end
%     field = '';
% end
% 
% 
% % ======================================================================= %
% function field = find_channel(session, name, ch_names)
%     if isfield(session, name), field = name; return; end
%     san = regexprep(name, '[^a-zA-Z0-9_]', '_');
%     if isfield(session, san),  field = san;  return; end
%     for i = 1:numel(ch_names)
%         if strcmpi(ch_names{i}, name) || strcmpi(ch_names{i}, san)
%             field = ch_names{i};
%             return;
%         end
%     end
%     field = '';
% end
% 
% 
% % ======================================================================= %
% function val = get_opt(opts, name, default)
%     if isfield(opts, name) && ~isempty(opts.(name))
%         val = opts.(name);
%     else
%         val = default;
%     end
% end

function laps = lap_slicer(session, opts)
% LAP_SLICER  Slice a MoTeC session struct into per-lap channel data.
%
% Lap boundaries are detected from Lap_Number (1Hz).
%
% Lap duration uses a two-source end-of-lap strategy:
%
%   PRIMARY:   Running_Lap_Time — last value before the beacon fires
%              (sampled in the 1s window ending at t_end). This channel
%              counts up from 0 each lap so its final value = elapsed time.
%              Preferred because it is high-frequency (10Hz typical).
%
%   SECONDARY: Lap_Time — last value written in the 2s window ending at
%              t_end. The ECU writes the completed lap time at the beacon.
%              Used when RLT is absent or disagrees by more than 1s.
%
%   LAST RESORT: t_end - t_start from Lap_Number boundaries.
%                Integer resolution — only used if both channels are absent.
%
% Negative .time values on channels are from the pre-beacon lookback window
% (LOOKBACK_S). These are intentional — they capture data before the beacon
% for distance enrichment. Downstream code should treat time < 0 as
% pre-lap context, not as part of the timed lap.
%
% Usage:
%   laps = lap_slicer(session)
%   laps = lap_slicer(session, opts)
%
% Options (all optional):
%   opts.lap_channel      Lap number channel       (default: 'Lap_Number')
%   opts.min_lap_time     Minimum lap time (s)     (default: 10)
%   opts.max_lap_time     Maximum lap time (s)     (default: 600)
%   opts.lap_range        [first last] to keep     (default: all)
%   opts.exclude_laps     Lap numbers to exclude   (default: [])
%   opts.verbose          Print summary            (default: true)
%
% Output — laps(k):
%   .lap_number       integer
%   .lap_time         seconds (best available precision)
%   .lap_time_source  'Running_Lap_Time' | 'Lap_Time' | 'boundary'
%   .t_start          session time at lap start (s)
%   .t_end            session time at lap end (s)
%   .channels.(X)
%       .data         sliced values
%       .time         lap-relative time (s); 0 = beacon; negative = lookback
%       .time_abs     absolute session time (s)
%       .dist         distance (m) — added by enrich_with_distance
%       .units / .sample_rate / .raw_name  (copied)

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 2, opts = struct(); end
    lap_ch       = get_opt(opts, 'lap_channel',  'Lap_Number');
    min_lap_time = get_opt(opts, 'min_lap_time', 10);
    max_lap_time = get_opt(opts, 'max_lap_time', 600);
    lap_range    = get_opt(opts, 'lap_range',    []);
    excl_laps    = get_opt(opts, 'exclude_laps', []);
    verbose      = get_opt(opts, 'verbose',      true);
    verbose = 1;
    ch_names = fieldnames(session);

    % ------------------------------------------------------------------
    %  1. Lap_Number channel
    % ------------------------------------------------------------------
    lap_field = find_channel(session, lap_ch, ch_names);
    if isempty(lap_field)
        error('lap_slicer: cannot find lap channel "%s".\nAvailable: %s', ...
              lap_ch, strjoin(ch_names, ', '));
    end
    lap_num_data  = session.(lap_field).data;
    lap_num_time  = session.(lap_field).time;
    t_session_end = lap_num_time(end);

    % ------------------------------------------------------------------
    %  2. Running_Lap_Time channel (PRIMARY precision source)
    %     Counts up from 0 at beacon — last value before next beacon
    %     is the elapsed lap time.
    % ------------------------------------------------------------------
    RLT_CANDIDATES = {'Running_Lap_Time', 'Run_Lap_Time', 'Running_Lap_Timer'};
    rlt_field = '';
    for i = 1:numel(RLT_CANDIDATES)
        f = find_channel(session, RLT_CANDIDATES{i}, ch_names);
        if ~isempty(f), rlt_field = f; break; end
    end

    % Auto-detect ms vs s: median value of a typical lap should be ~half
    % the lap time in seconds. If median >> 600 it is almost certainly ms.
    rlt_scale = 1.0;
    if ~isempty(rlt_field)
        rlt_raw = session.(rlt_field).data;
        pos_vals = rlt_raw(isfinite(rlt_raw) & rlt_raw > 0);
        if ~isempty(pos_vals) && median(pos_vals) > 1000
            rlt_scale = 1 / 1000;
        end
    end

    % ------------------------------------------------------------------
    %  3. Lap_Time channel (SECONDARY precision source)
    %     1Hz, written by ECU at beacon crossing with completed lap time.
    %     Read the last value in a 2s window ending at t_end.
    % ------------------------------------------------------------------
    LT_CANDIDATES = {'Lap_Time', 'Lap Time', 'LapTime', 'Lap_Timer'};
    lt_field = '';
    for i = 1:numel(LT_CANDIDATES)
        f = find_channel(session, LT_CANDIDATES{i}, ch_names);
        if ~isempty(f), lt_field = f; break; end
    end

    if verbose
        fprintf('\n=== Lap Slicer ===\n');
        if ~isempty(rlt_field)
            fprintf('  Primary   (Running_Lap_Time): %s  %.0fHz  scale=%.4f\n', ...
                rlt_field, session.(rlt_field).sample_rate, rlt_scale);
        else
            fprintf('  Primary   (Running_Lap_Time): NOT FOUND\n');
        end
        if ~isempty(lt_field)
            fprintf('  Secondary (Lap_Time):         %s  %.0fHz\n', ...
                lt_field, session.(lt_field).sample_rate);
        else
            fprintf('  Secondary (Lap_Time):         NOT FOUND\n');
        end
        if isempty(rlt_field) && isempty(lt_field)
            fprintf('  WARNING: no precision source — lap times will be integer resolution\n');
        end
    end

    % ------------------------------------------------------------------
    %  4. Detect lap boundaries from Lap_Number (two-pass build)
    %     Pass 1: t_start of lap N = first sample time where Lap_Number == N
    %     Pass 2: t_end   of lap N = t_start of lap N+1 (or session end)
    % ------------------------------------------------------------------
    lap_nums = unique(round(lap_num_data));
    lap_nums = lap_nums(lap_nums > -1);   % include lap 0 (outlap)

    boundaries = NaN(numel(lap_nums), 2);
    for k = 1:numel(lap_nums)
        mask     = round(lap_num_data) == lap_nums(k);
        t_in_lap = lap_num_time(mask);
        if ~isempty(t_in_lap)
            boundaries(k, 1) = t_in_lap(1);
        end
    end
    for k = 1:numel(lap_nums)
        if isnan(boundaries(k, 1)), continue; end
        if k < numel(lap_nums) && ~isnan(boundaries(k+1, 1))
            boundaries(k, 2) = boundaries(k+1, 1);
        else
            boundaries(k, 2) = t_session_end;
        end
    end

    % ------------------------------------------------------------------
    %  5. Coarse filter on Lap_Number boundary durations
    %     10% tolerance so precision source can correct edge cases that
    %     integer-snapped boundaries misrepresent slightly.
    % ------------------------------------------------------------------
    COARSE_TOL = 0.10;
    durations  = boundaries(:,2) - boundaries(:,1);
    valid_mask = (durations >= min_lap_time * (1 - COARSE_TOL)) & ...
                 (durations <= max_lap_time * (1 + COARSE_TOL));
    valid_mask = valid_mask & ~any(isnan(boundaries), 2);

    if ~isempty(lap_range)
        valid_mask = valid_mask & ...
            (lap_nums(:) >= lap_range(1)) & (lap_nums(:) <= lap_range(2));
    end
    if ~isempty(excl_laps)
        for k = 1:numel(excl_laps)
            valid_mask = valid_mask & (lap_nums(:) ~= excl_laps(k));
        end
    end

    lap_nums_valid   = lap_nums(valid_mask);
    boundaries_valid = boundaries(valid_mask, :);
    n_valid          = numel(lap_nums_valid);

    if verbose
        fprintf('\n  Lap numbers detected : %d\n', numel(lap_nums));
        fprintf('  After coarse filter  : %d\n', n_valid);
        fprintf('\n  %-6s  %-10s  %-10s  %-12s  %s\n', ...
            'Lap', 't_start', 't_end', 'Duration(s)', 'Source');
        fprintf('  %s\n', repmat('-', 1, 52));
    end

    % ------------------------------------------------------------------
    %  6. Slice channels + resolve precise lap time for each lap
    % ------------------------------------------------------------------
    LOOKBACK_S = 1.5;   % pre-beacon window for distance enrichment

    laps = struct('lap_number',       cell(1, n_valid), ...
                  'lap_time',         cell(1, n_valid), ...
                  'lap_time_source',  cell(1, n_valid), ...
                  't_start',          cell(1, n_valid), ...
                  't_end',            cell(1, n_valid), ...
                  'channels',         cell(1, n_valid));

    for k = 1:n_valid
        lap_n = lap_nums_valid(k);
        t_s   = boundaries_valid(k, 1);
        t_e   = boundaries_valid(k, 2);

        % ---- Resolve lap time from end-of-lap channel values ----
        dur        = t_e - t_s;   % last resort
        dur_source = 'boundary';

        % -- Secondary: Lap_Time last value in 2s window before t_e --
        % ECU writes completed lap time at the beacon — read the last
        % sample written before/at t_e within a 2s lookback.
        lt_dur = NaN;
        if ~isempty(lt_field)
            lt_data  = session.(lt_field).data;
            lt_time  = session.(lt_field).time;
            end_mask = lt_time >= (t_e - 2.0) & lt_time <= (t_e + 0.5);
            end_vals = lt_data(end_mask);
            end_vals = end_vals(isfinite(end_vals) & end_vals > 0);
            if ~isempty(end_vals)
                lt_dur     = end_vals(end);
                dur        = lt_dur;
                dur_source = 'Lap_Time';
            end
        end

        % -- Primary: Running_Lap_Time last value before beacon fires --
        % Take the last RLT sample in a 1s window ending at t_e.
        % This is the final elapsed value before the counter resets.
        if ~isempty(rlt_field)
            rlt_data = session.(rlt_field).data * rlt_scale;
            rlt_time = session.(rlt_field).time;
            end_mask = rlt_time >= (t_e - 1.0) & rlt_time < t_e;
            rlt_end  = rlt_data(end_mask);
            rlt_end  = rlt_end(isfinite(rlt_end) & rlt_end > 0);
            if ~isempty(rlt_end)
                rlt_dur = rlt_end(end);
                % Accept RLT if it agrees with Lap_Time within 1s,
                % or if Lap_Time was not found.
                if isnan(lt_dur) || abs(rlt_dur - lt_dur) < 1.0
                    dur        = rlt_dur;
                    dur_source = 'Running_Lap_Time';
                end
            end
        end

        laps(k).lap_number      = lap_n;
        laps(k).lap_time        = dur;
        laps(k).lap_time_source = dur_source;
        laps(k).t_start         = t_s;
        laps(k).t_end           = t_e;
        laps(k).channels        = struct();

        % ---- Slice all channels with pre-beacon lookback ----
        for c = 1:numel(ch_names)
            fn  = ch_names{c};
            ch  = session.(fn);
            t   = ch.time;

            msk = t >= (t_s - LOOKBACK_S) & t < t_e;

            sliced          = ch;
            sliced.data     = ch.data(msk);
            sliced.time_abs = t(msk);
            sliced.time     = t(msk) - t_s;  % 0 = beacon; negative = lookback

            laps(k).channels.(fn) = sliced;
        end

        if verbose
            fprintf('  %-6d  %-10.2f  %-10.2f  %-12.3f  %s\n', ...
                lap_n, t_s, t_e, dur, dur_source);
        end
    end

    % ------------------------------------------------------------------
    %  7. Accurate filter — drop laps whose resolved lap time falls
    %     outside min/max. This catches cases where coarse tolerance
    %     passed a lap that the precision source correctly rejects.
    % ------------------------------------------------------------------
    keep = true(1, numel(laps));
    for k = 1:numel(laps)
        lt = laps(k).lap_time;
        if lt < min_lap_time || lt > max_lap_time
            keep(k) = false;
            if verbose
                fprintf('  [FILTER] Lap %d dropped: %.3fs outside [%.1f, %.1f]  (source: %s)\n', ...
                    laps(k).lap_number, lt, min_lap_time, max_lap_time, ...
                    laps(k).lap_time_source);
            end
        end
    end
    laps = laps(keep);

    if verbose
        fprintf('\n  Sliced %d valid laps.\n\n', numel(laps));
    end

    % ------------------------------------------------------------------
    %  8. Enrich all channels with .dist field
    % ------------------------------------------------------------------
    laps = enrich_with_distance(laps, verbose);
end


% ======================================================================= %
function laps = enrich_with_distance(laps, verbose)
% ENRICH_WITH_DISTANCE  Add .dist (metres) to every channel by resampling
%                       onto the master distance grid.
%
% Distance source priority:
%   1. Ground_Speed  — integrated via cumtrapz, zeroed at beacon (t=0).
%                      Cleanest option: no cross-lap contamination, starts
%                      exactly at 0 regardless of odometer state.
%   2. Corr_Dist     — corrected cumulative distance, zeroed at first sample
%   3. Odometer      — cumulative, zeroed at first sample

    SPEED_CANDIDATES = {'Ground_Speed'};
    DIST_CANDIDATES  = {'Corr_Dist', 'Odometer'};

    if isempty(laps), return; end

    for k = 1:numel(laps)
        ch_names        = fieldnames(laps(k).channels);
        dist_field      = '';
        dist_source     = '';
        use_integration = false;

        % PRIMARY: integrate Ground_Speed — clean zero at beacon
        for i = 1:numel(SPEED_CANDIDATES)
            f = find_ch_field_local(laps(k).channels, SPEED_CANDIDATES{i});
            if ~isempty(f)
                dist_field      = f;
                dist_source     = SPEED_CANDIDATES{i};
                use_integration = true;
                break;
            end
        end

        % FALLBACK: use a distance channel if no speed channel found
        if isempty(dist_field)
            for i = 1:numel(DIST_CANDIDATES)
                f = find_ch_field_local(laps(k).channels, DIST_CANDIDATES{i});
                if ~isempty(f)
                    dist_field  = f;
                    dist_source = DIST_CANDIDATES{i};
                    break;
                end
            end
        end

        if isempty(dist_field)
            if verbose
                fprintf('  [WARN] Lap %d: no speed or distance channel — .dist not added.\n', ...
                    laps(k).lap_number);
            end
            continue;
        end

        % ---- Build master distance vector ----
        dist_ch  = laps(k).channels.(dist_field);
        t_master = dist_ch.time(:);
        d_raw    = dist_ch.data(:);

        if use_integration
            % Integrate Ground_Speed (km/h -> m/s), zero at beacon (t=0)
            zero_idx = find(t_master >= 0, 1);
            if isempty(zero_idx), zero_idx = 1; end
            speed_ms = max(d_raw, 0) / 3.6;
            d_master = cumtrapz(t_master, speed_ms);
            d_master = d_master - d_master(zero_idx);
        else
            % Zero distance at first sample
            d_master = d_raw - d_raw(1);
        end

        if verbose && k == 1
            if use_integration
                fprintf('  [INFO] Distance: integrating %s (%.0f Hz)\n', ...
                    dist_source, laps(k).channels.(dist_field).sample_rate);
            else
                fprintf('  [INFO] Distance source: %s\n', dist_source);
            end
        end

        % Enforce monotonically increasing distance
        mono_mask = [true; diff(d_master) > 0];
        t_master  = t_master(mono_mask);
        d_master  = d_master(mono_mask);

        if numel(t_master) < 2
            if verbose
                fprintf('  [WARN] Lap %d: distance has < 2 monotonic points.\n', ...
                    laps(k).lap_number);
            end
            continue;
        end

        % ---- Resample all channels onto master distance time grid ----
        for c = 1:numel(ch_names)
            fn   = ch_names{c};
            ch   = laps(k).channels.(fn);
            t_ch = ch.time(:);
            d_ch = ch.data(:);

            if numel(t_ch) < 2
                laps(k).channels.(fn).dist = NaN(size(d_ch));
                continue;
            end

            [t_ch_u, ia] = unique(t_ch, 'stable');
            d_ch_u = d_ch(ia);

            t_lo      = max(t_master(1),  t_ch_u(1));
            t_hi      = min(t_master(end), t_ch_u(end));
            data_full = NaN(numel(t_master), 1);

            if t_lo < t_hi
                in_range = t_master >= t_lo & t_master <= t_hi;
                data_full(in_range) = interp1(t_ch_u, d_ch_u, ...
                    t_master(in_range), 'linear', NaN);
            end

            laps(k).channels.(fn).data = data_full;
            laps(k).channels.(fn).time = t_master;
            laps(k).channels.(fn).dist = d_master;
        end
    end
end


% ======================================================================= %
function field = find_ch_field_local(channels_struct, name)
    if isfield(channels_struct, name), field = name; return; end
    san = regexprep(name, '[^a-zA-Z0-9_]', '_');
    if isfield(channels_struct, san),  field = san;  return; end
    all_f = fieldnames(channels_struct);
    for i = 1:numel(all_f)
        if strcmpi(all_f{i}, name) || strcmpi(all_f{i}, san)
            field = all_f{i};
            return;
        end
    end
    field = '';
end

% ======================================================================= %
% function field = find_ch_field_local(channels_struct, name)
%     if isfield(channels_struct, name), field = name; return; end
%     san = regexprep(name, '[^a-zA-Z0-9_]', '_');
%     if isfield(channels_struct, san),  field = san;  return; end
%     all_f = fieldnames(channels_struct);
%     for i = 1:numel(all_f)
%         if strcmpi(all_f{i}, name) || strcmpi(all_f{i}, san)
%             field = all_f{i};
%             return;
%         end
%     end
%     field = '';
% end


% ======================================================================= %
function field = find_channel(session, name, ch_names)
    if isfield(session, name), field = name; return; end
    san = regexprep(name, '[^a-zA-Z0-9_]', '_');
    if isfield(session, san),  field = san;  return; end
    for i = 1:numel(ch_names)
        if strcmpi(ch_names{i}, name) || strcmpi(ch_names{i}, san)
            field = ch_names{i};
            return;
        end
    end
    field = '';
end


% ======================================================================= %
function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end