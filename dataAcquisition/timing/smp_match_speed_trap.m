function T_match = smp_match_speed_trap(cache, opts)
% SMP_MATCH_SPEED_TRAP  Join timing-sheet entries to MoTeC cache laps.
%
% Loads both top_speed and pit_speed CSVs (where available) and combines
% them into a single table. Speed is extracted as the average of
% Ground_Speed within the MyLaps beacon window for each lap:
%   top_speed  beacon value = 2
%   pit_speed  beacon value = 41
%
% T_match = smp_match_speed_trap(cache, opts)
%
% opts fields (all optional):
%   event            string   filter by event code          (default: all)
%   session          string   filter by session name        (default: all)
%   report_type      string   'top_speed'|'pit_speed'|'both' (default: 'both')
%   master_csv       string   override CSV path (top_speed only)
%   master_pit_csv   string   override CSV path (pit_speed only)
%   timing_base_dir  string   season timing root folder
%   speed_channel    string   MoTeC channel name            (default: 'Ground_Speed')
%   mylaps_channel   string   beacon channel name           (default: 'MyLaps_X2TRA_DeviceShortId')
%   beacon_top       double   beacon value for top speed    (default: 2)
%   beacon_pit       double   beacon value for pit speed    (default: 41)
%
% Returns table with columns:
%   car, driver, session, lap, trap_type,
%   timing_kph, motec_kph, delta_kph,
%   group_key, matched, vehicle
%   speed_channel string    MoTeC channel name        (default: 'Ground_Speed')
%
% Returns table with columns:
%   car, driver, session, lap, timing_kph, motec_kph, delta_kph,
%   group_key, matched, vehicle

    if nargin < 2 || isempty(opts), opts = struct(); end

    event_filt   = get_opt(opts, 'event',            '');
    ses_filt     = get_opt(opts, 'session',           '');
    rep_type     = get_opt(opts, 'report_type',       'top_speed');
    master_csv   = get_opt(opts, 'master_csv',        '');
    base_dir     = get_opt(opts, 'timing_base_dir',   '');
    speed_ch     = get_opt(opts, 'speed_channel',     'Ground_Speed');
    mylaps_ch    = get_opt(opts, 'mylaps_channel',    'MyLaps_X2TRA_DeviceShortId');
    press_chs    = get_opt(opts, 'press_channels',    {'TPM1S_FL_WS_PRESS','TPM1S_FR_WS_PRESS', ...
                                                        'TPM1S_RL_WS_PRESS','TPM1S_RR_WS_PRESS'});
    wheel_chs    = get_opt(opts, 'wheel_speed_channels', {'Wheel_Speed_Front_Left','Wheel_Speed_Front_Right', ...
                                                          'Wheel_Speed_Rear_Left','Wheel_Speed_Rear_Right'});
    accel_chs    = get_opt(opts, 'accel_channels',    {'ADR_Acceleration_X'});
    % Pressure scale: ld stores kPa/10; MoTeC i2 displays psi. 10*0.14504 = 1.4504
    press_scale  = get_opt(opts, 'press_scale',       10 * 0.14504);
    skip_pit_lap = get_opt(opts, 'skip_pit_lap',      false);
    pit_trap_col = get_opt(opts, 'pit_trap_col',      '');
    pit_trap_n_v = get_opt(opts, 'pit_trap_n',        1);

    % ── Resolve CSV path & speed column ──────────────────────────────────────
    timing_dir = fileparts(mfilename('fullpath'));
    if strcmp(rep_type, 'pit_speed')
        kph_col = 's1_kph';
        if ~isempty(pit_trap_col)
            kph_col = pit_trap_col;
        end
        if isempty(master_csv)
            if ~isempty(base_dir) && ~isempty(event_filt) && ~isempty(ses_filt)
                master_csv = resolve_timing_csv(base_dir, event_filt, ses_filt, 'pit_speed');
            else
                master_csv = fullfile(timing_dir, 'master_pit_speed.csv');
            end
        end
    else
        kph_col = 'kph';
        if isempty(master_csv)
            if ~isempty(base_dir) && ~isempty(event_filt) && ~isempty(ses_filt)
                master_csv = resolve_timing_csv(base_dir, event_filt, ses_filt, 'top_speed');
            else
                master_csv = fullfile(timing_dir, 'master_topspeed.csv');
            end
        end
    end

    if ~isfile(master_csv)
        error('smp_match_speed_trap: CSV not found:\n  %s', master_csv);
    end

    % ── Load and clean timing CSV ─────────────────────────────────────────────
    T = readtable(master_csv, 'Delimiter', ',', 'TextType', 'string');

    if ismember('parse_error', T.Properties.VariableNames)
        T = T(~strcmpi(string(T.parse_error), 'true'), :);
    end

    if ~isempty(event_filt)
        T = T(strcmpi(string(T.event), event_filt), :);
    end
    if ~isempty(ses_filt)
        T = T(strcmpi(string(T.session), ses_filt), :);
    end

    if height(T) == 0
        T_match = make_empty_table();
        return;
    end

    % Coerce types
    T.car = strtrim(string(T.car));
    if ~isnumeric(T.lap)
        T.lap = str2double(string(T.lap));
    end
    if ~ismember(kph_col, T.Properties.VariableNames)
        error('smp_match_speed_trap: column ''%s'' not found in CSV ''%s''.', ...
              kph_col, master_csv);
    end
    if ~isnumeric(T.(kph_col))
        T.(kph_col) = str2double(string(T.(kph_col)));
    end

    % ── Normalise to common column names expected by match_rows ───────────────
    if ~strcmp(kph_col, 'kph')
        T.kph = T.(kph_col);
    end
    if strcmp(rep_type, 'pit_speed')
        trap_type_val = "pit_speed";
        beacon_val_num = get_opt(opts, 'beacon_pit', 41);
    else
        trap_type_val = "top_speed";
        beacon_val_num = get_opt(opts, 'beacon_top', 2);
    end
    T.trap_type = repmat(trap_type_val, height(T), 1);
    T.beacon_val = repmat(double(beacon_val_num), height(T), 1);

    % ── Assign pit_stop_n (rank per car by ascending lap) for pit_speed rows ──────
    if strcmp(rep_type, 'pit_speed')
        T.pit_stop_n = zeros(height(T), 1);
        pit_cars_r = unique(T.car);
        for pci_r = 1:numel(pit_cars_r)
            pc_mask_r = strcmp(T.car, pit_cars_r(pci_r));
            [~, rank_ord_r] = sort(T.lap(pc_mask_r));
            idx_r = find(pc_mask_r);
            for ri_r = 1:numel(rank_ord_r)
                T.pit_stop_n(idx_r(rank_ord_r(ri_r))) = ri_r;
            end
        end
    end
    if ~strcmp(rep_type, 'pit_speed') && ~skip_pit_lap
        pit_csv = get_opt(opts, 'master_pit_csv', '');
        if isempty(pit_csv)
            if ~isempty(base_dir) && ~isempty(event_filt) && ~isempty(ses_filt)
                pit_csv = resolve_timing_csv(base_dir, event_filt, ses_filt, 'pit_speed');
            else
                pit_csv = fullfile(timing_dir, 'master_pit_speed.csv');
            end
        end
        if isfile(pit_csv)
            T_pit = readtable(pit_csv, 'Delimiter', ',', 'TextType', 'string');
            if ismember('parse_error', T_pit.Properties.VariableNames)
                T_pit = T_pit(~strcmpi(string(T_pit.parse_error), 'true'), :);
            end
            if ~isempty(event_filt)
                T_pit = T_pit(strcmpi(string(T_pit.event), event_filt), :);
            end
            if ~isempty(ses_filt)
                T_pit = T_pit(strcmpi(string(T_pit.session), ses_filt), :);
            end
            if height(T_pit) > 0
                T_pit.car = strtrim(string(T_pit.car));
                if ~isnumeric(T_pit.lap), T_pit.lap = str2double(string(T_pit.lap)); end
                % Resolve kph column: try s1_kph, then kph, then any *kph* column
                pit_vars = T_pit.Properties.VariableNames;
                if ~isempty(pit_trap_col) && ismember(pit_trap_col, pit_vars)
                    pit_kph_src = pit_trap_col;
                elseif ismember('s1_kph', pit_vars)
                    pit_kph_src = 's1_kph';
                elseif ismember('kph', pit_vars)
                    pit_kph_src = 'kph';
                else
                    kph_candidates = pit_vars(~cellfun(@isempty, regexpi(pit_vars, 'kph')));
                    if ~isempty(kph_candidates)
                        pit_kph_src = kph_candidates{1};
                        fprintf('[smp_match_speed_trap] pit_speed: using ''%s'' as kph column\n', pit_kph_src);
                    else
                        fprintf('[smp_match_speed_trap] pit_speed CSV has no kph column — skipping\n');
                        pit_kph_src = '';
                    end
                end
                if ~isempty(pit_kph_src)
                    if ~isnumeric(T_pit.(pit_kph_src))
                        T_pit.(pit_kph_src) = str2double(string(T_pit.(pit_kph_src)));
                    end
                    T_pit.kph        = T_pit.(pit_kph_src);
                    T_pit.trap_type  = repmat("pit_speed", height(T_pit), 1);
                    T_pit.beacon_val = repmat(double(get_opt(opts, 'beacon_pit', 41)), height(T_pit), 1);
                    % Add pit_stop_n: rank each row per car/session by ascending lap number
                    T_pit.pit_stop_n = zeros(height(T_pit), 1);
                    pit_cars = unique(T_pit.car);
                    for pci = 1:numel(pit_cars)
                        pc_mask = strcmp(T_pit.car, pit_cars(pci));
                        [~, rank_ord] = sort(T_pit.lap(pc_mask));
                        idx = find(pc_mask);
                        for ri = 1:numel(rank_ord)
                            T_pit.pit_stop_n(idx(rank_ord(ri))) = ri;
                        end
                    end
                    T_pit = align_pit_table(T_pit, T);
                    T     = align_pit_table(T, T_pit);
                    T = [T; T_pit]; %#ok<AGROW>
                    fprintf('[smp_match_speed_trap] Appended %d pit_speed rows.\n', height(T_pit));
                end
            end
        else
            fprintf('[smp_match_speed_trap] No pit_speed CSV at: %s (skipping)\n', pit_csv);
        end
    end

    % ── Pre-build manifest lookup vectors ─────────────────────────────────────
    mf     = cache.manifest;
    mf_car = strtrim(string(mf.CarNumber));
    mf_ses = string(mf.Session);
    mf_gk  = string(mf.GroupKey);

    % ── First pass: direct lap match ─────────────────────────────────────────
    results = match_rows(T, mf_car, mf_ses, mf_gk, cache, speed_ch, mylaps_ch, press_chs, wheel_chs, accel_chs, press_scale, 0);

    % ── Offset fallback: if match rate < 20%, retry with timing.lap - 1 ──────
    n_total   = height(results);
    n_matched = sum(results.matched);
    if n_total > 0 && (n_matched / n_total) < 0.2
        results_off = match_rows(T, mf_car, mf_ses, mf_gk, cache, speed_ch, mylaps_ch, press_chs, wheel_chs, accel_chs, press_scale, -1);
        if sum(results_off.matched) > n_matched
            results = results_off;
            fprintf(['[smp_match_speed_trap] WARNING: offset -1 applied — ' ...
                     'timing lap numbers appear 1-based vs 0-indexed MoTeC laps.\n']);
        end
    end

    T_match = results;
    T_match.pit_trap_n = repmat(int32(pit_trap_n_v), height(T_match), 1);
end

% ─────────────────────────────────────────────────────────────────────────────

function T_out = match_rows(T, mf_car, mf_ses, mf_gk, cache, speed_ch, mylaps_ch, press_chs, wheel_chs, accel_chs, press_scale, offset)

    n = height(T);

    % Pre-compute valid field names for pressure channels
    n_press      = numel(press_chs);
    press_valid  = cellfun(@matlab.lang.makeValidName, press_chs, 'UniformOutput', false);
    press_cols   = cell(1, n_press);   % will hold nan(n,1) arrays
    for pi = 1:n_press
        press_cols{pi} = nan(n, 1);
    end

    % Pre-compute valid field names for wheel speed channels
    n_wheel     = numel(wheel_chs);
    wheel_valid = cellfun(@matlab.lang.makeValidName, wheel_chs, 'UniformOutput', false);
    wheel_cols  = cell(1, n_wheel);   % will hold nan(n,1) arrays
    for wi = 1:n_wheel
        wheel_cols{wi} = nan(n, 1);
    end

    % Pre-compute valid field names for acceleration channels
    n_accel     = numel(accel_chs);
    accel_valid = cellfun(@matlab.lang.makeValidName, accel_chs, 'UniformOutput', false);
    accel_cols  = cell(1, n_accel);
    for ai = 1:n_accel
        accel_cols{ai} = nan(n, 1);
    end

    car_col       = strings(n, 1);
    driver_col    = strings(n, 1);
    session_col   = strings(n, 1);
    vehicle_col   = strings(n, 1);
    trap_type_col = strings(n, 1);
    lap_col          = zeros(n, 1);
    timing_kph       = nan(n, 1);
    motec_kph        = nan(n, 1);
    delta_kph        = nan(n, 1);
    lap_time_col     = nan(n, 1);
    motec_lap_num_col = nan(n, 1);
    motec_lap_type_col = strings(n, 1);
    group_key_col    = strings(n, 1);
    matched_col   = false(n, 1);

    has_driver  = ismember('driver',  T.Properties.VariableNames);
    has_vehicle = ismember('vehicle', T.Properties.VariableNames);
    spd_valid   = matlab.lang.makeValidName(speed_ch);
    bkn_valid   = matlab.lang.makeValidName(mylaps_ch);

    for i = 1:n
        car_str    = T.car(i);
        ses_str    = string(T.session(i));
        lap_target = T.lap(i) + offset;
        t_kph      = T.kph(i);
        bkn_val    = T.beacon_val(i);

        car_col(i)       = car_str;
        session_col(i)   = ses_str;
        lap_col(i)       = T.lap(i);
        timing_kph(i)    = t_kph;
        trap_type_col(i) = T.trap_type(i);

        if has_driver,  driver_col(i)  = string(T.driver(i));  end
        if has_vehicle, vehicle_col(i) = string(T.vehicle(i)); end

        if isnan(lap_target) || isnan(t_kph), continue; end

        % Manifest lookup
        car_mask = strcmpi(mf_car, car_str);
        ses_mask = strcmpi(mf_ses, ses_str);
        gks      = unique(mf_gk(car_mask & ses_mask));

        for gi = 1:numel(gks)
            gk = char(gks(gi));
            if ~isfield(cache.traces, gk), continue; end
            tr = cache.traces.(gk);
            if ~isfield(tr, 'lap_numbers'), continue; end

            is_pit_row = strcmp(T.trap_type(i), 'pit_speed');
            if is_pit_row
                % Match Nth pit_speed CSV row → Nth 'pitlap' in MoTeC (chronological order)
                % Pit lane speed beacon fires during the pitlap (lap entirely within pit lane)
                pit_n = 1;
                if ismember('pit_stop_n', T.Properties.VariableNames)
                    pit_n = T.pit_stop_n(i);
                end
                k = nth_pitlap_idx(tr, pit_n);
            else
                % timing-lap → trace index, skipping MoTeC pitlap laps
                k = timing_lap_to_trace_idx(tr, lap_target, 0);
            end
            if isempty(k), continue; end

            group_key_col(i) = gk;

            mk = extract_trap_speed(tr, k, spd_valid, bkn_valid, bkn_val);
            if ~isnan(mk)
                motec_kph(i)   = mk;
                delta_kph(i)   = t_kph - mk;
                matched_col(i) = true;
            end
            if isfield(tr, 'lap_times') && numel(tr.lap_times) >= k
                lap_time_col(i) = tr.lap_times(k);
            end
            motec_lap_num_col(i) = tr.lap_numbers(k);
            if isfield(tr, 'lap_types') && numel(tr.lap_types) >= k
                motec_lap_type_col(i) = string(tr.lap_types{k});
            end
            % Average each pressure channel over the beacon window, then scale to psi
            for pi = 1:n_press
                fld = press_valid{pi};
                pv  = extract_channel_at_trap(tr, k, fld, bkn_valid, bkn_val);
                if ~isnan(pv)
                    pv = pv * press_scale;
                end
                press_cols{pi}(i) = pv;
            end
            % Average each wheel speed channel over the beacon window, normalise to kph
            for wi = 1:n_wheel
                fld = wheel_valid{wi};
                wv  = extract_channel_at_trap(tr, k, fld, bkn_valid, bkn_val);
                if ~isnan(wv) && wv < 10   % assume m/s if < 10 — convert to kph
                    wv = wv * 3.6;
                end
                wheel_cols{wi}(i) = wv;
            end
            % Average each acceleration channel over the beacon window
            for ai = 1:n_accel
                fld = accel_valid{ai};
                accel_cols{ai}(i) = extract_channel_at_trap(tr, k, fld, bkn_valid, bkn_val);
            end
            break;
        end
    end

    T_out = table(car_col, driver_col, session_col, lap_col, trap_type_col, ...
                  timing_kph, motec_kph, delta_kph, lap_time_col, ...
                  motec_lap_num_col, motec_lap_type_col, ...
                  group_key_col, matched_col, vehicle_col, ...
                  'VariableNames', {'car','driver','session','lap','trap_type', ...
                                    'timing_kph','motec_kph','delta_kph','lap_time_s', ...
                                    'motec_lap','motec_lap_type', ...
                                    'group_key','matched','vehicle'});
    % Append pressure columns
    for pi = 1:n_press
        col_name = lower(press_valid{pi});
        T_out.(col_name) = press_cols{pi};
    end
    % Append wheel speed columns (prefix ws_)
    for wi = 1:n_wheel
        col_name = ['ws_' lower(wheel_valid{wi})];
        T_out.(col_name) = wheel_cols{wi};
    end
    % Append acceleration columns (prefix accel_)
    for ai = 1:n_accel
        col_name = ['accel_' lower(accel_valid{ai})];
        T_out.(col_name) = accel_cols{ai};
    end
end

% ─────────────────────────────────────────────────────────────────────────────

function k = timing_lap_to_trace_idx(tr, timing_lap, offset)
% Map a timing CSV lap number to a trace index k, skipping pit-lane laps.
%
% MoTeC counts pit-lane laps (car travels through pit lane and never crosses
% the timing beacon). The timing system never records those as laps, so a
% "+1" offset accumulates after every pit stop.
%
% Strategy: sort MoTeC laps by lap_number; remove pit-only laps; the
% remaining laps are numbered sequentially from 1 as seen by the timing
% system.  Return the trace index k (position in tr.lap_numbers) of the
% lap that matches timing_lap + offset.
%
% 'pit_lap' is the MoTeC lap_type name for a lap driven entirely in pit lane.

    k = [];
    lap_nums = tr.lap_numbers(:);      % MoTeC lap numbers, order as stored
    n = numel(lap_nums);

    % Get lap types (default to 'flying' if not stored)
    if isfield(tr, 'lap_types') && numel(tr.lap_types) == n
        lap_types = tr.lap_types(:);
    else
        lap_types = repmat({'flying'}, n, 1);
    end

    % Sort by lap number so sequential numbering is correct
    [sorted_nums, sort_idx] = sort(lap_nums);
    sorted_types = lap_types(sort_idx);

    % Assign a timing lap number to each MoTeC lap, skipping pit-only laps
    timing_num = 0;
    timing_map = zeros(numel(sorted_nums), 1);   % timing lap → position in sorted list
    for j = 1:numel(sorted_nums)
        if strcmpi(sorted_types{j}, 'pitlap')
            timing_map(j) = NaN;   % invisible to timing
        else
            timing_num = timing_num + 1;
            timing_map(j) = timing_num;
        end
    end

    target = timing_lap + offset;
    match  = find(timing_map == target, 1);
    if isempty(match), return; end

    % Convert back to original (unsorted) trace index
    original_sorted_idx = sort_idx(match);
    k = original_sorted_idx;
end

% ─────────────────────────────────────────────────────────────────────────────

function k = nth_pitlap_idx(tr, n)
% Return trace index of the Nth 'pitlap' in chronological (lap_number) order.
    k = [];
    lap_nums = tr.lap_numbers(:);
    if isfield(tr, 'lap_types') && numel(tr.lap_types) == numel(lap_nums)
        lap_types = tr.lap_types(:);
    else
        return;
    end
    [~, sort_idx] = sort(lap_nums);
    count = 0;
    for j = 1:numel(sort_idx)
        idx = sort_idx(j);
        if strcmpi(lap_types{idx}, 'pitlap')
            count = count + 1;
            if count == n
                k = idx;
                return;
            end
        end
    end
end

% ─────────────────────────────────────────────────────────────────────────────

function k = nth_inlap_idx(tr, n)
% Return trace index of the Nth 'inlap' in chronological (lap_number) order.
% Pit lane speed is captured as the car enters the pit lane (inlap).
    k = [];
    lap_nums = tr.lap_numbers(:);
    if isfield(tr, 'lap_types') && numel(tr.lap_types) == numel(lap_nums)
        lap_types = tr.lap_types(:);
    else
        return;
    end
    [~, sort_idx] = sort(lap_nums);
    count = 0;
    for j = 1:numel(sort_idx)
        idx = sort_idx(j);
        if strcmpi(lap_types{idx}, 'inlap')
            count = count + 1;
            if count == n
                k = idx;
                return;
            end
        end
    end
end

% ─────────────────────────────────────────────────────────────────────────────

function val = extract_channel_at_trap(tr, k, ch_valid, bkn_valid, bkn_val)
% Average any channel within the MyLaps beacon window for lap k.
% Returns NaN if channel absent, beacon absent, or window empty.

    val = NaN;
    if ~isfield(tr, ch_valid) || numel(tr.(ch_valid)) < k, return; end
    ch_data = tr.(ch_valid)(k).data(:);
    ch_dist = tr.(ch_valid)(k).dist(:);
    if isempty(ch_data), return; end

    if ~isfield(tr, bkn_valid) || numel(tr.(bkn_valid)) < k, return; end
    bkn_data = tr.(bkn_valid)(k).data(:);
    bkn_dist = tr.(bkn_valid)(k).dist(:);
    if isempty(bkn_data), return; end

    bkn_mask = round(bkn_data) == bkn_val;
    if ~any(bkn_mask), return; end

    d_start  = min(bkn_dist(bkn_mask));
    d_end    = max(bkn_dist(bkn_mask));
    win_mask = ch_dist >= d_start & ch_dist <= d_end & ~isnan(ch_data);
    if ~any(win_mask), return; end

    val = mean(ch_data(win_mask));
end

% ─────────────────────────────────────────────────────────────────────────────

function mk = extract_trap_speed(tr, k, spd_valid, bkn_valid, bkn_val)
% Average Ground_Speed within the MyLaps beacon window for lap k.
% Falls back to max(Ground_Speed) if beacon channel absent or no matching samples.

    mk = NaN;

    if ~isfield(tr, spd_valid) || numel(tr.(spd_valid)) < k, return; end
    spd_data = tr.(spd_valid)(k).data(:);
    spd_dist = tr.(spd_valid)(k).dist(:);
    if isempty(spd_data), return; end

    valid_spd = ~isnan(spd_data);
    if ~any(valid_spd), return; end

    % Unit normalise to kph
    if max(spd_data(valid_spd)) < 10
        spd_data = spd_data * 3.6;
    end

    % Try beacon windowing
    if isfield(tr, bkn_valid) && numel(tr.(bkn_valid)) >= k
        bkn_data = tr.(bkn_valid)(k).data(:);
        bkn_dist = tr.(bkn_valid)(k).dist(:);
        if ~isempty(bkn_data) && ~isempty(bkn_dist)
            bkn_mask = round(bkn_data) == bkn_val;
            if any(bkn_mask)
                d_start  = min(bkn_dist(bkn_mask));
                d_end    = max(bkn_dist(bkn_mask));
                win_mask = spd_dist >= d_start & spd_dist <= d_end & valid_spd;
                if any(win_mask)
                    mk = mean(spd_data(win_mask));
                    return;
                end
            end
        end
    end

    % Fallback: max over whole lap
    mk = max(spd_data(valid_spd));
end

% ─────────────────────────────────────────────────────────────────────────────

function T = load_timing_csv(csv_path, kph_col, event_filt, ses_filt)
% Load a timing CSV, filter, and normalise columns to: car, driver, session, lap, kph, vehicle

    T = readtable(csv_path, 'Delimiter', ',', 'TextType', 'string');
    if ismember('parse_error', T.Properties.VariableNames)
        T = T(~strcmpi(string(T.parse_error), 'true'), :);
    end
    if ~isempty(event_filt)
        T = T(strcmpi(string(T.event), event_filt), :);
    end
    if ~isempty(ses_filt)
        T = T(strcmpi(string(T.session), ses_filt), :);
    end
    if height(T) == 0, return; end

    T.car = strtrim(string(T.car));
    if ~isnumeric(T.lap), T.lap = str2double(string(T.lap)); end
    if ~ismember(kph_col, T.Properties.VariableNames)
        error('smp_match_speed_trap: column ''%s'' not found in %s', kph_col, csv_path);
    end
    if ~isnumeric(T.(kph_col)), T.(kph_col) = str2double(string(T.(kph_col))); end

    % Normalise kph column name
    T.kph = T.(kph_col);
    if ~strcmp(kph_col, 'kph'), T.(kph_col) = []; end

    if ~ismember('driver',  T.Properties.VariableNames), T.driver  = repmat("", height(T), 1); end
    if ~ismember('vehicle', T.Properties.VariableNames), T.vehicle = repmat("", height(T), 1); end
end

% ─────────────────────────────────────────────────────────────────────────────

function val = get_opt(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end

function csv_path = resolve_timing_csv(base_dir, event, session, report_type)
    if strcmp(report_type, 'pit_speed')
        type_sub = 'pit_speed';
        suffix   = '_speed_trap.csv';
    else
        type_sub = 'top_speed';
        suffix   = '_topspeed.csv';
    end
    d = dir(fullfile(base_dir, ['*_' upper(event)]));
    d = d([d.isdir]);
    if isempty(d)
        csv_path = '';
        return;
    end
    csv_path = fullfile(base_dir, d(1).name, type_sub, [session suffix]);
end

function T = make_empty_table()
    T = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), strings(0,1), ...
              nan(0,1), nan(0,1), nan(0,1), nan(0,1), nan(0,1), strings(0,1), ...
              strings(0,1), false(0,1), strings(0,1), ...
              'VariableNames', {'car','driver','session','lap','trap_type', ...
                                'timing_kph','motec_kph','delta_kph','lap_time_s', ...
                                'motec_lap','motec_lap_type', ...
                                'group_key','matched','vehicle'});
end

% ─────────────────────────────────────────────────────────────────────────────

function k = pit_lap_after_timing_inlap(tr, inlap_timing_num)
% Return trace index k of the pit_lap immediately following the in-lap
% identified by inlap_timing_num (a timing-system lap number).
%
% The in-lap itself is a non-pit lap (it crosses the timing beacon).
% The very next MoTeC lap after it that is typed 'pit_lap' is what we want.

    k = [];
    k_in = timing_lap_to_trace_idx(tr, inlap_timing_num, 0);
    if isempty(k_in), return; end

    inlap_motec_num = tr.lap_numbers(k_in);

    lap_nums  = tr.lap_numbers(:);
    if isfield(tr, 'lap_types') && numel(tr.lap_types) == numel(lap_nums)
        lap_types = tr.lap_types(:);
    else
        lap_types = repmat({'flying'}, numel(lap_nums), 1);
    end

    % Find laps after the in-lap that are pit_lap, take the first one
    after_mask = lap_nums > inlap_motec_num;
    candidates = find(after_mask);
    for j = 1:numel(candidates)
        idx = candidates(j);
        if strcmpi(lap_types{idx}, 'pitlap')
            k = idx;
            return;
        end
    end
end

% ─────────────────────────────────────────────────────────────────────────────

function T_pit = align_pit_table(T_pit, T_ref)
% Ensure T_pit has the same columns as T_ref (fill missing with empty values).
    ref_vars = T_ref.Properties.VariableNames;
    for vi = 1:numel(ref_vars)
        col = ref_vars{vi};
        if ismember(col, T_pit.Properties.VariableNames), continue; end
        % Infer fill type from T_ref
        sample = T_ref.(col);
        if isnumeric(sample)
            T_pit.(col) = nan(height(T_pit), 1);
        elseif islogical(sample)
            T_pit.(col) = false(height(T_pit), 1);
        else
            T_pit.(col) = repmat("", height(T_pit), 1);
        end
    end
    % Reorder to match T_ref column order (keep any extra pit cols at end)
    pit_vars  = T_pit.Properties.VariableNames;
    in_ref    = ref_vars(ismember(ref_vars, pit_vars));
    extra     = pit_vars(~ismember(pit_vars, ref_vars));
    T_pit     = T_pit(:, [in_ref, extra]);
end
