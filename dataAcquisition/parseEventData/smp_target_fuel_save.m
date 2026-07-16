function results = smp_target_fuel_save(variants, segments, lap, fuel_targets_kg, varargin)
% SMP_TARGET_FUEL_SAVE  Find and plot optimal combinations for target fuel savings
%
% USAGE:
%   results = smp_target_fuel_save(variants, segments, lap, [0.1, 0.2, 0.3])
%   results = smp_target_fuel_save(..., 'output_dir', './out', 'preceding_lap', prec)
%
% INPUTS:
%   variants        (struct array)  From smp_fuel_save_coasting.
%   segments        (struct array)  Segment definitions.
%   lap             (struct)        Original lap (4th output of smp_fuel_save_coasting).
%   fuel_targets_kg (double array)  Target fuel savings in kg, e.g. [0.1 0.2 0.3].
%
% OPTIONAL PARAMETERS:
%   output_dir    (string)   Output folder for PNG and XLSX. [default: './fuel_save_output']
%   max_combos    (integer)  Abort threshold for combo count. [default: 10e6]
%   preceding_lap (struct)   Lap before the timed lap (5th output of smp_fuel_save_coasting).
%                            When provided, the S01 (main straight) portion is prepended
%                            with negative distance offsets, matching the master lap plot.

%% --- Input parsing ----------------------------------------------------------

p = inputParser;
addParameter(p, 'output_dir',    './fuel_save_output', @ischar);
addParameter(p, 'max_combos',    5e6,                  @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'preceding_lap', [],                   @(x) isempty(x) || isstruct(x));
parse(p, varargin{:});

output_dir    = p.Results.output_dir;
max_combos    = p.Results.max_combos;
preceding_lap = p.Results.preceding_lap;

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

fuel_targets_kg = fuel_targets_kg(:)';   % ensure row vector

%% --- Step 1: Build per-segment discrete option tables -----------------------

ok_mask = strcmp({variants.status}, 'success');
ok_v    = variants(ok_mask);

if isempty(ok_v)
    warning('smp_target_fuel_save: no successful variants found.');
    results = [];
    return;
end

seg_ids   = unique([ok_v.segment_idx]);
n_segs    = numel(seg_ids);
seg_opts  = cell(n_segs, 1);   % (n_opts × 4): [coast_m, time_s, fuel_kg, var_linear_idx]
seg_names = cell(n_segs, 1);
n_opts    = zeros(n_segs, 1);

for si = 1:n_segs
    sid  = seg_ids(si);
    mask = ([ok_v.segment_idx] == sid);
    sv   = ok_v(mask);

    coast_m = [sv.coasting_point]';
    time_s  = [sv.time_penalty_sec]';
    fuel_kg = [sv.fuel_saved_kg]';
    % Store linear index into ok_v for later speed-trace lookup
    var_idx = find(mask)';

    [coast_m, order] = sort(coast_m);
    time_s  = time_s(order);
    fuel_kg = fuel_kg(order);
    var_idx = var_idx(order);

    % Row 1: no-coast (coast_m=0, time=0, fuel=0, var_idx=0)
    opts = [0, 0, 0, 0; coast_m, time_s, fuel_kg, var_idx];

    seg_opts{si}  = opts;
    seg_names{si} = sv(1).segment_name;
    n_opts(si)    = size(opts, 1);
end

%% --- Step 2: Check feasibility and enumerate --------------------------------

total_combos = prod(n_opts);
fprintf('[TargetSave] %d segments | %s total combinations\n', n_segs, fmt_large(total_combos));

if total_combos > max_combos
    % DP solver: finds exact optimum without enumerating all combinations.
    % Handles arbitrarily large grids with O(n_segs * n_opts * n_fuel_levels) cost.
    fprintf('[TargetSave] %s combinations > max_combos (%s) — using DP solver.\n', ...
        fmt_large(total_combos), fmt_large(max_combos));
    use_dp = true;
    idx_mat = []; combo_time = []; combo_fuel = [];
else
    use_dp = false;
    % Chunked enumeration — same strategy as smp_doe_fuel_save.
    % Peak memory bounded to ~chunk_size * n_segs * 2 bytes (uint16) per chunk.
    chunk_size  = 5e6;
    n_chunks    = ceil(double(total_combos) / chunk_size);
    seg_opts_s  = cellfun(@(x) single(x(:, 1:3)), seg_opts, 'UniformOutput', false);
    combo_time  = zeros(total_combos, 1, 'single');
    combo_fuel  = zeros(total_combos, 1, 'single');
    idx_mat     = zeros(total_combos, n_segs, 'uint16');

    for chunk_i = 1:n_chunks
        i_start = uint64(chunk_i - 1) * uint64(chunk_size);
        i_end   = min(i_start + uint64(chunk_size) - uint64(1), uint64(total_combos - 1));
        n_this  = double(i_end - i_start) + 1;
        g_rows  = double(i_start) + 1 : double(i_start) + n_this;

        idx_chunk = zeros(n_this, n_segs, 'uint16');
        remaining = i_start + uint64(0 : n_this - 1)';
        for si = n_segs : -1 : 1
            n_i = uint64(n_opts(si));
            idx_chunk(:, si) = uint16(mod(remaining, n_i)) + 1;
            remaining        = idivide(remaining, n_i, 'floor');
        end
        clear remaining;
        idx_mat(g_rows, :) = idx_chunk;

        for si = 1:n_segs
            o    = seg_opts_s{si};
            rows = double(idx_chunk(:, si));
            combo_time(g_rows) = combo_time(g_rows) + o(rows, 2);  %#ok<AGROW>
            combo_fuel(g_rows) = combo_fuel(g_rows) + o(rows, 3);  %#ok<AGROW>
        end
        clear idx_chunk;
    end
end

%% --- Step 3: For each target, find the best-matching combination -----------
% "Closest" = minimum |combo_fuel - target|.
% Ties broken by minimum time penalty (most efficient route to that fuel).

results = [];
n_targets = numel(fuel_targets_kg);

for ti = 1:n_targets
    if use_dp
        % DP solver: finds exact optimum without enumerating all combinations
        [alloc_idx_row, achieved_kg_dp, time_pen_dp] = dp_find_target(seg_opts, fuel_targets_kg(ti));
        fprintf('[TargetSave] Target %.4f kg -> achieved %.4f kg  |  time: %.3f s  [DP]\n', ...
            fuel_targets_kg(ti), achieved_kg_dp, time_pen_dp);
        alloc = build_allocation(seg_opts, seg_names, seg_ids, alloc_idx_row, ok_v);
        r_achieved_kg   = achieved_kg_dp;
        r_time_pen      = time_pen_dp;
    else
        target    = single(fuel_targets_kg(ti));
        fuel_diff = abs(combo_fuel - target);
        min_diff  = min(fuel_diff);
        tol       = max(single(0.0005), min_diff * single(1.01));
        candidate = fuel_diff <= tol;
        [~, ci]   = min(combo_time .* single(candidate) + single(1e6) .* single(~candidate));
        fprintf('[TargetSave] Target %.4f kg -> achieved %.4f kg  |  time: %.3f s\n', ...
            fuel_targets_kg(ti), combo_fuel(ci), combo_time(ci));
        alloc = build_allocation(seg_opts, seg_names, seg_ids, idx_mat(ci, :), ok_v);
        r_achieved_kg = double(combo_fuel(ci));
        r_time_pen    = double(combo_time(ci));
    end

    % Build combined full-lap speed trace
    [d_out, v_orig, v_combined] = build_speed_trace(lap, preceding_lap, alloc, ok_v);

    r.target_kg            = fuel_targets_kg(ti);
    r.achieved_kg          = r_achieved_kg;
    r.time_penalty_sec     = r_time_pen;
    r.efficiency_kg_per_s  = r.achieved_kg / max(r.time_penalty_sec, 1e-9);
    r.allocation           = alloc;
    r.lap_distance         = d_out;
    r.lap_speed_combined   = v_combined;
    r.lap_speed_original   = v_orig;

    if isempty(results)
        results = r;
    else
        results(end + 1) = r;  %#ok<AGROW>
    end
end

%% --- Step 4: Plot -----------------------------------------------------------

plot_speed_traces(results, seg_names, segments, output_dir);

%% --- Step 5: Save XLSX summary ---------------------------------------------

save_target_xlsx(results, seg_names, output_dir);

fprintf('[TargetSave] Complete. Output saved to: %s\n\n', output_dir);

end % main function


%% ===========================================================================
%  BUILD ALLOCATION STRUCT
%% ===========================================================================
function [alloc_idx, achieved_kg, achieved_time] = dp_find_target(seg_opts, target_kg)
% DP solver: finds the allocation (one option per segment) whose total fuel
% saving is closest to target_kg with minimum time penalty.
% Complexity: O(n_segs * n_opts * n_fuel_levels) — very fast even for 8 segments × 101 options.

    FUEL_RES = single(0.0005);   % 0.5 g resolution
    n_segs   = numel(seg_opts);

    % Size the DP table: maximum achievable fuel across all segments
    max_fuel = single(0);
    for si = 1:n_segs
        max_fuel = max_fuel + single(max(seg_opts{si}(:, 3)));
    end
    n_levels = ceil(max_fuel / FUEL_RES) + 2;   % 1-based: level f+1 = f*FUEL_RES kg

    INF_T = single(1e9);
    dp   = INF_T * ones(n_levels, 1, 'single');
    dp(1) = single(0);                          % 0 fuel, 0 time
    back = zeros(n_segs, n_levels, 'uint8');    % back(si,f) = option idx chosen for seg si

    for si = 1:n_segs
        opts     = seg_opts{si};   % [coast_m, time_s, fuel_kg, var_idx]
        n_oi     = size(opts, 1);
        dp_new   = INF_T * ones(n_levels, 1, 'single');
        back_new = zeros(1, n_levels, 'uint8');

        for oi = 1:n_oi
            df = max(0, round(single(opts(oi, 3)) / FUEL_RES));  % fuel quanta added
            dt = single(opts(oi, 2));                            % time penalty added

            prev_idx = find(dp < INF_T);                        % reachable states
            new_idx  = prev_idx + df;
            keep     = new_idx <= n_levels;
            prev_idx = prev_idx(keep);
            new_idx  = new_idx(keep);
            if isempty(prev_idx), continue; end

            new_t   = dp(prev_idx) + dt;
            improve = new_t < dp_new(new_idx);
            dp_new(new_idx(improve))   = new_t(improve);
            back_new(new_idx(improve)) = uint8(oi);
        end

        dp = dp_new;
        back(si, :) = back_new;
    end

    % Find fuel level closest to target, tie-break on minimum time
    fuel_levels = single(0:n_levels-1)' * FUEL_RES;
    achievable  = dp < INF_T;
    fuel_diff   = abs(fuel_levels - single(target_kg));
    fuel_diff(~achievable) = INF_T;
    min_diff    = min(fuel_diff);
    tol         = max(single(0.0005), min_diff * single(1.01));
    candidate   = achievable & (fuel_diff <= tol);
    dp_cand     = dp;
    dp_cand(~candidate) = INF_T;
    [~, best_f] = min(dp_cand);

    achieved_kg   = double(fuel_levels(best_f));
    achieved_time = double(dp(best_f));

    % Backtrack to reconstruct per-segment option choices
    alloc_idx = ones(1, n_segs, 'uint16');   % default: option 1 = no-coast
    curr_f    = best_f;
    for si = n_segs:-1:1
        oi = double(back(si, curr_f));
        if oi == 0; oi = 1; end              % fallback to no-coast
        alloc_idx(si) = uint16(oi);
        df     = max(0, round(single(seg_opts{si}(oi, 3)) / FUEL_RES));
        curr_f = max(1, curr_f - df);
    end
end


function alloc = build_allocation(seg_opts, seg_names, seg_ids, idx_row, ok_v)
% Reconstruct per-segment allocation from chosen row indices.
    n_segs = numel(seg_opts);
    alloc  = [];
    for si = 1:n_segs
        row = double(idx_row(si));
        opt = seg_opts{si}(row, :);   % [coast_m, time_s, fuel_kg, var_idx]

        a.segment_idx      = seg_ids(si);
        a.segment_name     = seg_names{si};
        a.coasting_dist_m  = opt(1);
        a.time_penalty_sec = opt(2);
        a.fuel_saved_kg    = opt(3);

        % Attach the source variant for speed trace extraction
        vi = round(opt(4));
        if vi > 0 && vi <= numel(ok_v)
            a.variant = ok_v(vi);
        else
            a.variant = [];
        end

        if isempty(alloc)
            alloc = a;
        else
            alloc(end + 1) = a;  %#ok<AGROW>
        end
    end
end


%% ===========================================================================
%  BUILD COMBINED FULL-LAP SPEED TRACE
%% ===========================================================================
function [d_out, v_orig, v_combined] = build_speed_trace(lap, preceding_lap, alloc, ok_v)  %#ok<INUSD>
% Assemble a full-lap speed trace by pasting the coasted windows from each
% chosen segment variant into the original lap speed profile.
% preceding_lap, when provided, extends the distance axis into negatives
% for S01 (main straight before finish line) — matching smp_plot_fuel_save_variants.

    % --- Original timed lap distance and speed ---
    % Use .dist first (the sampled-distance axis), fall back to .data — same
    % logic as smp_plot_fuel_save_variants to avoid a garbled distance axis.
    if isfield(lap.channels, 'Distance')
        d_timed = lap.channels.Distance.dist(:);
        if isempty(d_timed)
            d_timed = lap.channels.Distance.data(:);
        end
    elseif isfield(lap.channels, 'Lap_Distance')
        d_timed = lap.channels.Lap_Distance.dist(:);
        if isempty(d_timed)
            d_timed = lap.channels.Lap_Distance.data(:);
        end
    else
        d_timed = lap.channels.Ground_Speed.dist(:);
    end
    spd_raw  = lap.channels.Ground_Speed.data(:);
    dist_spd = lap.channels.Ground_Speed.dist(:);
    v_timed  = interp1(dist_spd, spd_raw, d_timed, 'linear', 'extrap');

    % --- Prepend preceding lap (negative offsets) — same as smp_plot_fuel_save_variants ---
    if ~isempty(preceding_lap) && isstruct(preceding_lap) && isfield(preceding_lap, 'channels')
        dist_cands = {'Distance', 'Odometer', 'Lap_Distance'};
        p_dist_raw = [];
        for kk = 1:numel(dist_cands)
            if isfield(preceding_lap.channels, dist_cands{kk})
                p_dist_raw = preceding_lap.channels.(dist_cands{kk}).dist(:);
                if isempty(p_dist_raw)
                    p_dist_raw = preceding_lap.channels.(dist_cands{kk}).data(:);
                end
                break;
            end
        end
        if ~isempty(p_dist_raw) && isfield(preceding_lap.channels, 'Ground_Speed')
            p_dist  = p_dist_raw - p_dist_raw(end);   % shift so end = 0 (finish line)
            keep_p  = p_dist < 0;
            p_spd   = interp1(preceding_lap.channels.Ground_Speed.dist(:), ...
                              preceding_lap.channels.Ground_Speed.data(:), ...
                              p_dist_raw(keep_p), 'linear', 'extrap');
            d_timed = [p_dist(keep_p); d_timed];
            v_timed = [p_spd(:);       v_timed];
        end
    end

    d_out  = d_timed;
    v_orig = v_timed;
    v_combined = v_orig;   % start from original; patch coasted windows below

    for ai = 1:numel(alloc)
        a = alloc(ai);
        if isempty(a.variant) || a.coasting_dist_m < 0.5
            continue;   % no-coast for this segment — leave original
        end

        var = a.variant;

        % Coasting window bounds
        if isfield(var, 'details') && isfield(var.details, 'coasting_start_dist')
            c_start = var.details.coasting_start_dist;
            c_end   = var.details.coasting_end_dist;
        else
            % Fallback: infer window from where variant speed differs from original
            v_var_on_orig = interp1(var.distance, var.speed_trace, d_out, 'linear', NaN);
            diff_mask = ~isnan(v_var_on_orig) & abs(v_var_on_orig - v_orig) > 0.5;
            if ~any(diff_mask)
                continue;
            end
            c_start = d_out(find(diff_mask, 1, 'first'));
            c_end   = d_out(find(diff_mask, 1, 'last'));
        end

        % Points on original distance axis that fall inside the coasting window
        in_window = d_out >= c_start & d_out <= c_end;
        if ~any(in_window)
            continue;
        end

        % Interpolate variant's speed onto those distance points
        v_coasted = interp1(var.distance, var.speed_trace, d_out(in_window), 'pchip', NaN);
        valid_pts  = ~isnan(v_coasted);

        window_idx = find(in_window);
        v_combined(window_idx(valid_pts)) = v_coasted(valid_pts);
    end
end


%% ===========================================================================
%  PLOT
%% ===========================================================================
function plot_speed_traces(results, seg_names, segments, output_dir)  %#ok<INUSD>
    n_targets = numel(results);
    if n_targets == 0; return; end

    % Colour palette — one colour per target
    cmap = lines(n_targets);

    % Build segment shading boundaries from segments struct
    seg_dist_starts = [segments.distance_start];
    seg_dist_ends   = [segments.distance_end];
    seg_label_names = {segments.segment_name};

    % X-axis limits: exactly S01 distance_start to last segment distance_end
    % (matches smp_plot_fuel_save_variants master lap trace range)
    x_lo = seg_dist_starts(1);
    x_hi = seg_dist_ends(end);

    %% Figure 1: Full lap speed traces (all targets overlaid)
    fig1 = figure('Position', [80 80 1200 560]);
    ax1  = axes(fig1);
    hold(ax1, 'on');

    % Shade each segment region
    y_lo = min(results(1).lap_speed_original) * 0.95;
    y_hi = max(results(1).lap_speed_original) * 1.05;
    for si = 1:numel(seg_dist_starts)
        patch(ax1, ...
            [seg_dist_starts(si), seg_dist_ends(si), seg_dist_ends(si), seg_dist_starts(si)], ...
            [y_lo, y_lo, y_hi, y_hi], ...
            [0.93 0.93 0.93], 'EdgeColor', 'none', 'HandleVisibility', 'off');
        text(ax1, (seg_dist_starts(si) + seg_dist_ends(si)) / 2, y_hi * 0.98, ...
            sprintf('S%02d', si), 'FontSize', 7, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
            'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
    end

    % Original lap — thick black
    d_ref = results(1).lap_distance;
    v_ref = results(1).lap_speed_original;
    plot(ax1, d_ref, v_ref, 'k-', 'LineWidth', 2.5, 'DisplayName', 'Original lap');

    % Each target combination
    for ti = 1:n_targets
        r   = results(ti);
        lbl = sprintf('Target %.3f kg $\\rightarrow$ %.3f kg $|$ +%.3f s $|$ %.4f kg/s', ...
            r.target_kg, r.achieved_kg, r.time_penalty_sec, r.efficiency_kg_per_s);
        plot(ax1, r.lap_distance, r.lap_speed_combined, '-', ...
            'Color', cmap(ti, :), 'LineWidth', 1.6, 'DisplayName', lbl);
    end

    xlabel(ax1, 'Lap Distance (m)');
    ylabel(ax1, 'Speed (km/h)');
    title(ax1, 'Target Fuel-Save Combinations --- Full Lap Speed Traces', ...
        'FontWeight', 'bold');
    legend(ax1, 'Location', 'southoutside', 'FontSize', 8, 'NumColumns', 2, ...
        'Interpreter', 'latex');
    grid(ax1, 'on');
    box(ax1, 'on');
    xlim(ax1, [x_lo, x_hi]);
    ylim(ax1, [y_lo, y_hi]);

    out1 = fullfile(output_dir, 'smp_target_fuel_save_traces.png');
    exportgraphics(fig1, out1, 'Resolution', 150);
    fprintf('[TargetSave] Speed trace plot: %s\n', out1);

    %% Figure 2: Delta speed vs distance (coasted - original), one line per target
    fig2 = figure('Position', [80 80 1200 400]);
    ax2  = axes(fig2);
    hold(ax2, 'on');
    yline(ax2, 0, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off');

    for ti = 1:n_targets
        r     = results(ti);
        delta = r.lap_speed_combined - r.lap_speed_original;
        lbl   = sprintf('Target %.3f kg (achieved %.3f kg)', r.target_kg, r.achieved_kg);
        plot(ax2, r.lap_distance, delta, '-', ...
            'Color', cmap(ti, :), 'LineWidth', 1.5, 'DisplayName', lbl);
    end

    % Segment boundary ticks
    for si = 1:numel(seg_dist_starts)
        xline(ax2, seg_dist_starts(si), ':', 'Color', [0.7 0.7 0.7], ...
            'HandleVisibility', 'off');
    end

    xlabel(ax2, 'Lap Distance (m)', 'Interpreter', 'latex');
    ylabel(ax2, '$\Delta$ Speed (km/h)', 'Interpreter', 'latex');
    title(ax2, 'Speed Delta vs Original Lap (negative $=$ slower $=$ coasting)', ...
        'FontWeight', 'bold', 'Interpreter', 'latex');
    legend(ax2, 'Location', 'southoutside', 'FontSize', 8, 'NumColumns', 2, ...
        'Interpreter', 'latex');
    grid(ax2, 'on');
    box(ax2, 'on');
    xlim(ax2, [x_lo, x_hi]);

    out2 = fullfile(output_dir, 'smp_target_fuel_save_delta.png');
    exportgraphics(fig2, out2, 'Resolution', 150);
    fprintf('[TargetSave] Delta speed plot: %s\n', out2);
end


%% ===========================================================================
%  XLSX SUMMARY
%% ===========================================================================
function save_target_xlsx(results, seg_names, output_dir)
    n  = numel(results);
    n_segs = numel(seg_names);

    target_v   = [results.target_kg]';
    achieved_v = [results.achieved_kg]';
    time_v     = [results.time_penalty_sec]';
    eff_v      = [results.efficiency_kg_per_s]';

    T = table(target_v, achieved_v, time_v, eff_v, ...
        'VariableNames', {'Target_Fuel_kg', 'Achieved_Fuel_kg', ...
                          'Time_Penalty_sec', 'Efficiency_kg_per_s'});

    for si = 1:n_segs
        col_name = matlab.lang.makeValidName(seg_names{si});
        col_data = zeros(n, 1);
        for ri = 1:n
            if si <= numel(results(ri).allocation)
                col_data(ri) = results(ri).allocation(si).coasting_dist_m;
            end
        end
        T.(col_name) = col_data;
    end

    out_path = fullfile(output_dir, 'smp_target_fuel_save.xlsx');
    writetable(T, out_path, 'Sheet', 'TargetCombinations');
    fprintf('[TargetSave] XLSX saved: %s\n', out_path);
end


%% ===========================================================================
%  UTILITY
%% ===========================================================================
function s = fmt_large(n)
    if n >= 1e9;      s = sprintf('%.2fB', n/1e9);
    elseif n >= 1e6;  s = sprintf('%.2fM', n/1e6);
    elseif n >= 1e3;  s = sprintf('%.1fK', n/1e3);
    else;             s = sprintf('%d', n);
    end
end
