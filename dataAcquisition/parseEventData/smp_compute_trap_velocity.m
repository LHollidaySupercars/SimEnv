function T_result = smp_compute_trap_velocity(cache, params, opts)
% SMP_COMPUTE_TRAP_VELOCITY  Compute tyre-model wheel velocity over MyLaps speed
%                             trap zones and compare to timing-sheet kph.
%
% For each lap in the cache, locates contiguous dist-aligned windows where
% MyLaps X2TRA DeviceShortId == 31 (speed trap), then computes:
%   r_mm  = (r0 + P_coef*P + Fz_coef*FZ + N_coef*N_rpm) * 10
%   v_kph = (r_mm/1000) * rotSpeed_rad * 3.6
% Mean v_kph over the trap window is compared against the timing CSV.
%
% Usage:
%   T = smp_compute_trap_velocity(cache, params, opts)
%
% params (struct, all optional — defaults match smp_custom_channels.m):
%   r0            double   [28.2200]
%   P_coef        double   [0.0505]
%   Fz_coef       double   [-0.000340]
%   N_coef        double   [0.0004]
%   totalMass     double   [1300]   kg
%   frontCL_coef  [1x2]   [[-0.002087248, -0.196832152]]
%   rearCL_coef   [1x2]   [[-0.000202926, -0.745339228]]
%   gRef          double   [0]      vertical g baseline
%   mylaps_ch     string   ['MyLaps_X2TRA_DeviceShortId']
%   trap_value    double   [31]     beacon value marking trap zone
%
% opts (struct, all optional):
%   event         string   filter timing CSV by event
%   session       string   filter timing CSV by session
%   report_type   string   'top_speed' | 'pit_speed'  (default: 'top_speed')
%   master_csv    string   override timing CSV path
%
% Returns table columns:
%   car, driver, session, lap, trap_num,
%   timing_kph,
%   vFL_kph, vFR_kph, vRL_kph, vRR_kph,
%   delta_FL, delta_FR, delta_RL, delta_RR,
%   mean_rFL_mm, mean_rFR_mm, mean_rRL_mm, mean_rRR_mm,
%   trap_d_start_m, trap_d_end_m,
%   group_key, matched

    if nargin < 2 || isempty(params), params = struct(); end
    if nargin < 3 || isempty(opts),   opts   = struct(); end

    % ── Model parameters (defaults from smp_custom_channels.m) ───────────────
    r0           = get_p(params, 'r0',           28.2200);
    P_coef       = get_p(params, 'P_coef',        0.0505);
    Fz_coef      = get_p(params, 'Fz_coef',      -0.000340);
    N_coef       = get_p(params, 'N_coef',         0.0004);
    totalMass    = get_p(params, 'totalMass',      1300);
    frontCL_coef = get_p(params, 'frontCL_coef', [-0.002087248, -0.196832152]);
    rearCL_coef  = get_p(params, 'rearCL_coef',  [-0.000202926, -0.745339228]);
    gRef         = get_p(params, 'gRef',           0);
    mylaps_ch    = get_p(params, 'mylaps_ch',     'MyLaps_X2TRA_DeviceShortId');
    trap_value   = get_p(params, 'trap_value',    31);

    cornerMass   = (totalMass - 140) * 10 / 4;   % [N]
    r_nominal    = (2.090 / pi) / 2;              % static rolling radius [m]

    % ── Load and filter timing CSV ────────────────────────────────────────────
    timing_dir  = fullfile(fileparts(mfilename('fullpath')), '..', 'timing');
    rep_type    = get_p(opts, 'report_type',      'top_speed');
    master_csv  = get_p(opts, 'master_csv',        '');
    base_dir    = get_p(opts, 'timing_base_dir',   '');
    event_filt  = get_p(opts, 'event',             '');
    ses_filt    = get_p(opts, 'session',           '');

    if strcmp(rep_type, 'pit_speed')
        kph_col = 's1_kph';
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

    T_timing = table();
    has_timing = false;
    if isfile(master_csv)
        T_timing = readtable(master_csv, 'Delimiter', ',', 'TextType', 'string');
        if ismember('parse_error', T_timing.Properties.VariableNames)
            T_timing = T_timing(~strcmpi(string(T_timing.parse_error), 'true'), :);
        end
        if ~isempty(event_filt)
            T_timing = T_timing(strcmpi(string(T_timing.event), event_filt), :);
        end
        if ~isempty(ses_filt)
            T_timing = T_timing(strcmpi(string(T_timing.session), ses_filt), :);
        end
        if ~isnumeric(T_timing.lap)
            T_timing.lap = str2double(string(T_timing.lap));
        end
        if ismember(kph_col, T_timing.Properties.VariableNames)
            if ~isnumeric(T_timing.(kph_col))
                T_timing.(kph_col) = str2double(string(T_timing.(kph_col)));
            end
            has_timing = height(T_timing) > 0;
        end
    end

    % ── Build manifest lookup ─────────────────────────────────────────────────
    mf     = cache.manifest;
    mf_car = strtrim(string(mf.CarNumber));
    mf_ses = string(mf.Session);
    mf_gk  = string(mf.GroupKey);

    % ── Corner config ─────────────────────────────────────────────────────────
    corners = { ...
        'FL', 'Wheel_Speed_Front_Left',  'TPM1S_FL_WS_PRESS', 'front'; ...
        'FR', 'Wheel_Speed_Front_Right', 'TPM1S_FR_WS_PRESS', 'front'; ...
        'RL', 'Wheel_Speed_Rear_Left',   'TPM1S_RL_WS_PRESS', 'rear';  ...
        'RR', 'Wheel_Speed_Rear_Right',  'TPM1S_RR_WS_PRESS', 'rear';  ...
    };
    % valid field names for trace lookup
    corner_ws_fn = cellfun(@matlab.lang.makeValidName, corners(:,2), 'UniformOutput', false);
    corner_tp_fn = cellfun(@matlab.lang.makeValidName, corners(:,3), 'UniformOutput', false);

    accel_fn     = matlab.lang.makeValidName('Acceleration_Z_Filt');
    mylaps_fn    = matlab.lang.makeValidName(mylaps_ch);

    % ── Pre-allocate result rows ──────────────────────────────────────────────
    rows = {};

    gkeys = fieldnames(cache.traces);
    for gi = 1:numel(gkeys)
        gk = gkeys{gi};
        tr = cache.traces.(gk);
        if ~isfield(tr, 'lap_numbers') || ~isfield(tr, mylaps_fn)
            continue;
        end

        n_laps  = tr.n_traces;
        lap_nums = tr.lap_numbers;

        % manifest info for this group
        gk_mask  = strcmp(mf_gk, gk);
        car_str  = '';
        drv_str  = '';
        ses_str  = '';
        if any(gk_mask)
            car_str = char(mf_car(find(gk_mask, 1)));
            if ismember('Driver',  mf.Properties.VariableNames)
                drv_str = char(string(mf.Driver(find(gk_mask,1))));
            end
            if ismember('Session', mf.Properties.VariableNames)
                ses_str = char(string(mf.Session(find(gk_mask,1))));
            end
        end

        for k = 1:n_laps
            lap_n = lap_nums(k);

            % ── Find trap windows from MyLaps beacon ──────────────────────────
            ml_ch = tr.(mylaps_fn)(k);
            if isempty(ml_ch.data) || isempty(ml_ch.dist)
                continue;
            end
            ml_data = ml_ch.data(:);
            ml_dist = ml_ch.dist(:);

            trap_windows = find_sustained_windows(ml_data, ml_dist, trap_value);
            if isempty(trap_windows)
                continue;
            end

            % ── Timing lookup ─────────────────────────────────────────────────
            timing_kph = NaN;
            timing_matched = false;
            if has_timing
                t_mask = strcmpi(strtrim(string(T_timing.car)), car_str) & ...
                         T_timing.lap == lap_n;
                if ~any(t_mask) && lap_n > 0
                    t_mask = strcmpi(strtrim(string(T_timing.car)), car_str) & ...
                             T_timing.lap == (lap_n - 1);
                end
                if any(t_mask)
                    vals = T_timing.(kph_col)(t_mask);
                    vals = vals(~isnan(vals));
                    if ~isempty(vals)
                        timing_kph     = vals(1);
                        timing_matched = true;
                    end
                end
            end

            % ── Per-trap computation ──────────────────────────────────────────
            for ti = 1:size(trap_windows, 1)
                d_lo = trap_windows(ti, 1);
                d_hi = trap_windows(ti, 2);

                vCorner   = nan(1, 4);
                rCorner   = nan(1, 4);

                for ci = 1:4
                    ws_fn = corner_ws_fn{ci};
                    tp_fn = corner_tp_fn{ci};
                    axle  = corners{ci, 4};

                    if ~isfield(tr, ws_fn), continue; end
                    ws_ch = tr.(ws_fn)(k);
                    if isempty(ws_ch.data) || isempty(ws_ch.dist), continue; end

                    ref_dist = ws_ch.dist(:);
                    ref_data = ws_ch.data(:);   % km/h

                    % restrict to trap window
                    win_mask = ref_dist >= d_lo & ref_dist <= d_hi;
                    if sum(win_mask) < 2, continue; end

                    spd_w    = ref_dist(win_mask);   % dist axis in window
                    spd_kph  = ref_data(win_mask);

                    % tyre pressure (interp onto wheel-speed dist axis)
                    P_vals = zeros(size(spd_kph));
                    if isfield(tr, tp_fn)
                        tp_ch = tr.(tp_fn)(k);
                        if ~isempty(tp_ch.data) && ~isempty(tp_ch.dist)
                            P_vals = interp1(tp_ch.dist(:), tp_ch.data(:), spd_w, ...
                                             'linear', 'extrap');
                        end
                    end

                    % vertical g (interp or zero)
                    gVert = zeros(size(spd_kph));
                    if isfield(tr, accel_fn)
                        az_ch = tr.(accel_fn)(k);
                        if ~isempty(az_ch.data) && ~isempty(az_ch.dist)
                            gVert = interp1(az_ch.dist(:), az_ch.data(:), spd_w, ...
                                            'linear', 'extrap');
                        end
                    end

                    % vertical load
                    FZ = (1 + (gVert - gRef)) .* cornerMass;

                    % aero
                    if strcmp(axle, 'front')
                        CL_vals = frontCL_coef(1) .* spd_kph + frontCL_coef(2);
                    else
                        CL_vals = rearCL_coef(1)  .* spd_kph + rearCL_coef(2);
                    end
                    FZ = FZ + 0.5 .* spd_kph.^2 .* CL_vals / 2;

                    % rotational speed (RPM)
                    rot_rpm = (spd_kph / 3.6) / r_nominal * 60 / (2 * pi);
                    rot_rad = (spd_kph / 3.6) / r_nominal;   % rad/s

                    % radius model
                    r_mm = (r0 + P_coef .* P_vals + Fz_coef .* FZ + N_coef .* rot_rpm) * 10;

                    % wheel velocity
                    v_kph = (r_mm / 1000) .* rot_rad * 3.6;

                    vCorner(ci) = mean(v_kph,  'omitnan');
                    rCorner(ci) = mean(r_mm,   'omitnan');
                end

                rows{end+1} = { ...
                    car_str, drv_str, ses_str, lap_n, ti, ...
                    timing_kph, ...
                    vCorner(1), vCorner(2), vCorner(3), vCorner(4), ...
                    vCorner(1) - timing_kph, vCorner(2) - timing_kph, ...
                    vCorner(3) - timing_kph, vCorner(4) - timing_kph, ...
                    rCorner(1), rCorner(2), rCorner(3), rCorner(4), ...
                    d_lo, d_hi, gk, timing_matched ...
                }; %#ok<AGROW>
            end
        end
    end

    % ── Assemble output table ─────────────────────────────────────────────────
    if isempty(rows)
        T_result = make_empty_result();
        return;
    end

    rows = vertcat(rows{:});

    T_result = table( ...
        string(rows(:,1)),  string(rows(:,2)),  string(rows(:,3)), ...
        cell2mat(rows(:,4)), cell2mat(rows(:,5)), ...
        cell2mat(rows(:,6)), ...
        cell2mat(rows(:,7)),  cell2mat(rows(:,8)),  cell2mat(rows(:,9)),  cell2mat(rows(:,10)), ...
        cell2mat(rows(:,11)), cell2mat(rows(:,12)), cell2mat(rows(:,13)), cell2mat(rows(:,14)), ...
        cell2mat(rows(:,15)), cell2mat(rows(:,16)), cell2mat(rows(:,17)), cell2mat(rows(:,18)), ...
        cell2mat(rows(:,19)), cell2mat(rows(:,20)), ...
        string(rows(:,21)), logical(cell2mat(rows(:,22))), ...
        'VariableNames', { ...
            'car','driver','session','lap','trap_num', ...
            'timing_kph', ...
            'vFL_kph','vFR_kph','vRL_kph','vRR_kph', ...
            'delta_FL','delta_FR','delta_RL','delta_RR', ...
            'mean_rFL_mm','mean_rFR_mm','mean_rRL_mm','mean_rRR_mm', ...
            'trap_d_start_m','trap_d_end_m', ...
            'group_key','matched'});
end

% ── Local helpers ─────────────────────────────────────────────────────────────

function wins = find_sustained_windows(data, dist, target_val)
% Return [N x 2] matrix of [d_start, d_end] for each contiguous run where
% data == target_val.
    in_trap  = (round(data) == target_val);
    starts   = find(diff([0; in_trap(:)]) == 1);
    ends     = find(diff([in_trap(:); 0]) == -1);
    wins     = [dist(starts), dist(ends)];
    % drop zero-length windows
    wins     = wins(wins(:,2) > wins(:,1), :);
end

function T = make_empty_result()
    T = cell2table(cell(0, 22), 'VariableNames', { ...
        'car','driver','session','lap','trap_num', ...
        'timing_kph', ...
        'vFL_kph','vFR_kph','vRL_kph','vRR_kph', ...
        'delta_FL','delta_FR','delta_RL','delta_RR', ...
        'mean_rFL_mm','mean_rFR_mm','mean_rRL_mm','mean_rRR_mm', ...
        'trap_d_start_m','trap_d_end_m', ...
        'group_key','matched'});
end

function val = get_p(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end

function csv_path = resolve_timing_csv(base_dir, event, session, report_type)
% Find <base_dir>\*_EVENT\<type>\<session>_<suffix>.csv
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
