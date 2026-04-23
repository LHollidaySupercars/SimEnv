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
%   opts.detect_pitlane   Enable pit-lane detection via MyLaps beacon
%                         channel                  (default: false)
%   opts.mylaps_channel   MyLaps beacon channel name
%                         (default: 'MyLaps X2TRA DeviceShortId')
%                         Beacon values used:
%                           41 = pit entry
%                           42 = pit entry speed trap (5 m after 41)
%                           48 = pit exit speed trap (optional)
%                           49 = pit exit
%
% Output — laps(k):
%   .lap_number           integer
%   .lap_time             seconds (best available precision)
%   .lap_time_source      'Running_Lap_Time' | 'Lap_Time' | 'boundary'
%   .t_start              session time at lap start (s)
%   .t_end                session time at lap end (s)
%   .lap_type             'pitlap'  — beacon 49 present (exiting pits / session start)
%                         'inlap'   — beacon 41 present (entering pits)
%                         'outlap'  — no beacons, lap immediately follows a pitlap
%                         'flying'  — no beacons, not following a pitlap
%                         'fcy'     — FCY channel active during lap (overrides above)
%                         'slow'    — lap_time < min_lap_time (flying/unclassified only)
%                         'long'    — lap_time > max_lap_time (flying/unclassified only)
%                         ''        — when detect_pitlane is false
%   .pit_entry_t          abs session time of beacon 41 (NaN if absent)
%   .pit_entry_speed_t    abs session time of beacon 42 (NaN if absent)
%   .pit_exit_speed_t     abs session time of beacon 48 (NaN if absent)
%   .pit_exit_t           abs session time of beacon 49 (NaN if absent)
%   .pit_segment          Struct with pit-lane sub-slice ([] if not detected)
%       .t_start          abs session time at pit entry (beacon 41)
%       .t_end            abs session time at pit exit  (beacon 49)
%       .duration         pit lane transit time (s)
%       .channels.(X)     same fields as laps(k).channels but scoped to
%                         [pit_entry_t, pit_exit_t]; .time is zeroed to
%                         pit_entry_t (0 = pit entry beacon)
%   .channels.(X)
%       .data             sliced values
%       .time             lap-relative time (s); 0 = beacon; negative = lookback
%       .time_abs         absolute session time (s)
%       .dist             distance (m) — added by enrich_with_distance
%       .units / .sample_rate / .raw_name  (copied)

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 2, opts = struct(); end
    lap_ch          = get_opt(opts, 'lap_channel',    'Lap_Number');
    min_lap_time    = get_opt(opts, 'min_lap_time',   10);    % backwards compat — classification only, not filtering
    max_lap_time    = get_opt(opts, 'max_lap_time',   600);   % backwards compat — classification only, not filtering
    lap_range       = get_opt(opts, 'lap_range',      []);
    excl_laps       = get_opt(opts, 'exclude_laps',   []);
    verbose         = get_opt(opts, 'verbose',        true);
    detect_pitlane  = get_opt(opts, 'detect_pitlane', false);
    mylaps_ch_name  = get_opt(opts, 'mylaps_channel', 'MyLaps_X2TRA_DeviceShortId');
    fcy_ch_name     = get_opt(opts, 'fcy_channel',    'Sw_State_SC');
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

    % ------------------------------------------------------------------
    %  3b. MyLaps X2TRA beacon channel (pit-lane detection)
    %      Values used:
    %        41 = pit entry          (pit lane begins)
    %        42 = pit entry speed trap (5 m after beacon 41)
    %        48 = pit exit speed trap  (optional — not all tracks)
    %        49 = pit exit           (pit lane ends)
    % ------------------------------------------------------------------
    % ------------------------------------------------------------------
    %  3b. MyLaps channel (pit-lane detection)
    %      Only opts.mylaps_channel is used — no fallback to 'Beacon'.
    %      The Beacon channel (idle = 997, noisy S/F transitions) never
    %      contains values 41/42/48/49 and must not be used here.
    %      Values used:
    %        41 = pit entry             (pit lane begins)
    %        42 = pit entry speed trap  (~5 m after beacon 41)
    %        48 = pit exit speed trap   (optional — not all tracks)
    %        49 = pit exit              (pit lane ends)
    % ------------------------------------------------------------------
    mylaps_field = '';
    if detect_pitlane
        mylaps_field = find_channel(session, mylaps_ch_name, ch_names);
        if ~isempty(mylaps_field)
            if verbose
                fprintf('  [INFO] MyLaps channel: %s\n', mylaps_field);
            end
        else
            if verbose
                fprintf('  [WARN] detect_pitlane=true but MyLaps channel "%s" not found — pit detection disabled.\n', mylaps_ch_name);
            end
            detect_pitlane = false;
        end
    end

    % ------------------------------------------------------------------
    %  3c. FCY flag channel (Full Course Yellow / Safety Car detection)
    %      When any sample > 0 in the lap window, lap_type is set 'fcy'.
    % ------------------------------------------------------------------
    fcy_field = find_channel(session, fcy_ch_name, ch_names);
    if verbose && ~isempty(fcy_field)
        fprintf('  [INFO] FCY channel: %s\n', fcy_field);
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
    %  5. Filter lap boundaries
    %     All laps are kept regardless of duration — classify, don't discard.
    %     min_lap_time / max_lap_time accepted for backwards compat but used
    %     for classification only (step 7), not filtering.
    %     Only NaN boundaries, lap_range, and exclude_laps are applied here.
    % ------------------------------------------------------------------
    valid_mask = ~any(isnan(boundaries), 2);

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
        fprintf('  After boundary filter: %d\n', n_valid);
        if detect_pitlane
            fprintf('\n  %-6s  %-10s  %-10s  %-12s  %-18s  %s\n', ...
                'Lap', 't_start', 't_end', 'Duration(s)', 'Source', 'Type');
            fprintf('  %s\n', repmat('-', 1, 72));
        else
            fprintf('\n  %-6s  %-10s  %-10s  %-12s  %s\n', ...
                'Lap', 't_start', 't_end', 'Duration(s)', 'Source');
            fprintf('  %s\n', repmat('-', 1, 52));
        end
    end

    % ------------------------------------------------------------------
    %  6. Slice channels + resolve precise lap time for each lap
    % ------------------------------------------------------------------
    LOOKBACK_S = 1.5;   % pre-beacon window for distance enrichment

    laps = struct('lap_number',         cell(1, n_valid), ...
                  'lap_time',           cell(1, n_valid), ...
                  'lap_time_source',    cell(1, n_valid), ...
                  't_start',            cell(1, n_valid), ...
                  't_end',              cell(1, n_valid), ...
                  'lap_type',           cell(1, n_valid), ...
                  'pit_entry_t',        cell(1, n_valid), ...
                  'pit_entry_speed_t',  cell(1, n_valid), ...
                  'pit_exit_speed_t',   cell(1, n_valid), ...
                  'pit_exit_t',         cell(1, n_valid), ...
                  'pit_segment',        cell(1, n_valid), ...
                  'channels',           cell(1, n_valid));

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

        % ------------------------------------------------------------------
        %  Pit-lane detection from MyLaps X2TRA beacon channel
        % ------------------------------------------------------------------
        if detect_pitlane
            ml_data = round(session.(mylaps_field).data);
            ml_time = session.(mylaps_field).time;
            lap_msk = ml_time >= t_s & ml_time < t_e;
            ml_d    = ml_data(lap_msk);
            ml_t    = ml_time(lap_msk);

            pit_entry_t       = find_beacon(ml_d, ml_t, 41);
            pit_entry_speed_t = find_beacon(ml_d, ml_t, 42);
            pit_exit_speed_t  = find_beacon(ml_d, ml_t, 48);
            pit_exit_t        = find_beacon(ml_d, ml_t, 49);

            % Classify lap type from beacon presence.
            % Beacon 49 (pit exit) fires during the pitlane lap — the car
            % is either starting the session from pits, or has completed
            % an inlap and is driving back out through pit lane.  The lap
            % *following* a pitlap (no beacons) is labelled outlap in the
            % sequence pass (step 6b) below.
            has_entry = ~isnan(pit_entry_t);
            has_exit  = ~isnan(pit_exit_t);
            if has_entry && has_exit
                lap_type = 'pitlap';   % edge: full pit stop within one MoTeC lap
            elseif has_entry
                lap_type = 'inlap';
            elseif has_exit
                lap_type = 'pitlap';   % beacon 49 only — exiting pit lane
            else
                lap_type = 'flying';   % may be revised to outlap in step 6b
            end

            laps(k).lap_type          = lap_type;
            laps(k).pit_entry_t       = pit_entry_t;
            laps(k).pit_entry_speed_t = pit_entry_speed_t;
            laps(k).pit_exit_speed_t  = pit_exit_speed_t;
            laps(k).pit_exit_t        = pit_exit_t;

            % Build pit_segment when we have both entry and exit
            if has_entry && has_exit
                ps         = struct();
                ps.t_start = pit_entry_t;
                ps.t_end   = pit_exit_t;
                ps.duration = pit_exit_t - pit_entry_t;
                ps.channels = struct();
                seg_ch_names = fieldnames(laps(k).channels);
                for sc = 1:numel(seg_ch_names)
                    sfn  = seg_ch_names{sc};
                    sch  = laps(k).channels.(sfn);
                    % sub-index using time_abs which is always present
                    if isfield(sch, 'time_abs')
                        smsk = sch.time_abs >= pit_entry_t & sch.time_abs <= pit_exit_t;
                        seg             = sch;
                        seg.data        = sch.data(smsk);
                        seg.time        = sch.time_abs(smsk) - pit_entry_t;
                        seg.time_abs    = sch.time_abs(smsk);
                        if isfield(sch, 'dist')
                            seg.dist    = sch.dist(smsk);
                        end
                        ps.channels.(sfn) = seg;
                    end
                end
                laps(k).pit_segment = ps;
            else
                laps(k).pit_segment = [];
            end
        else
            laps(k).lap_type          = '';
            laps(k).pit_entry_t       = NaN;
            laps(k).pit_entry_speed_t = NaN;
            laps(k).pit_exit_speed_t  = NaN;
            laps(k).pit_exit_t        = NaN;
            laps(k).pit_segment       = [];
        end

        if verbose
            if detect_pitlane
                fprintf('  %-6d  %-10.2f  %-10.2f  %-12.3f  %-18s  %s\n', ...
                    lap_n, t_s, t_e, dur, dur_source, laps(k).lap_type);
            else
                fprintf('  %-6d  %-10.2f  %-10.2f  %-12.3f  %s\n', ...
                    lap_n, t_s, t_e, dur, dur_source);
            end
        end
    end

    % ------------------------------------------------------------------
    %  6b. Sequence pass — label outlaps by position.
    %      MoTeC records the pitlane phase under Lap_Number = -1 which is
    %      filtered out by step 5 — the pitlane lap is invisible.  We
    %      therefore use two triggers to identify outlaps:
    %        (a) Previous lap was 'pitlap' (beacon 41+49 in same window —
    %            edge case where both beacons fall within one MoTeC lap)
    %        (b) Previous lap was 'inlap' (beacon 41 detected; car pitted
    %            during the filtered -1 lap; next flying lap must be outlap)
    %      The session always starts from pits, so the first flying lap
    %      is also an outlap regardless.
    % ------------------------------------------------------------------
    if detect_pitlane
        for k = 2:numel(laps)
            if strcmp(laps(k).lap_type, 'flying') && ...
               (strcmp(laps(k-1).lap_type, 'pitlap') || ...
                strcmp(laps(k-1).lap_type, 'inlap'))
                laps(k).lap_type = 'outlap';
            end
        end
        % First lap — session always starts from pits
        if numel(laps) >= 1 && strcmp(laps(1).lap_type, 'flying')
            laps(1).lap_type = 'outlap';
        end
    end

    % ------------------------------------------------------------------
    %  7. Classification pass — all laps are kept.
    %     Priority order: FCY > pit-type (set in step 6/6b) > slow > long
    %     min/max_lap_time apply to 'flying' and unclassified laps only.
    % ------------------------------------------------------------------
    for k = 1:numel(laps)
        % FCY overrides everything (including pit-type laps)
        if ~isempty(fcy_field)
            fcy_data = session.(fcy_field).data;
            fcy_time = session.(fcy_field).time;
            fcy_msk  = fcy_time >= laps(k).t_start & fcy_time < laps(k).t_end;
            if any(fcy_msk) && any(fcy_data(fcy_msk) > 0)
                laps(k).lap_type = 'fcy';
                continue;
            end
        end
        % Time classification for flying / unclassified laps only
        if ismember(laps(k).lap_type, {'flying', ''})
            lt = laps(k).lap_time;
            if lt < min_lap_time
                laps(k).lap_type = 'slow';
            elseif lt > max_lap_time
                laps(k).lap_type = 'long';
            end
        end
    end

    if verbose
        fprintf('\n  Sliced %d laps (all kept).\n', numel(laps));
        types = {laps.lap_type};
        ut = unique(types);
        for ti = 1:numel(ut)
            fprintf('    %-10s : %d\n', ut{ti}, sum(strcmp(types, ut{ti})));
        end
        fprintf('\n');
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
function t = find_beacon(beacon_data, beacon_time, value)
% FIND_BEACON  Return the absolute session time of the first TRANSITION to
%              a beacon value within an already-masked data/time pair.
%              A transition means: previous sample != value, current == value.
%              The first sample is never counted even if it equals value —
%              a beacon set at the very start of a lap window is a holdover
%              from the previous lap (the channel holds its last value), not
%              a new event.  Returns NaN if no transition is found.
    t = NaN;
    n = numel(beacon_data);
    if n < 2, return; end
    % Start from index 2 so we always have a preceding sample to compare
    for i = 2:n
        if beacon_data(i) == value && beacon_data(i-1) ~= value
            t = beacon_time(i);
            return;
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