function laps = lap_slicer(session, opts)
% LAP_SLICER  Slice a MoTeC session struct into per-lap channel data.
%
% Boundary detection mode is selected automatically (A → B → C):
%
%   MODE A  MyLaps X2TRA (detect_pitlane=true, channel present)
%           Boundaries from transitions to beacons 41/49/60.
%           Full pit classification from beacon sequence.
%
%   MODE B  BR2_Beacon_Number (auto-detected when channel present)
%           Signal behaviour:
%             996 = normal running (flying-lap phase)
%             999 = approaching S/F line OR entering pit lane
%             0   = garage / pit lane hold
%           Transitions:
%             999 → 996 = S/F crossing → new lap boundary
%             996 → 999 = pit entry → inlap
%           Pit stop is detected as a contiguous hold at 0 > BR2_PIT_MIN_S.
%           pit_entry_speed_t and pit_exit_speed_t are always NaN (not
%           available from BR2).
%
%   MODE C  Lap_Number channel (fallback / legacy)
%           1 Hz integer channel. lap_time resolution is integer seconds
%           unless Running_Lap_Time or Lap_Time channels are present.
%           No pit classification.
%
% Lap duration (Mode C only — Modes A/B use beacon timestamps directly):
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
%                         channel (Mode A)         (default: false)
%   opts.mylaps_channel   MyLaps beacon channel name
%                         (default: 'MyLaps_X2TRA_DeviceShortId')
%                         Beacon values used:
%                           41 = pit entry
%                           42 = pit entry speed trap (5 m after 41)
%                           48 = pit exit speed trap (optional)
%                           49 = pit exit
%   opts.br2_channel      BR2 beacon channel name for Mode B
%                         (default: 'BR2_Beacon_Number')
%                         Auto-detected — no opt needed to enable.
%                         Set to '' to force Mode C even if channel exists.
%
% Output — laps(k):
%   .lap_number           integer
%   .lap_time             seconds (best available precision)
%   .lap_time_source      'Running_Lap_Time' | 'Lap_Time' | 'boundary'
%   .t_start              session time at lap start (s)
%   .t_end                session time at lap end (s)
%   .lap_type             'pitlap'  — beacon 49 present (exiting pits / session start)
%                         'inlap'   — entering pits (beacon 41 / BR2 context)
%                         'outlap'  — exiting pits (beacon 49 / BR2 context)
%                         'flying'  — normal timed lap, no pit beacons
%                         'fcy'     — FCY channel active during lap (overrides above)
%                         'slow'    — lap_time < min_lap_time (flying/unclassified only)
%                         'long'    — lap_time > max_lap_time (flying/unclassified only)
%                         ''        — Mode C with no pit awareness
%   .pit_entry_t          abs session time of pit entry event (NaN if absent)
%                         Mode A: beacon 41 | Mode B: start of long-900 pulse
%   .pit_entry_speed_t    abs session time of beacon 42 (NaN if absent / Mode B)
%   .pit_exit_speed_t     abs session time of beacon 48 (NaN if absent / Mode B)
%   .pit_exit_t           abs session time of pit exit event (NaN if absent)
%                         Mode A: beacon 49 | Mode B: end of long-900 pulse
%   .pit_segment          Struct with pit-lane sub-slice ([] if not detected)
%       .t_start          abs session time at pit entry
%       .t_end            abs session time at pit exit
%       .duration         pit lane transit time (s)
%       .channels.(X)     same fields as laps(k).channels but scoped to
%                         [pit_entry_t, pit_exit_t]; .time is zeroed to
%                         pit_entry_t (0 = pit entry)
%   .channels.(X)
%       .data             sliced values
%       .time             lap-relative time (s); 0 = t_start
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
    br2_ch_name     = get_opt(opts, 'br2_channel',    'BR2_Beacon_Number');
    br2_proto_in    = get_opt(opts, 'br2_protocol',   'standard');
    fcy_ch_name     = get_opt(opts, 'fcy_channel',    'Sw_State_SC');
    beacon_check    = get_opt(opts, 'beacon_check',   false);
    beacon_label    = get_opt(opts, 'beacon_check_label', '');

    % BR2 thresholds
    BR2_PIT_MIN_S      = 4.0;  % garage hold longer than this = pit stop

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
    t_session_start = lap_num_time(1);
    t_session_end   = lap_num_time(end);

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
    detect_pitlane_requested = detect_pitlane;   % remember original intent
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

    % ------------------------------------------------------------------
    %  3d. BR2_Beacon_Number channel (Mode B boundary detection)
    %      Auto-detected — no opt required. Only used when Mode A
    %      (MyLaps / detect_pitlane) is not active.
    % ------------------------------------------------------------------
    br2_field = '';
        if ~isempty(br2_ch_name)
        br2_field = find_channel(session, br2_ch_name, ch_names);
        if verbose && ~isempty(br2_field)
            fprintf('  [INFO] BR2 channel: %s\n', br2_field);
        end
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
    %  4. Detect lap boundaries
    %
    %  Mode A — MyLaps X2TRA (detect_pitlane=true, channel present)
    %    Boundary events: 41 (pit entry), 49 (pit exit), 60 (S/F line).
    %    Slice type is determined by transition pair.
    %
    %  Mode B — BR2_Beacon_Number (auto-detected)
    %    S/F crossing = 999→996 transition → new lap boundary.
    %    Pit-in       = 996→999 transition → inlap.
    %    Garage hold  = contiguous 0 > BR2_PIT_MIN_S → outlap on next lap.
    %
    %  Mode C — Lap_Number channel (fallback / legacy)
    %    Two-pass build: t_start = first sample of each unique lap number,
    %    t_end = t_start of the next lap (or session end).
    % ------------------------------------------------------------------
    br2_mode = false;   % set true when Mode B is active

    % Pre-compute ZOH beacon channel for Mode A pit classification.
    MIN_BEACON_HOLD_S = 0.1;
    if detect_pitlane && ~isempty(mylaps_field)
        [ml_data_zoh, ml_time_zoh] = beacon_to_zoh( ...
            round(session.(mylaps_field).data), ...
            session.(mylaps_field).time, ...
            MIN_BEACON_HOLD_S);
    else
        ml_data_zoh = [];
        ml_time_zoh = [];
    end

    if detect_pitlane && ~isempty(mylaps_field)
        % ---- MODE A: MyLaps beacon-transition boundary detection ----
        % Slices are defined by consecutive significant beacon events.
        % Boundary events: 41 (pit entry), 49 (pit exit), 60 (S/F line).
        % Slice type is determined by the transition pair:
        %   49 -> 60  : outlap
        %   60 -> 60  : flying
        %   60 -> 41  : inlap
        %   41 -> 49  : pitlap
        % Slices are numbered sequentially from 0.

        % BOUNDARY_BEACONS = [41, 49, 60];
        BOUNDARY_BEACONS = [41, 49, 60, 62, 63];
        % Extract only boundary beacon events from ZOH data
        ev_vals = [];
        ev_times = [];
        for i = 1:numel(ml_data_zoh)
            if ismember(ml_data_zoh(i), BOUNDARY_BEACONS)
                ev_vals(end+1)  = ml_data_zoh(i);  %#ok<AGROW>
                ev_times(end+1) = ml_time_zoh(i);  %#ok<AGROW>
            end
        end
        SF_BEACONS = [60, 62, 63];
        if ~isempty(ev_vals)
            keep = true(1, numel(ev_vals));
            for i = 2:numel(ev_vals)
                if ismember(ev_vals(i), SF_BEACONS) && ismember(ev_vals(i-1), SF_BEACONS) && ...
                        (ev_times(i) - ev_times(i-1)) < 2.0
                    keep(i) = false;
                end
            end
            ev_vals  = ev_vals(keep);
            ev_times = ev_times(keep);
        end
        if isempty(ev_vals)
            warning('lap_slicer: detect_pitlane=true but no boundary beacons (41/49/60) found. Falling back to BR2/Lap_Number.');
            detect_pitlane = false;
        end
    end  % beacon extraction — detect_pitlane may have been cleared

    if detect_pitlane && ~isempty(mylaps_field)
        % Build slice boundaries from consecutive beacon events.
        % Pre-session window: t_session_start -> first beacon event.
        t_starts_b = [t_session_start, ev_times];
        t_ends_b   = [ev_times,        t_session_end];
        val_starts = [NaN,     ev_vals];   % NaN = pre-session (no entry beacon)
        val_ends   = [ev_vals, NaN];       % NaN = session end

        n_slices   = numel(t_starts_b);
        boundaries = [t_starts_b(:), t_ends_b(:)];
        lap_nums   = (0 : n_slices-1)';

        % Pre-assign lap types from beacon transitions (overridden per-lap below)
        slice_types_preset = cell(n_slices, 1);
        % for k = 1:n_slices
        %     vs = val_starts(k);
        %     ve = val_ends(k);
        %     if isnan(vs)
        %         slice_types_preset{k} = 'pitlap';
        %     elseif vs == 49 && ve == 60
        %         slice_types_preset{k} = 'outlap';
        %     elseif vs == 60 && ve == 60
        %         slice_types_preset{k} = 'flying';
        %     elseif vs == 60 && ve == 41
        %         slice_types_preset{k} = 'inlap';
        %     elseif vs == 41 && ve == 49
        %         slice_types_preset{k} = 'pitlap';
        %     elseif isnan(ve)
        %         slice_types_preset{k} = 'inlap';
        %     else
        %         slice_types_preset{k} = 'flying';
        %     end
        % end
        SF_BEACONS = [60, 62, 63];   % all S/F line beacon values

        for k = 1:n_slices
            vs = val_starts(k);
            ve = val_ends(k);
            if isnan(vs)
                slice_types_preset{k} = 'pitlap';
            elseif vs == 49 && ismember(ve, SF_BEACONS)
                slice_types_preset{k} = 'outlap';
            elseif ismember(vs, SF_BEACONS) && ismember(ve, SF_BEACONS)
                slice_types_preset{k} = 'flying';
            elseif ismember(vs, SF_BEACONS) && ve == 41
                slice_types_preset{k} = 'inlap';
            elseif vs == 41 && ve == 49
                slice_types_preset{k} = 'pitlap';
            elseif vs == 41 && isnan(ve)
                slice_types_preset{k} = 'pit_truncated';  
            elseif isnan(ve)
                slice_types_preset{k} = 'inlap';
            else
                slice_types_preset{k} = 'flying';
            end
        end
        if verbose
            fprintf('\n  Boundary mode       : Mode A — MyLaps beacon transitions (41/49/60)\n');
            fprintf('  Slices detected     : %d\n', n_slices);
        end
        boundary_mode = mylaps_field;
    elseif ~isempty(br2_field)
        br2_field_orig = br2_field;   % preserve for plot even if detection falls back to Mode C
        if ischar(br2_proto_in)
            br2_proto = br2_protocol_get(br2_proto_in);
        else
            br2_proto = br2_proto_in;
        end
        % ---- MODE B: BR2_Beacon_Number S/F transition detection ----
        %
        % Signal semantics:
        %   996 = normal running (flying lap phase)
        %   999 = approaching S/F line  OR  entering pit lane
        %   0   = garage / pit lane hold
        %   other values = transient bounce while crossing S/F
        %
        % S/F crossing (new lap boundary):
        %   999 → 996 transition = car crossed S/F line.
        %
        % Pit-in detection:
        %   996 → 999 transition = car entered pit lane → inlap.
        %   (Opposite direction to S/F crossing.)
        %
        % Pit-stop detection (garage hold):
        %   A contiguous run of 0 lasting > BR2_PIT_MIN_S = in garage.

        % MoTeC stores beacon channels as linearly-interpolated floats.
        % Collapse to a ZOH step function to strip interpolation ramp integers
        % (e.g. 997, 998 between 996 and 999) before transition detection.
        BR2_MIN_HOLD_S = 0.05;   % discard ramp samples held < 50 ms
        [br2_zoh, br2_zoh_t] = beacon_to_zoh( ...
            round(session.(br2_field).data(:)), ...
            session.(br2_field).time(:), ...
            BR2_MIN_HOLD_S);

        % Keep originals for Pass 2 (garage run duration uses raw timestamps)
        br2_raw  = round(session.(br2_field).data(:));
        br2_time = session.(br2_field).time(:);

        br2_sf_times    = [];   % session time of each S/F crossing
        br2_pitin_t     = [];   % session time of each pit-in line crossing
        br2_pitout_t    = [];   % session time of each pit-out event

        if strcmp(br2_proto.variant, 'simple_pulse')
            % --- Simple-pulse protocol detection (e.g. TAS2025) ---
            % S/F:     idle -> sf_pulse -> idle   time = start of sf_pulse
            % Pit-in:  idle -> pitin             time = start of pitin state
            % Pit-out: pitin -> idle             time = return to idle
            for i = 2:numel(br2_zoh)
                prev_v = br2_zoh(i-1);
                cur_v  = br2_zoh(i);
                if prev_v == br2_proto.idle && cur_v == br2_proto.sf_pulse
                    br2_sf_times(end+1) = br2_zoh_t(i);   %#ok<AGROW>
                elseif prev_v == br2_proto.idle && cur_v == br2_proto.pitin
                    br2_pitin_t(end+1)  = br2_zoh_t(i);   %#ok<AGROW>
                elseif prev_v == br2_proto.pitin && cur_v == br2_proto.idle
                    br2_pitout_t(end+1) = br2_zoh_t(i);   %#ok<AGROW>
                end
            end
        else
            % --- Standard protocol detection (999->1500->996 sequences) ---
            br2_pit900_prev = [];   % value before each garage run
            br2_pit900_t0   = [];   % start time of each garage run
            br2_pit900_t1   = [];   % end   time of each garage run

            n_br2_zoh = numel(br2_zoh);

        % --- Pass 1: S/F crossings and pit-in detection ---
        %
        % Confirmed signal sequences (raw):
        %   S/F crossing  : ANY -> 999 -> 1500 -> 900 -> 996
        %                   Discriminator: first non-999 raw value after 999 = 1500.
        %                   Lap boundary time = first 996 in raw after that 1500.
        %
        %   Pit-in line   : 996 -> 999 -> 900/0  (no 1500)
        %                   Discriminator: first non-999 raw value = 900 or 0.
        %                   Predecessor ZOH must be 996 (not garage re-entry).
        %
        % ZOH used only to find 999 transition start-time cleanly.
        % Raw signal used for the forward discriminator scan — 1500 pulse at
        % race speed may be < 50ms and would be stripped by the ZOH filter.
        for i = 2:n_br2_zoh
            if br2_zoh(i) == 999 && br2_zoh(i-1) ~= 999
                t_999     = br2_zoh_t(i);
                pred_996  = (br2_zoh(i-1) == 996);

                % Scan raw signal forward from this 999 start to find first
                % non-999, non-artifact value.  -1 is a MoTeC transitional
                % placeholder written between beacon states; skip it so it
                % does not mask the real discriminator (1500, 996, 900, etc.)
                raw_after   = br2_raw(br2_time >= t_999);
                raw_t_after = br2_time(br2_time >= t_999);
                fn_idx      = find(raw_after ~= 999 & raw_after ~= -1, 1);
                if isempty(fn_idx)
                    % Session ended while beacon was still at 999 — the car
                    % entered the pit lane but the session closed before a
                    % discriminator value appeared.  If the predecessor was
                    % 996 this is a pit-in at session end → record it.
                    if pred_996
                        br2_pitin_t(end+1) = t_999;  %#ok<AGROW>
                        if verbose
                            fprintf('  [INFO] BR2: pit-in at session end t=%.3fs (999 with no following discriminator).\n', t_999);
                        end
                    end
                    continue;
                end
                first_non999 = raw_after(fn_idx);

                if first_non999 == 1500
                    % S/F crossing -- find first 996 in raw after the 1500
                    raw_from_1500 = raw_after(fn_idx:end);
                    raw_t_1500    = raw_t_after(fn_idx:end);
                    idx996 = find(raw_from_1500 == 996, 1);
                    if ~isempty(idx996)
                        br2_sf_times(end+1) = raw_t_1500(idx996);  %#ok<AGROW>
                    end
                elseif first_non999 == 0
                    % 999→0: car went directly to garage/jacks.
                    if pred_996
                        % Normal pit-in: on-track → pit lane → jacks
                        br2_pitin_t(end+1) = t_999;  %#ok<AGROW>
                    end
                    % else: still in garage (0→999→0 re-entry) — ignore.

                elseif first_non999 == 900
                    if pred_996
                        % 996→999→900: brief landing zone after S/F crossing
                        % (1500 pulse absent or too short in raw data).
                        % Find first 996 after the 900 zone.
                        raw_seg   = raw_after(fn_idx:end);
                        raw_t_seg = raw_t_after(fn_idx:end);
                        hold_end  = find(raw_seg ~= 900 & raw_seg ~= 0, 1);
                        if ~isempty(hold_end)
                            tail_vals = raw_seg(hold_end:end);
                            tail_t    = raw_t_seg(hold_end:end);
                            idx996 = find(tail_vals == 996, 1);
                            if ~isempty(idx996)
                                br2_sf_times(end+1) = tail_t(idx996);  %#ok<AGROW>
                            end
                        end
                    else
                        % 0→999→900: garage exit, car crossing S/F on outlap.
                        raw_seg   = raw_after(fn_idx:end);
                        raw_t_seg = raw_t_after(fn_idx:end);
                        hold_end  = find(raw_seg ~= 900 & raw_seg ~= 0, 1);
                        if ~isempty(hold_end)
                            tail_vals = raw_seg(hold_end:end);
                            tail_t    = raw_t_seg(hold_end:end);
                            idx996 = find(tail_vals == 996, 1);
                            if ~isempty(idx996)
                                br2_sf_times(end+1) = tail_t(idx996);  %#ok<AGROW>
                            end
                        end
                    end
                elseif first_non999 == 996
                    % Direct 999→996 with no 1500 in raw (very high speed crossing).
                    % The discriminator value itself is already the 996 boundary time.
                    br2_sf_times(end+1) = raw_t_after(fn_idx);  %#ok<AGROW>
                else
                    % Unrecognised discriminator (e.g. -1 sensor artifact, or 900
                    % without pred_996). The 1500 pulse may have been absent or too
                    % short. Recovery: look for a 996 within BR2_SF_RECOVERY_S of
                    % the unrecognised value — if found it is an S/F crossing.
                    BR2_SF_RECOVERY_S = 5.0;
                    rec_vals = raw_after(fn_idx:end);
                    rec_t    = raw_t_after(fn_idx:end);
                    in_win   = rec_t <= (rec_t(1) + BR2_SF_RECOVERY_S);
                    idx996   = find(rec_vals(in_win) == 996, 1);
                    if ~isempty(idx996)
                        br2_sf_times(end+1) = rec_t(idx996);  %#ok<AGROW>
                        if verbose
                            fprintf('  [INFO] BR2: discriminator %d at t=%.3fs — S/F recovered from next 996.\n', first_non999, t_999);
                        end
                    else
                        if verbose
                            fprintf('  [WARN] BR2: unexpected discriminator value %d after 999 at t=%.3fs — skipped (no 996 within %.1fs).\n', first_non999, t_999, BR2_SF_RECOVERY_S);
                        end
                    end
                end
            end
        end

        % Deduplicate S/F times: multiple ZOH 999-transitions can resolve to the
        % same 996 timestamp (e.g. signal bouncing at pit exit).  Remove entries
        % that are within min_lap_time of a previous entry.
        if ~isempty(br2_sf_times)
            br2_sf_times = sort(br2_sf_times);
            keep = [true, diff(br2_sf_times) > min_lap_time];
            br2_sf_times = br2_sf_times(keep);
        end

        n_br2 = numel(br2_raw);

        % --- Pass 2: pit/garage runs (contiguous hold at 900 or 0) ---
        i = 1;
        while i <= n_br2
            if br2_raw(i) == 900 || br2_raw(i) == 0
                garage_val = br2_raw(i);
                run_start = i;
                while i <= n_br2 && (br2_raw(i) == 900 || br2_raw(i) == 0)
                    i = i + 1;
                end
                run_end  = i - 1;
                run_dur  = br2_time(run_end) - br2_time(run_start);
                if run_dur > BR2_PIT_MIN_S
                    prev_val = garage_val;
                    if run_start > 1, prev_val = br2_raw(run_start - 1); end
                    br2_pit900_prev(end+1) = prev_val;        %#ok<AGROW>
                    br2_pit900_t0(end+1)   = br2_time(run_start);  %#ok<AGROW>
                    br2_pit900_t1(end+1)   = br2_time(run_end);    %#ok<AGROW>
                end
            else
                i = i + 1;
            end
        end

        % --- Pass 2b: recover pit-in times for garage runs preceded by 999 ---
        % When the car enters the pit lane (996→999) and transitions directly
        % into the garage (999→900/0) without a 1500 discriminator, Pass 1
        % misclassifies the 996→999 as a potential S/F crossing and records
        % only the eventual S/F crossing (pit exit). Recover the true pit-in
        % time by scanning backward from each such garage run to find the
        % last 996 sample.
        PITIN_DEDUP_S = 5.0;
        for pi = 1:numel(br2_pit900_t0)
            if br2_pit900_prev(pi) ~= 999, continue; end
            run_t0   = br2_pit900_t0(pi);
            bk_mask  = br2_time < run_t0;
            bk_vals  = br2_raw(bk_mask);
            bk_t     = br2_time(bk_mask);
            last996  = find(bk_vals == 996, 1, 'last');
            if isempty(last996), continue; end
            t_recovered = bk_t(last996);
            if ~isempty(br2_pitin_t) && any(abs(br2_pitin_t - t_recovered) < PITIN_DEDUP_S)
                continue;   % already captured
            end
            br2_pitin_t(end+1) = t_recovered;  %#ok<AGROW>
            if verbose
                fprintf('  [INFO] BR2: recovered pit-in at t=%.3fs (garage run at %.3f, prev=999).\n', t_recovered, run_t0);
            end
        end
        if ~isempty(br2_pitin_t)
            br2_pitin_t = sort(br2_pitin_t);
        end

        % --- Pit-exit boundary injection ---
        % Inject the START of each garage run (beacon → 900) as an explicit
        % boundary so that the outlap begins the moment the car starts moving
        % in the garage (consistent with beacon semantics: 900 = car moving
        % in pit lane).  Only inject runs that lead back onto the circuit
        % (i.e. a S/F crossing follows within BR2_PIT_EXIT_SF_WINDOW_S);
        % sub-runs with no subsequent S/F (multi-bay moves etc.) are ignored.
        BR2_PIT_EXIT_SF_WINDOW_S = 120.0;
        br2_pitout_t = [];
        for pi = 1:numel(br2_pit900_t0)
            t_pit_start = br2_pit900_t0(pi);
            t_pit_end   = br2_pit900_t1(pi);
            sf_in_win   = find(br2_sf_times > t_pit_end & br2_sf_times <= t_pit_end + BR2_PIT_EXIT_SF_WINDOW_S, 1);
            if isempty(sf_in_win), continue; end
            br2_pitout_t(end+1) = t_pit_start;  %#ok<AGROW>
            if verbose
                fprintf('  [INFO] BR2: outlap boundary (beacon→900) at %.3fs (S/F at %.3fs follows).\n', t_pit_start, br2_sf_times(sf_in_win));
            end
        end
        end  % if strcmp(br2_proto.variant, 'simple_pulse') / else

        if isempty(br2_sf_times)
            warning('lap_slicer: BR2 channel found but no 999→996 S/F transitions detected — falling back to Lap_Number (Mode C).');
            br2_field = '';   % fall through to Mode C
        else
            br2_mode = true;
            % Merge pit-in and pit-exit events into the boundary list:
            %   inlap  : S/F → pit entry
            %   pitlap : pit entry → pit exit
            %   outlap : pit exit → first S/F after pit  (short slice)
            %   flying : S/F → S/F (first full lap after outlap)
            br2_all_ev_times     = sort([br2_sf_times(:)', br2_pitin_t(:)', br2_pitout_t(:)']);
            br2_all_ev_is_pitin  = ismember(br2_all_ev_times, br2_pitin_t);
            br2_all_ev_is_pitout = ismember(br2_all_ev_times, br2_pitout_t);

            % Build boundaries from merged event list
            t_starts_b = [t_session_start, br2_all_ev_times];
            t_ends_b   = [br2_all_ev_times, t_session_end];
            n_slices   = numel(t_starts_b);
            boundaries = [t_starts_b(:), t_ends_b(:)];

            % Sequential lap numbering — 0-based (0 = pre-first-beacon outlap).
            % I2 Lap_Number channel is not used in Mode B; its counter can be
            % shifted or skip values when the ECU resets during garage holds.
            lap_nums = (0 : n_slices-1)';

            % Per-slice boundary type flags (length = n_slices).
            %   ends_at_pitin   → inlap
            %   starts_at_pitin → pitlap
            %   ends_at_pitout  → pitlap
            %   starts_at_pitout → outlap
            br2_lap_ends_at_pitin    = [br2_all_ev_is_pitin,  false];
            br2_lap_starts_at_pitin  = [false, br2_all_ev_is_pitin];
            br2_lap_ends_at_pitout   = [br2_all_ev_is_pitout, false];
            br2_lap_starts_at_pitout = [false, br2_all_ev_is_pitout];

            if verbose
                fprintf('\n  Boundary mode       : Mode B - BR2 S/F transitions (%s)\n', br2_proto.name);
                fprintf('  S/F crossings       : %d\n', numel(br2_sf_times));
                fprintf('  Pit-in events       : %d\n', numel(br2_pitin_t));
                fprintf('  Pit-out events      : %d\n', numel(br2_pitout_t));
                if exist('br2_pit900_t0', 'var')
                    fprintf('  Garage runs (0/900) : %d\n', numel(br2_pit900_t0));
                end
            end
        end
    end

    if ~detect_pitlane && ~br2_mode
        % ---- MODE C: Lap_Number-based boundary detection (legacy / fallback) ----
        lap_nums = unique(round(lap_num_data));
        lap_nums = lap_nums(lap_nums > -1);   % include lap 0, exclude -1/-2 init

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

        if verbose
            if detect_pitlane_requested
                fprintf('  [INFO] Beacon channel unavailable — falling back to Lap_Number-based boundary detection (Mode C).\n');
            elseif ~isempty(br2_ch_name)
                fprintf('  [INFO] BR2 beacon channel unavailable — falling back to Lap_Number-based boundary detection (Mode C).\n');
            end
            fprintf('\n  Boundary mode       : Mode C — Lap_Number channel (legacy, fallback)\n');
            fprintf('  Lap numbers detected: %d\n', numel(lap_nums));
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

    if br2_mode
        br2_ends_at_pitin_v    = br2_lap_ends_at_pitin(valid_mask);
        br2_starts_at_pitin_v  = br2_lap_starts_at_pitin(valid_mask);
        br2_ends_at_pitout_v   = br2_lap_ends_at_pitout(valid_mask);
        br2_starts_at_pitout_v = br2_lap_starts_at_pitout(valid_mask);
    end

    if verbose
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

        % ---- Resolve lap time ----
        % Modes A and B use high-frequency beacon/BR2 timestamps directly.
        % Mode C (Lap_Number) falls back to channel-based precision sources.
        if (exist('slice_types_preset', 'var') && ~isempty(slice_types_preset)) || br2_mode
            dur        = t_e - t_s;
            dur_source = 'boundary';
        else
            dur        = t_e - t_s;
            dur_source = 'boundary';
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
            if ~isempty(rlt_field)
                rlt_data = session.(rlt_field).data * rlt_scale;
                rlt_time = session.(rlt_field).time;
                end_mask = rlt_time >= (t_e - 1.0) & rlt_time < t_e;
                rlt_end  = rlt_data(end_mask);
                rlt_end  = rlt_end(isfinite(rlt_end) & rlt_end > 0);
                if ~isempty(rlt_end)
                    rlt_dur = rlt_end(end);
                    if isnan(lt_dur) || abs(rlt_dur - lt_dur) < 1.0
                        dur        = rlt_dur;
                        dur_source = 'Running_Lap_Time';
                    end
                end
            end
            boundary_dur = t_e - t_s;
            if ~strcmp(dur_source, 'boundary') && dur > boundary_dur * 1.5
                dur        = boundary_dur;
                dur_source = 'boundary';
            end
        end

        laps(k).lap_number      = lap_n;
        laps(k).lap_time        = dur;
        laps(k).lap_time_source = dur_source;
        laps(k).t_start         = t_s;
        laps(k).t_end           = t_e;
        laps(k).channels        = struct();

        % ---- Slice all channels, hard cut at t_start (no lookback) ----
        for c = 1:numel(ch_names)
            fn  = ch_names{c};
            ch  = session.(fn);
            t   = ch.time;

            msk = t >= t_s & t < t_e;

            sliced          = ch;
            try
                sliced.data     = ch.data(msk);
                sliced.time_abs = t(msk);
                sliced.time     = t(msk) - t_s;  % 0 = t_start

                laps(k).channels.(fn) = sliced;
            catch
                ch_names(c);
            end

        end

        % ------------------------------------------------------------------
        %  Pit-lane detection
        % ------------------------------------------------------------------
        if detect_pitlane
            % ---- Mode A: MyLaps X2TRA beacon channel ----
            % Reuse the ZOH-reconstructed channel from step 4 so that
            % linear-interpolation ramps between beacons cannot produce
            % false pit-entry/exit hits.
            lap_msk = ml_time_zoh >= t_s & ml_time_zoh < t_e;
            ml_d    = ml_data_zoh(lap_msk);
            ml_t    = ml_time_zoh(lap_msk);

            pit_entry_t       = find_beacon(ml_d, ml_t, 41);
            pit_entry_speed_t = find_beacon(ml_d, ml_t, 42);
            pit_exit_speed_t  = find_beacon(ml_d, ml_t, 48);
            pit_exit_t        = find_beacon(ml_d, ml_t, 49);

            % Lap type from preset transition table (built in step 4)
            has_entry = ~isnan(pit_entry_t);
            has_exit  = ~isnan(pit_exit_t);
            if exist('slice_types_preset', 'var') && k <= numel(slice_types_preset)
                lap_type = slice_types_preset{k};
            else
                % Legacy fallback: classify from beacon presence in window
                if has_entry && has_exit
                    lap_type = 'pitlap';
                elseif has_entry
                    lap_type = 'inlap';
                elseif has_exit
                    lap_type = 'pitlap';
                else
                    lap_type = 'flying';
                end
            end

            laps(k).lap_type          = lap_type;
            laps(k).pit_entry_t       = pit_entry_t;
            laps(k).pit_entry_speed_t = pit_entry_speed_t;
            laps(k).pit_exit_speed_t  = pit_exit_speed_t;
            laps(k).pit_exit_t        = pit_exit_t;

            % Build pit_segment when we have both entry and exit
            if has_entry && has_exit
                laps(k).pit_segment = build_pit_segment(laps(k).channels, pit_entry_t, pit_exit_t);
            else
                laps(k).pit_segment = [];
            end

        elseif br2_mode
            % ---- Mode B: BR2_Beacon_Number long-900 pulse ----
            % Find any long-900 event whose pulse overlaps this lap window.
            lap_dur   = t_e - t_s;
            pit_entry_t = NaN;
            pit_exit_t  = NaN;
            lap_type    = 'flying';  % default until proven otherwise

            % Classify from boundary event type flags (highest priority).
            if br2_ends_at_pitin_v(k)
                % Lap ends at pit entry → inlap; pit entry = t_e
                lap_type    = 'inlap';
                pit_entry_t = t_e;
            elseif br2_starts_at_pitin_v(k) || br2_ends_at_pitout_v(k)
                % Starts at pit entry OR ends at pit exit → pitlap
                lap_type = 'pitlap';
                if br2_starts_at_pitin_v(k), pit_entry_t = t_s; end
            elseif br2_starts_at_pitout_v(k)
                % Starts at beacon→900 transition → outlap
                % pit_exit_t = end of the garage run that began at t_s
                lap_type = 'outlap';
                if exist('br2_pit900_t0', 'var') && ~isempty(br2_pit900_t0)
                    run_idx  = find(abs(br2_pit900_t0 - t_s) < 0.1, 1);
                    if ~isempty(run_idx)
                        pit_exit_t = br2_pit900_t1(run_idx);
                    end
                end
            end

            % Check for garage run (900-hold) overlapping this lap window
            % to populate pit_entry_t / pit_exit_t fields where not already set.
            % Use strict > t_s so the outlap (which starts at t_s=pit_exit) is
            % not re-attributed with the run that just ended.
            if ~exist('br2_pit900_t0', 'var'), br2_pit900_t0 = []; br2_pit900_t1 = []; end
            for pi = 1:numel(br2_pit900_t0)
                p0 = br2_pit900_t0(pi);
                p1 = br2_pit900_t1(pi);
                if p1 > t_s && p0 < t_e
                    if isnan(pit_exit_t),  pit_exit_t  = p1; end
                    if isnan(pit_entry_t), pit_entry_t = p0; end
                    break;
                end
            end

            % Also check for a pitin event strictly inside this lap (edge case
            % where boundary injection did not fire but pit-in detection did).
            if strcmp(lap_type, 'flying')
                pitin_in_lap = br2_pitin_t(br2_pitin_t > t_s & br2_pitin_t < t_e);
                if ~isempty(pitin_in_lap)
                    lap_type    = 'inlap';
                    pit_entry_t = pitin_in_lap(1);
                end
            end

            % Legacy fallback: session-start pit or undetected pit entry.
            if strcmp(lap_type, 'flying') && ~isnan(pit_exit_t) && ...
                    (isnan(pit_entry_t) || pit_entry_t <= t_s + BR2_PIT_MIN_S)
                lap_type = 'pitlap';
            end

            laps(k).lap_type          = lap_type;
            laps(k).pit_entry_t       = pit_entry_t;
            laps(k).pit_entry_speed_t = NaN;   % not available from BR2
            laps(k).pit_exit_speed_t  = NaN;   % not available from BR2
            laps(k).pit_exit_t        = pit_exit_t;

            if ~isnan(pit_entry_t) && ~isnan(pit_exit_t)
                laps(k).pit_segment = build_pit_segment(laps(k).channels, pit_entry_t, pit_exit_t);
            else
                laps(k).pit_segment = [];
            end

        else
            % ---- Mode C: no pit awareness ----
            laps(k).lap_type          = '';
            laps(k).pit_entry_t       = NaN;
            laps(k).pit_entry_speed_t = NaN;
            laps(k).pit_exit_speed_t  = NaN;
            laps(k).pit_exit_t        = NaN;
            laps(k).pit_segment       = [];
        end

        if verbose
            if detect_pitlane || br2_mode
                fprintf('  %-6d  %-10.2f  %-10.2f  %-12.3f  %-18s  %s\n', ...
                    lap_n, t_s, t_e, dur, dur_source, laps(k).lap_type);
            else
                fprintf('  %-6d  %-10.2f  %-10.2f  %-12.3f  %s\n', ...
                    lap_n, t_s, t_e, dur, dur_source);
            end
        end
    end

    % ------------------------------------------------------------------
    %  6b. Sequence pass — label outlaps by position (Modes A and B).
    %      Flying lap immediately after an inlap/pitlap = outlap.
    %      First lap of the session = outlap.
    %      In Mode B: pit stop cycles now produce inlap→pitlap→outlap slices
    %      directly from boundaries; the inlap-after-pitlap guard below is
    %      retained as a safety net for edge cases (signal residue etc.).
    % ------------------------------------------------------------------
    if detect_pitlane || br2_mode
        for k = 2:numel(laps)
            prev_type = laps(k-1).lap_type;
            if strcmp(laps(k).lap_type, 'flying') && ...
               (strcmp(prev_type, 'pitlap') || strcmp(prev_type, 'inlap'))
                laps(k).lap_type = 'outlap';
                % Mode B: only use S/F crossing as pit_exit fallback if
                % Pass 2 garage-run detection did not already set it.
                if br2_mode && ~isnan(laps(k-1).pit_entry_t) && isnan(laps(k-1).pit_exit_t)
                    laps(k-1).pit_exit_t = laps(k).t_start;
                    laps(k-1).pit_segment = build_pit_segment( ...
                        laps(k-1).channels, laps(k-1).pit_entry_t, laps(k).t_start);
                end
            elseif br2_mode && strcmp(laps(k).lap_type, 'inlap') && strcmp(prev_type, 'pitlap')
                % A pit-in detection on the lap immediately following a
                % pitlap is a false positive (999→900/0 signal residue
                % from the recent pit exit).  Force outlap and clear.
                laps(k).lap_type    = 'outlap';
                laps(k).pit_entry_t = NaN;
                laps(k).pit_exit_t  = NaN;
                laps(k).pit_segment = [];
            end
        end
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
        % Time classification for flying / unclassified laps only.
        % Skipped in Modes A and B — those types are authoritative from
        % the physical beacon / BR2 sequence.
        beacon_mode_active = (exist('slice_types_preset', 'var') && ~isempty(slice_types_preset)) || br2_mode;
        if ismember(laps(k).lap_type, {'flying', ''}) && ~beacon_mode_active
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
        t0_enrich = tic;
        laps = enrich_with_distance(laps, verbose);
        fprintf('  enrich_with_distance: %.2fs\n', toc(t0_enrich));
        % laps = enrich_with_distance(laps, verbose);
    
        % ------------------------------------------------------------------
        %  9. Beacon check plot (diagnostic)
        % ------------------------------------------------------------------
    % beacon_check = 1;
    % if beacon_check
    % if ~exist('br2_field_orig', 'var'), br2_field_orig = br2_field; end
    %     fig = beacon_check_plot(session, laps, boundary_mode, lap_num_data, lap_num_time, beacon_label);
    %     waitfor(fig);
    % end
    beacon_check = 0; 
    if beacon_check
        if ~exist('br2_field_orig', 'var'), br2_field_orig = boundary_mode; end
    
        driver_str = get_opt(opts, 'driver_name', '');
        car_str    = get_opt(opts, 'car_number',  '');
        label_full = beacon_label;
        if ~isempty(driver_str)
            label_full = sprintf('%s — %s', label_full, driver_str);
        end
        if ~isempty(car_str)
            label_full = sprintf('%s — #%s', label_full, car_str);
        end
    
        fig = beacon_check_plot(session, laps, br2_field_orig, lap_num_data, lap_num_time, label_full);
    
        % Save PDF (appended into one combined file)
        if get_opt(opts, 'save_beacon_pdf', false)
            pdf_dir  = get_opt(opts, 'beacon_pdf_dir', pwd);
            pdf_name = get_opt(opts, 'beacon_pdf_name', 'beacon_checks_combined.pdf');
            if ~exist(pdf_dir, 'dir'), mkdir(pdf_dir); end
            pdf_path = fullfile(pdf_dir, pdf_name);
    
            % Delete stale combined file on first call of a fresh compile run
            if get_opt(opts, 'beacon_pdf_reset', false) && exist(pdf_path, 'file')
                delete(pdf_path);
            end
    
            exportgraphics(fig, pdf_path, 'ContentType', 'vector', 'Append', true);
            fprintf('  [INFO] Beacon check appended: %s\n', pdf_path);
        end
    
        % if get_opt(opts, 'beacon_check_pause', true)
        %     waitfor(fig);
        % else
        %     close(fig);
        % end
    end
end
%% beacon_check_plot(session, laps, 'MyLaps_X2TRA_DeviceShortId, lap_num_data, lap_num_time, beacon_label)

% ======================================================================= %
% function laps = enrich_with_distance(laps, verbose)
% % ENRICH_WITH_DISTANCE  Add .dist (metres) to every channel by resampling
% %                       onto the master distance grid.
% %
% % Distance source priority:
% %   1. Ground_Speed  — integrated via cumtrapz, zeroed at beacon (t=0).
% %                      Cleanest option: no cross-lap contamination, starts
% %                      exactly at 0 regardless of odometer state.
% %   2. Corr_Dist     — corrected cumulative distance, zeroed at first sample
% %   3. Odometer      — cumulative, zeroed at first sample
% 
%     SPEED_CANDIDATES = {'Ground_Speed'};
%     DIST_CANDIDATES  = {'Corr_Dist', 'Odometer'};
% 
%     if isempty(laps), return; end
% 
%     for k = 1:numel(laps)
%         ch_names        = fieldnames(laps(k).channels);
%         dist_field      = '';
%         dist_source     = '';
%         use_integration = false;
% 
%         % PRIMARY: integrate Ground_Speed — clean zero at beacon
%         for i = 1:numel(SPEED_CANDIDATES)
%             f = find_ch_field_local(laps(k).channels, SPEED_CANDIDATES{i});
%             if ~isempty(f)
%                 dist_field      = f;
%                 dist_source     = SPEED_CANDIDATES{i};
%                 use_integration = true;
%                 break;
%             end
%         end
% 
%         % FALLBACK: use a distance channel if no speed channel found
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
%         if isempty(dist_field)
%             if verbose
%                 fprintf('  [WARN] Lap %d: no speed or distance channel — .dist not added.\n', ...
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
%         if numel(t_master) < 2
%             if verbose
%                 fprintf('  [WARN] Lap %d: speed/distance channel has < 2 samples — .dist not added.\n', ...
%                     laps(k).lap_number);
%             end
%             continue;
%         end
% 
%         if use_integration
%             % Integrate Ground_Speed (km/h -> m/s), zero at beacon (t=0)
%             zero_idx = find(t_master >= 0, 1);
%             if isempty(zero_idx), zero_idx = 1; end
%             speed_ms = max(d_raw, 0) / 3.6;
%             d_master = cumtrapz(t_master, speed_ms);
%             d_master = d_master - d_master(zero_idx);
%         else
%             % Zero distance at first sample
%             d_master = d_raw - d_raw(1);
%         end
% 
%         if verbose && k == 1
%             if use_integration
%                 fprintf('  [INFO] Distance: integrating %s (%.0f Hz)\n', ...
%                     dist_source, laps(k).channels.(dist_field).sample_rate);
%             else
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
%                 fprintf('  [WARN] Lap %d: distance has < 2 monotonic points.\n', ...
%                     laps(k).lap_number);
%             end
%             continue;
%         end
% 
%         % ---- Resample all channels onto master distance time grid ----
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
%             t_lo      = max(t_master(1),  t_ch_u(1));
%             t_hi      = min(t_master(end), t_ch_u(end));
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
%
% PERFORMANCE NOTE (rewritten): channels are grouped by identical time
% vector before interpolation. Channels sharing a sample rate typically
% share an exact time array (same acquisition, same formula), so instead
% of calling unique()+interp1() once per channel (~1000+ individual calls
% per lap), we call it once per DISTINCT time vector and interpolate all
% channels in that group in a single batched interp1 call. Same math,
% same result per channel — only the call count changes. Groups are
% verified with isequal before batching, so a hash collision or unusual
% edge case falls back safely rather than silently producing wrong output.

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

        % ------------------------------------------------------------
        %  Group channels by identical time vector, then batch-interp
        % ------------------------------------------------------------
        n_ch = numel(ch_names);

        % Channels with < 2 samples: NaN out immediately, same as original.
        keep_mask = false(n_ch, 1);
        for c = 1:n_ch
            fn = ch_names{c};
            ch = laps(k).channels.(fn);
            if numel(ch.time) < 2
                laps(k).channels.(fn).dist = NaN(size(ch.data(:)));
            else
                keep_mask(c) = true;
            end
        end
        active_names = ch_names(keep_mask);
        n_active = numel(active_names);

        % Build a cheap grouping key per channel: length + first/last time
        % value. Channels with identical keys are verified with isequal
        % before being batched — this makes the grouping safe even if two
        % genuinely different time vectors happen to share length/endpoints.
        group_key = strings(n_active, 1);
        for c = 1:n_active
            t_ch = laps(k).channels.(active_names{c}).time(:);
            group_key(c) = sprintf('%d_%.9g_%.9g', numel(t_ch), t_ch(1), t_ch(end));
        end

        [uniq_keys, ~, key_idx] = unique(group_key);

        for g = 1:numel(uniq_keys)
            members = find(key_idx == g);   % indices into active_names sharing this key

            % Verify true equality within the group (guards against hash collision)
            t_ref = laps(k).channels.(active_names{members(1)}).time(:);
            same_time = true(numel(members), 1);
            for m = 2:numel(members)
                t_m = laps(k).channels.(active_names{members(m)}).time(:);
                if ~isequal(t_m, t_ref)
                    same_time(m) = false;
                end
            end

            batch_idx   = members(same_time);
            solo_idx    = members(~same_time);

            % ---- Batched path: all channels in batch_idx share t_ref exactly ----
            if ~isempty(batch_idx)
                [t_ch_u, ia] = unique(t_ref, 'stable');

                t_lo = max(t_master(1),  t_ch_u(1));
                t_hi = min(t_master(end), t_ch_u(end));
                in_range = t_master >= t_lo & t_master <= t_hi;

                n_batch = numel(batch_idx);
                D = NaN(numel(t_ch_u), n_batch);
                for bi = 1:n_batch
                    fn = active_names{batch_idx(bi)};
                    d_full = laps(k).channels.(fn).data(:);
                    D(:, bi) = d_full(ia);
                end

                data_out = NaN(numel(t_master), n_batch);
                if t_lo < t_hi
                    data_out(in_range, :) = interp1(t_ch_u, D, t_master(in_range), 'linear', NaN);
                end

                for bi = 1:n_batch
                    fn = active_names{batch_idx(bi)};
                    laps(k).channels.(fn).data = data_out(:, bi);
                    laps(k).channels.(fn).time = t_master;
                    laps(k).channels.(fn).dist = d_master;
                end
            end

            % ---- Fallback path: any hash-collision mismatches, one at a time ----
            for si = 1:numel(solo_idx)
                fn   = active_names{solo_idx(si)};
                ch   = laps(k).channels.(fn);
                t_ch = ch.time(:);
                d_ch = ch.data(:);

                [t_ch_u, ia] = unique(t_ch, 'stable');
                d_ch_u = d_ch(ia);

                t_lo = max(t_master(1),  t_ch_u(1));
                t_hi = min(t_master(end), t_ch_u(end));
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
function ps = build_pit_segment(channels, pit_entry_t, pit_exit_t)
% BUILD_PIT_SEGMENT  Sub-slice all channels to [pit_entry_t, pit_exit_t].
%                    .time is zeroed to pit_entry_t (0 = pit entry).
%                    Used by both Mode A (MyLaps) and Mode B (BR2).
    ps          = struct();
    ps.t_start  = pit_entry_t;
    ps.t_end    = pit_exit_t;
    ps.duration = pit_exit_t - pit_entry_t;
    ps.channels = struct();
    seg_ch_names = fieldnames(channels);
    for sc = 1:numel(seg_ch_names)
        sfn = seg_ch_names{sc};
        sch = channels.(sfn);
        if isfield(sch, 'time_abs')
            smsk            = sch.time_abs >= pit_entry_t & sch.time_abs <= pit_exit_t;
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
function [data_out, time_out] = beacon_to_zoh(data, time, min_hold_s)
% BEACON_TO_ZOH  Reconstruct a linearly-interpolated beacon channel as a
%                zero-order-hold step function.  Walks runs of equal rounded
%                integer values; discards any run held for < min_hold_s
%                seconds (ramp pass-throughs).  Returns the first sample
%                of each accepted run (the transition point).
    data = data(:);   % ensure column
    time = time(:);
    data_out = zeros(0, 1, 'like', data);
    time_out = zeros(0, 1, 'like', time);
    n = numel(data);
    if n == 0, return; end

    run_start = 1;
    for i = 2:n
        at_end = (i == n);
        if data(i) ~= data(i-1) || at_end
            run_end = i - 1;
            if at_end && data(i) == data(i-1), run_end = n; end
            hold_dur = time(run_end) - time(run_start);
            % Always keep the very first run (session init value).
            if hold_dur >= min_hold_s || run_start == 1
                data_out(end+1) = data(run_start); %#ok<AGROW>
                time_out(end+1) = time(run_start); %#ok<AGROW>
            end
            run_start = i;
        end
    end
    % Catch a trailing run not yet emitted
    if isempty(time_out) || time_out(end) ~= time(run_start)
        data_out(end+1) = data(run_start); % #ok<AGROW>
        time_out(end+1) = time(run_start); % #ok<AGROW>
    end
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


% ======================================================================= %
function fig = beacon_check_plot(session, laps, br2_field, lap_num_data, lap_num_time, label)
% BEACON_CHECK_PLOT  Diagnostic figure for troubleshooting lap boundary
%                    detection. Shows the full-session beacon channel and
%                    Lap_Number against detected lap boundaries coloured by
%                    lap type.

    if nargin < 6 || isempty(label), label = ''; end

    if isempty(label)
        fig_title = 'Lap Slicer — Beacon Check';
    else
        fig_title = sprintf('Beacon Check — %s', replace(label, "_", " "));
    end

    TYPE_COLORS = struct( ...
        'flying',  [0.18 0.55 0.18], ...   % green
        'outlap',  [0.20 0.45 0.80], ...   % blue
        'inlap',   [0.90 0.55 0.10], ...   % orange
        'pitlap',  [0.70 0.15 0.70], ...   % purple
        'fcy',     [0.95 0.80 0.00], ...   % yellow
        'slow',    [0.55 0.55 0.55], ...   % grey
        'long',    [0.85 0.15 0.15], ...   % red
        'x',       [0.80 0.80 0.80]);      % fallback (empty string type)

    fig = figure('Name', fig_title, ...
                 'NumberTitle', 'off', ...
                 'Color', [0.12 0.12 0.12], ...
                 'Position', [60 60 1400 700], ...
                 'Visible','on');
    sgtitle(fig, fig_title, 'Color', [0.95 0.95 0.95], 'FontSize', 13, 'FontWeight', 'bold');
    n_rows = 3 + (~isempty(br2_field));   % beacon, speed, lap_number, summary
    ax = gobjects(n_rows, 1);
    for r = 1:n_rows
        ax(r) = subplot(n_rows, 1, r, 'Parent', fig);
        set(ax(r), 'Color', [0.16 0.16 0.16], ...
                   'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8], ...
                   'GridColor', [0.35 0.35 0.35], 'GridAlpha', 0.5, ...
                   'XGrid', 'on', 'YGrid', 'on');
        hold(ax(r), 'on');
    end

    row_beacon  = 1;
    row_speed   = 1 + (~isempty(br2_field));
    row_lapnum  = row_speed + 1;
    row_summary = n_rows;

    % ---- Plot BR2 beacon channel ----
    if ~isempty(br2_field)
        br2_t = session.(br2_field).time(:);
        br2_d = session.(br2_field).data(:);
        stairs(ax(row_beacon), br2_t, br2_d, 'Color', [0.3 0.75 1.0], 'LineWidth', 1.2);
        ylabel(ax(row_beacon), br2_field, 'Color', [0.8 0.8 0.8], 'Interpreter', 'none');
        title(ax(row_beacon), 'Beacon Channel (BR2\_Beacon\_Number)', ...
              'Color', [0.9 0.9 0.9], 'FontSize', 10);
    else
        text(ax(row_beacon), 0.5, 0.5, 'BR2 channel not found', ...
             'Units', 'normalized', 'Color', [0.7 0.7 0.7], ...
             'HorizontalAlignment', 'center', 'FontSize', 11);
        title(ax(row_beacon), 'Beacon Channel — NOT FOUND', ...
              'Color', [0.85 0.4 0.4], 'FontSize', 10);
    end

    % ---- Plot speed channel ----
    SPEED_CANDIDATES = {'Ground_Speed', 'Speed', 'Vehicle_Speed', 'Groundspeed'};
    spd_field = '';
    for si = 1:numel(SPEED_CANDIDATES)
        spd_field = find_channel(session, SPEED_CANDIDATES{si}, fieldnames(session));
        if ~isempty(spd_field), break; end
    end
    if ~isempty(spd_field)
        spd_t = session.(spd_field).time(:);
        spd_d = session.(spd_field).data(:);
        plot(ax(row_speed), spd_t, spd_d, 'Color', [0.95 0.95 0.95], 'LineWidth', 0.8);
        ylabel(ax(row_speed), 'Speed (km/h)', 'Color', [0.8 0.8 0.8]);
        title(ax(row_speed), sprintf('Speed — %s', spd_field), ...
              'Color', [0.9 0.9 0.9], 'FontSize', 10, 'Interpreter', 'none');
    else
        text(ax(row_speed), 0.5, 0.5, 'Speed channel not found', ...
             'Units', 'normalized', 'Color', [0.7 0.7 0.7], ...
             'HorizontalAlignment', 'center', 'FontSize', 11);
        title(ax(row_speed), 'Speed — NOT FOUND', ...
              'Color', [0.85 0.4 0.4], 'FontSize', 10);
    end

    % ---- Plot Lap_Number channel ----
    stairs(ax(row_lapnum), lap_num_time, lap_num_data, ...
           'Color', [1.0 0.75 0.2], 'LineWidth', 1.2);
    ylabel(ax(row_lapnum), 'Lap\_Number', 'Color', [0.8 0.8 0.8]);
    title(ax(row_lapnum), 'Lap\_Number channel (reference)', ...
          'Color', [0.9 0.9 0.9], 'FontSize', 10);

    % ---- Draw lap regions (shaded bands) on beacon + lap_number rows ----
    % Done AFTER data is plotted so ylim is correctly scaled.
    type_seen = {};
    for k = 1:numel(laps)
        t0   = laps(k).t_start;
        t1   = laps(k).t_end;
        ltyp = laps(k).lap_type;
        if isempty(ltyp), ltyp = 'x'; end

        if isfield(TYPE_COLORS, ltyp)
            clr = TYPE_COLORS.(ltyp);
        else
            clr = TYPE_COLORS.x;
        end

        for r = [row_beacon, row_speed, row_lapnum]
            yl = ylim(ax(r));
            patch(ax(r), [t0 t1 t1 t0], [yl(1) yl(1) yl(2) yl(2)], ...
                  clr, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
            xline(ax(r), t0, '--', 'Color', [clr, 0.7], 'LineWidth', 0.8);
        end

        % Lap label on beacon row
        t_mid = (t0 + t1) / 2;
        yl    = ylim(ax(row_beacon));
        text(ax(row_beacon), t_mid, yl(2) * 0.92, ...
             sprintf('L%d\n%s', laps(k).lap_number, ltyp), ...
             'Color', clr, 'FontSize', 7, 'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'top', 'Interpreter', 'none');

        if ~ismember(ltyp, type_seen)
            type_seen{end+1} = ltyp; %#ok<AGROW>
        end
    end

    % ---- Summary table row ----
    cla(ax(row_summary));
    set(ax(row_summary), 'Visible', 'off');
    col_headers = {'Lap', 't_start', 't_end', 'Duration(s)', 'Type'};
    col_w       = [0.08, 0.18, 0.18, 0.18, 0.12];
    x_pos       = [0.02, cumsum(col_w(1:end-1)) + 0.02];
    y_top       = 0.95;
    row_h       = min(0.80 / max(numel(laps), 1), 0.075);

    for c = 1:numel(col_headers)
        text(ax(row_summary), x_pos(c), y_top, col_headers{c}, ...
             'Units', 'normalized', 'Color', [0.65 0.85 1.0], ...
             'FontSize', 8, 'FontWeight', 'bold', 'Interpreter', 'none');
    end
    for k = 1:numel(laps)
        ltyp = laps(k).lap_type;
        if isempty(ltyp), ltyp = '—'; end
        if isfield(TYPE_COLORS, ltyp), clr = TYPE_COLORS.(ltyp);
        else, clr = TYPE_COLORS.x; end
        y_row = y_top - k * row_h;
        vals = {sprintf('%d', laps(k).lap_number), ...
                sprintf('%.2f', laps(k).t_start), ...
                sprintf('%.2f', laps(k).t_end), ...
                sprintf('%.3f', laps(k).lap_time), ...
                ltyp};
        for c = 1:numel(vals)
            text(ax(row_summary), x_pos(c), y_row, vals{c}, ...
                 'Units', 'normalized', 'Color', clr, ...
                 'FontSize', 7.5, 'Interpreter', 'none');
        end
    end
    title(ax(row_summary), 'Lap Summary', 'Color', [0.9 0.9 0.9], 'FontSize', 10);

    % ---- Legend ----
    all_types = fieldnames(TYPE_COLORS);
    leg_h = gobjects(0);
    leg_lbl = {};
    for ti = 1:numel(all_types)
        t_name = all_types{ti};
        if strcmp(t_name, 'x'), continue; end
        if ismember(t_name, type_seen)
            leg_h(end+1)   = patch(ax(row_beacon), NaN, NaN, TYPE_COLORS.(t_name), ...
                                   'FaceAlpha', 0.5, 'EdgeColor', 'none'); %#ok<AGROW>
            leg_lbl{end+1} = t_name; %#ok<AGROW>
        end
    end
    if ~isempty(leg_h)
        lg = legend(ax(row_beacon), leg_h, leg_lbl, 'Location', 'northwest', ...
                    'TextColor', [0.85 0.85 0.85], 'Color', [0.18 0.18 0.18]);
        lg.FontSize = 8;
    end

    % ---- Link x-axes (all except summary) ----
    linkaxes(ax(1:n_rows-1), 'x');
    xlabel(ax(row_lapnum), 'Session time (s)', 'Color', [0.8 0.8 0.8]);

    drawnow;
end