function [result, summary, tbl] = quali_fuel_analysis(laps, session, opts)
% QUALI_FUEL_ANALYSIS  Extract flying-lap fuel, tyre, and fuel-effect data.
%
% Usage:
%   [result, summary, tbl] = quali_fuel_analysis(laps, session)
%   [result, summary, tbl] = quali_fuel_analysis(laps, session, opts)
%
% opts:
%   .plot   logical  (default true)  — set false to suppress tyre pressure plot
%
% Inputs:
%   laps    - struct array from lap_slicer()
%   session - raw session struct from motec_ld_reader() (contains channel data)
%
% Outputs:
%   result(k)  - struct array, one entry per flying lap (raw data)
%   summary    - scalar struct: n_flying_laps, n_tyre_changes
%   tbl        - MATLAB table, one row per flying lap:
%                  LapNum | LapTime | LapTime_s | TyreSet | TyreChange |
%                  TyreChangeAll | Fuel_OnLap_kg | Fuel_ToNext_kg |
%                  dLapTime_s | dFuel_kg | s_per_kg | s_per_10kg | SameSet |
%                  Press_FL FR RL RR | Temp_FL FR RL RR

% ======================================================================
%  CHANNEL NAME CONFIGURATION
% ======================================================================
CH_FUEL_USED = 'Fuel_Used_Mass';       % primary cumulative fuel channel

CORNERS       = {'FL', 'FR', 'RL', 'RR'};
CH_TYRE_ID    = {'TPM1S_FL_WS_ID',    'TPM1S_FR_WS_ID',    'TPM1S_RL_WS_ID',    'TPM1S_RR_WS_ID'};
CH_TYRE_PRESS = {'TPM1S_FL_WS_PRESS', 'TPM1S_FR_WS_PRESS', 'TPM1S_RL_WS_PRESS', 'TPM1S_RR_WS_PRESS'};
CH_TYRE_TEMP  = {'TPM1S_FL_WS_TEMP',  'TPM1S_FR_WS_TEMP',  'TPM1S_RL_WS_TEMP',  'TPM1S_RR_WS_TEMP'};

LAP_TYPES_FOR_TYRE = {'flying', 'inlap', 'outlap', 'pitlap'};

if nargin < 3 || isempty(opts), opts = struct(); end
if ~isfield(opts, 'plot'), opts.plot = true; end
if ~isfield(opts, 'fuel_plot'), opts.fuel_plot = opts.plot; end

% ======================================================================
%  PHASE 1 — LAP COUNT
% ======================================================================
n_flying = sum(strcmp({laps.lap_type}, 'flying'));
n_laps   = numel(laps);

if n_flying == 0
    warning('quali_fuel_analysis: no flying laps found.');
    result  = struct([]);
    summary = struct('n_flying_laps', 0, 'n_tyre_changes', 0);
    tbl     = table();
    return
end

fprintf('[quali_fuel_analysis] Found %d flying lap(s) across %d total lap(s).\n', n_flying, n_laps);

% ======================================================================
%  PHASE 2 — FUEL CHANNEL RESOLUTION
% ======================================================================
fuel_ch = resolve_fuel_channel(session, CH_FUEL_USED);
has_fuel = ~isempty(fuel_ch);
if ~has_fuel
    warning('quali_fuel_analysis: no cumulative fuel channel found — fuel fields will be NaN.');
end

% ======================================================================
%  PHASE 3 — TYRE ID CHANNEL AVAILABILITY
% ======================================================================
tyre_id_avail  = check_channels(session, CH_TYRE_ID,    'TPMS ID');
tyre_pr_avail  = check_channels(session, CH_TYRE_PRESS, 'Tyre pressure');
tyre_tmp_avail = check_channels(session, CH_TYRE_TEMP,  'Tyre temperature');

% ======================================================================
%  PHASE 4 — BUILD RESULT ARRAY
% ======================================================================
result = repmat(make_empty_result(CORNERS, LAP_TYPES_FOR_TYRE), n_laps, 1);

stint_number = 1;
prev_tyre_id = struct('FL', NaN, 'FR', NaN, 'RL', NaN, 'RR', NaN);

for k = 1:n_laps
    fi      = k;
    lap_k   = laps(fi);

    result(k).lap_number = lap_k.lap_number;
    result(k).lap_time   = lap_k.lap_time;
    result(k).lap_type   = lap_k.lap_type;
    result(k).t_start    = lap_k.t_start;
    result(k).t_end      = lap_k.t_end;

    % --- Fuel burned during this lap ---------------------------------
    if has_fuel
        result(k).fuel_on_lap = channel_delta(fuel_ch, lap_k.t_start, lap_k.t_end);
    end

    % --- Tyre IDs and stint tracking ---------------------------------
    is_push = strcmp(lap_k.lap_type, 'flying');
    cur_id  = struct();
    changed = struct('FL', false, 'FR', false, 'RL', false, 'RR', false);
    for c = 1:4
        corner = CORNERS{c};
        if tyre_id_avail(c)
            cur_id.(corner) = lap_scalar(session.(CH_TYRE_ID{c}), lap_k.t_start, lap_k.t_end);
        else
            cur_id.(corner) = NaN;
        end
        if is_push && ~isnan_safe(prev_tyre_id.(corner))
            changed.(corner) = ~isequal(cur_id.(corner), prev_tyre_id.(corner)) && ...
                                ~isnan_safe(cur_id.(corner));
        end
    end

    any_changed = changed.FL || changed.FR || changed.RL || changed.RR;
    all_changed = changed.FL && changed.FR && changed.RL && changed.RR;
    if all_changed
        stint_number = stint_number + 1;
    elseif any_changed
        warning('quali_fuel_analysis: lap %d changed only some tyre IDs; not counted as a new set.', ...
            lap_k.lap_number);
    end

    result(k).tyre_id          = cur_id;
    result(k).tyre_changed     = changed;
    result(k).tyre_all_changed = all_changed;
    result(k).stint_number     = stint_number;
    % Only push laps update the reference, so in/out laps cannot mask a change.
    if is_push, prev_tyre_id = cur_id; end

    % --- Tyre pressure & temperature per surrounding lap type --------
    for lt = 1:numel(LAP_TYPES_FOR_TYRE)
        lap_type_str = LAP_TYPES_FOR_TYRE{lt};
        ref_lap = find_surrounding_lap(laps, fi, lap_type_str);

        for c = 1:4
            corner = CORNERS{c};
            if ~isempty(ref_lap)
                if tyre_pr_avail(c)
                    result(k).tyre_press.(lap_type_str).(corner) = ...
                        lap_mean(session.(CH_TYRE_PRESS{c}), ref_lap.t_start, ref_lap.t_end);
                end
                if tyre_tmp_avail(c)
                    result(k).tyre_temp.(lap_type_str).(corner) = ...
                        lap_mean(session.(CH_TYRE_TEMP{c}), ref_lap.t_start, ref_lap.t_end);
                end
            end
        end
    end
end

% ======================================================================
%  PHASE 4b — PUSH-LAP-TO-PUSH-LAP FUEL AND PACE
% ======================================================================
push_idx = find(strcmp({result.lap_type}, 'flying'));
if has_fuel
    for a = push_idx(:)'
        result(a).fuel_cum = interp1(fuel_ch.time, fuel_ch.data, result(a).t_end, 'linear');
    end
end
for j = 1:numel(push_idx) - 1
    a = push_idx(j);  b = push_idx(j + 1);
    if has_fuel
        result(a).fuel_to_next = channel_delta(fuel_ch, result(a).t_end, result(b).t_start);
        result(b).d_fuel = channel_delta(fuel_ch, result(a).t_start, result(b).t_start);
    end
    result(b).d_lap_s  = result(b).lap_time - result(a).lap_time;
    result(b).same_set = ~result(b).tyre_all_changed;
    % Lap time gained per kg burned; positive means faster as fuel burns off.
    result(b).s_per_kg = -result(b).d_lap_s / result(b).d_fuel;
end

% ======================================================================
%  PHASE 5 — SUMMARY STRUCT
% ======================================================================
summary = struct();
summary.n_flying_laps  = n_flying;
summary.n_tyre_changes = sum([result.tyre_all_changed]);
same = [result.same_set] & ~isnan([result.s_per_kg]);
summary.s_per_kg_same_set = mean([result(same).s_per_kg], 'omitnan');

% ======================================================================
%  PHASE 6 — BUILD TABLE AND DISPLAY
% ======================================================================
tbl = build_result_table(result, CORNERS);
disp(tbl);

% ======================================================================
%  PHASE 7 — TYRE PRESSURE PLOT
% ======================================================================
if opts.plot
    plot_tyre_pressures(result, CORNERS);
end
if opts.fuel_plot && has_fuel
    plot_fuel_effect(result);
end

end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================

function plot_fuel_effect(result)
    push = result(strcmp({result.lap_type}, 'flying'));
    if numel(push) < 2, return, end

    fuel = [push.fuel_cum];
    lt   = [push.lap_time];
    set_ = [push.stint_number];
    laps = [push.lap_number];

    figure('Name', 'Qualifying: Lap Time vs Fuel Burned', 'NumberTitle', 'off');
    hold on; grid on; box on;
    cmap = lines(max(set_));

    % Solid between push laps on the same set, dashed across a tyre change.
    for j = 2:numel(push)
        if any(isnan([fuel(j-1:j) lt(j-1:j)])), continue, end
        if push(j).same_set
            plot(fuel(j-1:j), lt(j-1:j), '-', 'Color', cmap(set_(j),:), 'LineWidth', 1.5, 'HandleVisibility', 'off');
            text(mean(fuel(j-1:j)), mean(lt(j-1:j)), sprintf('  %.3f s/10kg', push(j).s_per_kg*10), ...
                'FontSize', 8, 'VerticalAlignment', 'bottom');
        else
            plot(fuel(j-1:j), lt(j-1:j), '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
        end
    end

    for s = unique(set_)
        m = set_ == s;
        scatter(fuel(m), lt(m), 70, cmap(s,:), 'filled', 'DisplayName', sprintf('Tyre set %d', s));
    end
    for k = 1:numel(push)
        text(fuel(k), lt(k), sprintf(' L%d', laps(k)), 'FontSize', 8, 'VerticalAlignment', 'top');
    end

    xlabel('Cumulative fuel burned at end of lap (kg)');
    ylabel('Lap time (s)');
    title('Push-lap pace vs fuel burned (dashed = tyre change)');
    legend('Location', 'best');
end

% ======================================================================
%  TABLE BUILDER
% ======================================================================

function tbl = build_result_table(result, corners)
    n = numel(result);

    LapNum    = [result.lap_number]';
    LapTime_s = [result.lap_time]';

    % Formatted mm:ss.sss
    LapTime = strings(n, 1);
    for k = 1:n
        t          = result(k).lap_time;
        mm         = floor(t / 60);
        ss         = t - mm * 60;
        LapTime(k) = sprintf('%d:%06.3f', mm, ss);
    end

    TyreSet    = [result.stint_number]';
    TyreChange = strings(n, 1);
    for k = 1:n
        ch = result(k).tyre_changed;
        changed_c = {};
        for c = 1:numel(corners)
            if ch.(corners{c}), changed_c{end+1} = corners{c}; end %#ok
        end
        if isempty(changed_c)
            TyreChange(k) = '-';
        else
            TyreChange(k) = strjoin(changed_c, ' ');
        end
    end

    LapType        = string({result.lap_type})';
    Fuel_OnLap_kg  = [result.fuel_on_lap]';
    Fuel_ToNext_kg = [result.fuel_to_next]';
    TyreChangeAll  = [result.tyre_all_changed]';
    SameSet        = [result.same_set]';
    dLapTime_s     = [result.d_lap_s]';
    dFuel_kg       = [result.d_fuel]';
    s_per_kg       = [result.s_per_kg]';
    s_per_10kg     = 10 * s_per_kg;

    press   = NaN(n, 4);
    temp    = NaN(n, 4);
    tyre_id = NaN(n, 4);
    for k = 1:n
        for c = 1:4
            press(k, c)   = result(k).tyre_press.flying.(corners{c});
            temp(k, c)    = result(k).tyre_temp.flying.(corners{c});
            tyre_id(k, c) = result(k).tyre_id.(corners{c});
        end
    end

    tbl = table(LapNum, LapType, LapTime, LapTime_s, TyreSet, TyreChange, ...
        TyreChangeAll, Fuel_OnLap_kg, Fuel_ToNext_kg, ...
        dLapTime_s, dFuel_kg, s_per_kg, s_per_10kg, SameSet, ...
        tyre_id(:,1), tyre_id(:,2), tyre_id(:,3), tyre_id(:,4), ...
        press(:,1), press(:,2), press(:,3), press(:,4), ...
        temp(:,1),  temp(:,2),  temp(:,3),  temp(:,4), ...
        'VariableNames', {'LapNum','LapType','LapTime','LapTime_s','TyreSet','TyreChange', ...
                          'TyreChangeAll','Fuel_OnLap_kg','Fuel_ToNext_kg', ...
                          'dLapTime_s','dFuel_kg','s_per_kg','s_per_10kg','SameSet', ...
                          'TyreID_FL','TyreID_FR','TyreID_RL','TyreID_RR', ...
                          'Press_FL','Press_FR','Press_RL','Press_RR', ...
                          'Temp_FL','Temp_FR','Temp_RL','Temp_RR'});
end

function r = make_empty_result(corners, lap_types)
% Scaffold one result entry so MATLAB can pre-allocate a struct array.
    r.lap_number   = NaN;
    r.lap_time     = NaN;
    r.lap_type     = '';
    r.t_start      = NaN;
    r.t_end        = NaN;
    r.fuel_on_lap  = NaN;
    r.fuel_to_next = NaN;
    r.fuel_cum     = NaN;
    r.d_lap_s      = NaN;
    r.d_fuel       = NaN;
    r.s_per_kg     = NaN;
    r.same_set     = false;
    r.tyre_all_changed = false;
    r.stint_number = 1;

    tc = struct(); ti = struct();
    for c = 1:numel(corners)
        tc.(corners{c}) = false;
        ti.(corners{c}) = NaN;
    end
    r.tyre_changed = tc;
    r.tyre_id      = ti;

    press = struct(); temp = struct();
    for lt = 1:numel(lap_types)
        corner_struct = struct();
        for c = 1:numel(corners)
            corner_struct.(corners{c}) = NaN;
        end
        press.(lap_types{lt}) = corner_struct;
        temp.(lap_types{lt})  = corner_struct;
    end
    r.tyre_press = press;
    r.tyre_temp  = temp;
end

% -----------------------------------------------------------------------

function ch = resolve_fuel_channel(session, primary_name)
% Returns the channel struct for the cumulative fuel channel, or [].
    ch = [];
    fnames = fieldnames(session);

    % Try primary name first
    if isfield(session, primary_name)
        ch = session.(primary_name);
        fprintf('[quali_fuel_analysis] Fuel channel: %s\n', primary_name);
        return
    end

    % Case-insensitive fallback: look for field containing 'fuel' and 'used'
    for i = 1:numel(fnames)
        fn_lower = lower(fnames{i});
        if contains(fn_lower, 'fuel') && contains(fn_lower, 'used')
            ch = session.(fnames{i});
            fprintf('[quali_fuel_analysis] Fuel channel (fallback): %s\n', fnames{i});
            return
        end
    end

    % Second fallback: flow channel — integrate if necessary
    for i = 1:numel(fnames)
        fn_lower = lower(fnames{i});
        if contains(fn_lower, 'fuel') && contains(fn_lower, 'flow')
            raw = session.(fnames{i});
            fprintf('[quali_fuel_analysis] Integrating fuel flow channel: %s\n', fnames{i});
            ch = integrate_channel(raw);
            return
        end
    end
end

function ch_int = integrate_channel(ch)
% Numerically integrate a flow-rate channel to produce a cumulative channel.
    dt      = diff(ch.time);
    dt      = [dt(1); dt(:)];   % forward-fill first sample
    cum_val = cumsum(ch.data .* dt);

    ch_int          = ch;
    ch_int.data     = cum_val;
    ch_int.units    = strrep(ch.units, '/s', '');
    ch_int.raw_name = [ch.raw_name '_integrated'];
end

% -----------------------------------------------------------------------

function avail = check_channels(session, ch_names, label)
    avail = false(1, numel(ch_names));
    missing = {};
    for i = 1:numel(ch_names)
        if isfield(session, ch_names{i})
            avail(i) = true;
        else
            missing{end+1} = ch_names{i}; %#ok
        end
    end
    if ~isempty(missing)
        warning('quali_fuel_analysis: %s channel(s) missing: %s', label, strjoin(missing, ', '));
    end
end

% -----------------------------------------------------------------------

function delta = channel_delta(ch, t_start, t_end)
% Difference between last and first value of ch.data within [t_start, t_end].
    mask = ch.time >= t_start & ch.time <= t_end;
    vals = ch.data(mask);
    if numel(vals) < 2
        delta = NaN;
        return
    end
    delta = vals(end) - vals(1);
end

function val = lap_scalar(ch, t_start, t_end)
% Mode value of ch.data within [t_start, t_end].
    mask = ch.time >= t_start & ch.time <= t_end;
    vals = ch.data(mask);
    if isempty(vals)
        val = NaN;
        return
    end
    if isnumeric(vals)
        val = mode(vals);
    else
        val = mode(string(vals));
    end
end

function val = lap_mean(ch, t_start, t_end)
% Mean of ch.data within [t_start, t_end].
    mask = ch.time >= t_start & ch.time <= t_end;
    vals = ch.data(mask);
    if isempty(vals)
        val = NaN;
    else
        val = mean(vals, 'omitnan');
    end
end

% -----------------------------------------------------------------------

function ref_lap = find_surrounding_lap(laps, flying_fi, lap_type_str)
% For a flying lap at index flying_fi, find the nearest lap of the given type.
%
%   flying  -> the lap itself
%   inlap   -> nearest inlap BEFORE flying_fi
%   outlap  -> nearest outlap AFTER  flying_fi
%   pitlap  -> nearest pitlap BEFORE flying_fi (within same stint window)

    ref_lap = [];

    if strcmp(lap_type_str, 'flying')
        ref_lap = laps(flying_fi);
        return
    end

    if strcmp(lap_type_str, 'inlap') || strcmp(lap_type_str, 'pitlap')
        % Search backwards from flying_fi - 1
        for i = flying_fi-1 : -1 : 1
            if strcmp(laps(i).lap_type, lap_type_str)
                ref_lap = laps(i);
                return
            end
            % Stop if we hit another flying lap (different stint)
            if strcmp(laps(i).lap_type, 'flying')
                return
            end
        end

    elseif strcmp(lap_type_str, 'outlap')
        % Search forwards from flying_fi + 1
        for i = flying_fi+1 : numel(laps)
            if strcmp(laps(i).lap_type, 'outlap')
                ref_lap = laps(i);
                return
            end
            % Stop if we hit another flying lap
            if strcmp(laps(i).lap_type, 'flying')
                return
            end
        end
    end
end

% -----------------------------------------------------------------------

function flag = isnan_safe(val)
% Returns true if val is NaN (works for numeric and non-numeric types).
    if isnumeric(val)
        flag = isnan(val);
    else
        flag = false;
    end
end

% ======================================================================
%  TYRE PRESSURE PLOT
% ======================================================================
function plot_tyre_pressures(result, corners)
    n        = numel(result);
    lap_nums = [result.lap_number];

    % Extract pressure matrix: [n_laps x 4 corners] for flying laps
    press = NaN(n, 4);
    for k = 1:n
        for c = 1:4
            v = result(k).tyre_press.flying.(corners{c});
            if ~isempty(v), press(k,c) = v; end
        end
    end

    if all(isnan(press(:)))
        fprintf('[quali_fuel_analysis] No tyre pressure data to plot.\n');
        return
    end

    figure('Name', 'Qualifying: Tyre Pressures (Flying Laps)', 'NumberTitle', 'off');
    corner_labels = {'Front Left', 'Front Right', 'Rear Left', 'Rear Right'};
    stints = [result.stint_number];
    unique_stints = unique(stints);
    cmap = lines(numel(unique_stints));

    for c = 1:4
        subplot(2, 2, c);
        hold on; grid on; box on;

        for s = 1:numel(unique_stints)
            mask = stints == unique_stints(s);
            scatter(lap_nums(mask), press(mask, c), 50, ...
                'filled', 'MarkerFaceColor', cmap(s,:), ...
                'DisplayName', sprintf('Stint %d', unique_stints(s)));
        end

        % Horizontal mean line per stint
        for s = 1:numel(unique_stints)
            mask = stints == unique_stints(s);
            mn   = mean(press(mask, c), 'omitnan');
            if ~isnan(mn)
                x_range = [min(lap_nums(mask))-0.5, max(lap_nums(mask))+0.5];
                plot(x_range, [mn mn], '--', 'Color', cmap(s,:), ...
                    'LineWidth', 1.2, 'HandleVisibility', 'off');
            end
        end

        xlabel('Lap number');
        ylabel('Mean pressure (bar)');
        title(corner_labels{c});
        if c == 1
            legend('show', 'Location', 'best');
        end
        hold off;
    end

    sgtitle('Qualifying: Mean Tyre Pressure per Flying Lap');
end
