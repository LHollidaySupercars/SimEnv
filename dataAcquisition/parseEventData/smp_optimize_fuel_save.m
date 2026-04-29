function [optimal, pareto_curve] = smp_optimize_fuel_save(variants, segments, varargin)
% SMP_OPTIMIZE_FUEL_SAVE  Cross-segment Pareto-optimal fuel-save allocation
%
% For a given lap-time budget (or a full Pareto sweep), finds the coasting
% level per segment that maximises total fuel saved subject to the total
% time penalty not exceeding the budget.  The problem is separable — each
% segment has an independent monotone (time_penalty, fuel_saved) curve —
% so a standard constrained optimiser works efficiently.
%
% USAGE:
%   [optimal, pareto_curve] = smp_optimize_fuel_save(variants, segments)
%   [optimal, pareto_curve] = smp_optimize_fuel_save(variants, segments, ...
%       'time_budget', 1.5, 'output_dir', './out')
%
% INPUTS:
%   variants  (struct array)  Output from smp_fuel_save_coasting — must
%                             contain fields: segment_idx, segment_name,
%                             time_penalty_sec, fuel_saved_kg, coasting_point,
%                             status.
%   segments  (struct array)  Segment definitions (passed through for context;
%                             not directly used by the solver).
%
% OPTIONAL PARAMETERS:
%   time_budget    (double)   Total lap-time loss budget in seconds.
%                             NaN = maximise fuel with no time constraint
%                             (equivalent to budget = T_max).  [default: NaN]
%   output_dir     (string)   Folder for output files.          [default: './fuel_save_output']
%   n_pareto_steps (integer)  Number of points on the Pareto curve. [default: 60]
%   dp_bins        (integer)  DP discretisation resolution (only used when
%                             Optimization Toolbox is absent).  [default: 200]
%
% OUTPUTS:
%   optimal (struct)
%     .allocation  (struct array, n_segs x 1)  Per-segment result:
%                    .segment_idx, .segment_name,
%                    .coasting_dist_m   — distance before brake marker (m, positive)
%                    .time_penalty_sec  — time allocated to this segment (s)
%                    .fuel_saved_kg     — fuel saved by this segment (kg)
%     .total_fuel_saved_kg     — sum across segments (kg)
%     .total_time_penalty_sec  — sum across segments (s)
%     .method                  — 'fmincon' or 'dp'
%
%   pareto_curve (struct)
%     .time_penalty_vec  [1 x N]  Total time budgets swept (s)
%     .fuel_saved_vec    [1 x N]  Optimal fuel saved at each budget (kg)
%     .segment_time_mat  [N x S]  Per-segment time-allocation matrix
%
% ALGORITHM:
%   1. Filter variants to 'success'; group by segment_idx.
%   2. Per segment: sort by time_penalty, enforce monotonicity, prepend
%      origin (0,0), build pchip griddedInterpolant fuel_i = f(time_i).
%   3. Pareto sweep: solve constrained optimisation at n_pareto_steps budgets
%      from 0 to T_max.
%      — If Optimization Toolbox present: fmincon (SQP, gradient-free obj).
%      — Otherwise: multiple-choice DP knapsack on discretised time grid.
%   4. Return optimal allocation for the user-supplied budget.
%   5. Save Pareto PNG and optimal-allocation XLSX to output_dir.

%% --- Input parsing -----------------------------------------------------------

p = inputParser;
addParameter(p, 'time_budget',    NaN,                    @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'output_dir',     './fuel_save_output',   @ischar);
addParameter(p, 'n_pareto_steps', 60,                     @(x) isnumeric(x) && isscalar(x) && x > 1);
addParameter(p, 'dp_bins',        200,                    @(x) isnumeric(x) && isscalar(x) && x > 10);
parse(p, varargin{:});

time_budget    = p.Results.time_budget;
output_dir     = p.Results.output_dir;
n_pareto_steps = round(p.Results.n_pareto_steps);
dp_bins        = round(p.Results.dp_bins);

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

has_opt = license('test', 'optimization_toolbox');
method  = ifelse_local(has_opt, 'fmincon', 'dp');

%% --- Step 1: Filter and build per-segment interpolants ----------------------

ok_mask = strcmp({variants.status}, 'success');
ok_v    = variants(ok_mask);

if isempty(ok_v)
    error('smp_optimize_fuel_save: no successful variants found in input.');
end

seg_ids = unique([ok_v.segment_idx]);
n_segs  = numel(seg_ids);

% Pre-allocate curve structs
empty_curve = struct('segment_idx', 0, 'segment_name', '', ...
    'time_vec', [], 'fuel_vec', [], 'interp', [], ...
    'max_time', 0, 'max_fuel', 0);
seg_curves = repmat(empty_curve, n_segs, 1);

for si = 1:n_segs
    sid  = seg_ids(si);
    mask = ([ok_v.segment_idx] == sid);
    sv   = ok_v(mask);

    % Sort by time penalty ascending
    [t_sorted, order] = sort([sv.time_penalty_sec]);
    f_sorted = [sv.fuel_saved_kg];
    f_sorted = f_sorted(order);

    % Deduplicate time values (keep max fuel per unique time)
    [t_u, ia, ~] = unique(t_sorted);
    f_u = f_sorted(ia);

    % Enforce monotonicity via cumulative max (simulation noise can cause dips)
    f_u = cummax_local(f_u);

    % Prepend origin: zero coasting = zero fuel saved, zero time lost
    if t_u(1) > 1e-6
        t_u = [0, t_u];
        f_u = [0, f_u];
    end

    % Build interpolant
    if numel(t_u) >= 2
        interp_fn = griddedInterpolant(t_u, f_u, 'pchip');
    else
        interp_fn = griddedInterpolant([0, t_u(end) + eps], [0, f_u(end)], 'linear');
    end

    seg_curves(si).segment_idx  = sid;
    seg_curves(si).segment_name = sv(1).segment_name;
    seg_curves(si).time_vec     = t_u;
    seg_curves(si).fuel_vec     = f_u;
    seg_curves(si).interp       = interp_fn;
    seg_curves(si).max_time     = t_u(end);
    seg_curves(si).max_fuel     = f_u(end);
end

% Global time bound
T_max = sum([seg_curves.max_time]);
user_supplied_budget = ~isnan(time_budget) && time_budget < T_max;
time_budget = min(max(ifelse_local(isnan(time_budget), T_max, time_budget), 0), T_max);

fprintf('[Optimizer] Segments: %d  |  T_max: %.3f s  |  Solver: %s\n', ...
    n_segs, T_max, method);

%% --- Step 2: Pareto sweep ---------------------------------------------------

t_budgets   = linspace(0, T_max, n_pareto_steps);
pareto_fuel = zeros(1, n_pareto_steps);
pareto_tmat = zeros(n_pareto_steps, n_segs);

for pi = 1:n_pareto_steps
    T_b = t_budgets(pi);
    if T_b < 1e-9
        continue;
    end
    if has_opt
        t_alloc = solve_fmincon(seg_curves, T_b);
    else
        t_alloc = solve_dp(seg_curves, T_b, dp_bins);
    end
    pareto_fuel(pi)      = eval_total_fuel(seg_curves, t_alloc);
    pareto_tmat(pi, :)   = t_alloc(:)';
end

pareto_curve.time_penalty_vec = t_budgets;
pareto_curve.fuel_saved_vec   = pareto_fuel;
pareto_curve.segment_time_mat = pareto_tmat;

%% --- Step 3: Optimal allocation — target best efficiency -------------------
% Default (no explicit budget): choose the Pareto point with the highest
% fuel_saved / time_penalty ratio (most kg saved per second of lap time
% lost), i.e. the steepest-slope point on the frontier.
% When the user supplies an explicit time_budget, honour it instead.

if ~user_supplied_budget
    valid_mask = t_budgets > 0.001 & pareto_fuel > 1e-6;
    eff_sweep  = pareto_fuel ./ max(t_budgets, 1e-9);
    eff_sweep(~valid_mask) = -Inf;
    [best_eff, best_pi] = max(eff_sweep);
    time_budget = t_budgets(best_pi);
    fprintf('[Optimizer] Best-efficiency budget: %.3f s  (%.4f kg/s)\n', ...
        time_budget, best_eff);
else
    fprintf('[Optimizer] User budget: %.3f s\n', time_budget);
end

if has_opt
    t_alloc_opt = solve_fmincon(seg_curves, time_budget);
else
    t_alloc_opt = solve_dp(seg_curves, time_budget, dp_bins);
end

allocation = build_allocation(seg_curves, t_alloc_opt, ok_v);

optimal.allocation             = allocation;
optimal.total_fuel_saved_kg    = sum([allocation.fuel_saved_kg]);
optimal.total_time_penalty_sec = sum([allocation.time_penalty_sec]);
optimal.efficiency_kg_per_s    = optimal.total_fuel_saved_kg / max(optimal.total_time_penalty_sec, 1e-9);
optimal.method                 = method;

%% --- Step 4: Print summary --------------------------------------------------

fprintf('\n');
fprintf('===========================================\n');
fprintf('  OPTIMAL FUEL-SAVE ALLOCATION\n');
fprintf('  Target: best efficiency (kg saved per s lost)\n');
fprintf('  Solver: %s  |  Budget used: %.3f s\n', method, time_budget);
fprintf('===========================================\n');
fprintf('  %-22s  %9s  %9s  %9s\n', 'Segment', 'Coast(m)', 'Time(s)', 'Fuel(kg)');
fprintf('  %s\n', repmat('-', 1, 56));
for ai = 1:numel(allocation)
    a = allocation(ai);
    fprintf('  %-22s  %9.1f  %9.3f  %9.4f\n', ...
        a.segment_name, a.coasting_dist_m, a.time_penalty_sec, a.fuel_saved_kg);
end
fprintf('  %s\n', repmat('-', 1, 56));
fprintf('  %-22s  %9s  %9.3f  %9.4f\n', 'TOTAL', '', ...
    optimal.total_time_penalty_sec, optimal.total_fuel_saved_kg);
fprintf('  %-22s  %9s  %9s  %9.4f  kg/s\n', 'EFFICIENCY', '', '', ...
    optimal.efficiency_kg_per_s);
fprintf('\n');

%% --- Step 5: Rank top-10 most efficient combinations -----------------------
% Efficiency = fuel_saved / time_penalty (kg/s).  Each row of pareto_tmat
% is one multi-segment combination produced by the Pareto sweep.  We
% evaluate efficiency for every non-trivial sweep point and return the best
% 10 in descending order.

top10 = rank_top_combos(pareto_curve, seg_curves, ok_v, 10);
optimal.top10 = top10;

print_top10(top10, seg_curves);

%% --- Step 6: Save outputs ---------------------------------------------------

save_pareto_plot(pareto_curve, seg_curves, time_budget, optimal, output_dir);
save_optimal_xlsx(allocation, optimal, top10, output_dir);

fprintf('[Optimizer] Output saved to: %s\n\n', output_dir);

end % main function


%% ===========================================================================
%  LOCAL SOLVER: fmincon  (requires Optimization Toolbox)
%% ===========================================================================
function t_alloc = solve_fmincon(seg_curves, T_budget)
    n  = numel(seg_curves);
    lb = zeros(n, 1);
    ub = [seg_curves.max_time]';

    % Warm start: proportional allocation capped by per-segment maxima
    if T_budget >= sum(ub)
        x0 = ub;
    else
        x0 = ub * (T_budget / sum(ub));
    end

    % Objective: maximise total fuel = minimise negated total fuel
    obj = @(t) -eval_total_fuel(seg_curves, t);

    % Linear inequality: sum(t) <= T_budget
    A = ones(1, n);
    b = T_budget;

    opts = optimoptions('fmincon', ...
        'Display',           'off', ...
        'Algorithm',         'sqp', ...
        'MaxIterations',     500,   ...
        'FunctionTolerance', 1e-9,  ...
        'StepTolerance',     1e-9);

    t_alloc = fmincon(obj, x0, A, b, [], [], lb, ub, [], opts);
    t_alloc = max(t_alloc, 0);
end


%% ===========================================================================
%  LOCAL SOLVER: Multiple-choice DP knapsack  (no toolbox required)
%% ===========================================================================
function t_alloc = solve_dp(seg_curves, T_budget, n_bins)
    n  = numel(seg_curves);
    dt = T_budget / n_bins;   % seconds per bin

    % dp(si+1, k+1) = max fuel using first si segments, total bins <= k
    dp     = zeros(n + 1, n_bins + 1);
    choice = zeros(n, n_bins + 1, 'int16');   % bins allocated to segment si

    for si = 1:n
        sc = seg_curves(si);
        max_bins_seg = min(n_bins, floor(sc.max_time / dt));

        % Precompute fuel saved at 0..max_bins_seg bins for this segment
        bins_range  = 0:max_bins_seg;
        t_range     = min(bins_range * dt, sc.max_time);
        fuel_at_bin = sc.interp(t_range);
        fuel_at_bin = max(fuel_at_bin, 0);   % clamp pchip overshoots

        for k = 0:n_bins
            % Default: zero bins for this segment
            best_val    = dp(si, k + 1);
            best_j      = 0;

            % Try allocating j bins to this segment
            for j = 1:min(k, max_bins_seg)
                candidate = dp(si, k - j + 1) + fuel_at_bin(j + 1);
                if candidate > best_val
                    best_val = candidate;
                    best_j   = j;
                end
            end

            dp(si + 1, k + 1)  = best_val;
            choice(si, k + 1)  = int16(best_j);
        end
    end

    % Backtrack: recover per-segment bin allocation
    bins_alloc = zeros(n, 1);
    remaining  = n_bins;
    for si = n:-1:1
        j_chosen       = double(choice(si, remaining + 1));
        bins_alloc(si) = j_chosen;
        remaining      = remaining - j_chosen;
    end

    % Convert bins to seconds, respect per-segment upper bounds
    t_alloc = bins_alloc * dt;
    t_alloc = min(t_alloc, [seg_curves.max_time]');
end


%% ===========================================================================
%  HELPERS
%% ===========================================================================
function fuel = eval_total_fuel(seg_curves, t_alloc)
    fuel = 0;
    for si = 1:numel(seg_curves)
        t_i  = min(max(t_alloc(si), 0), seg_curves(si).max_time);
        fuel = fuel + seg_curves(si).interp(t_i);
    end
end

% --------------------------------------------------------------------------
function allocation = build_allocation(seg_curves, t_alloc, ok_variants)
% Map optimal time allocation back to coasting distances by snapping to the
% nearest successful variant (so output values are always physically valid).
    n = numel(seg_curves);
    empty_alloc = struct('segment_idx', 0, 'segment_name', '', ...
        'coasting_dist_m', 0, 'time_penalty_sec', 0, 'fuel_saved_kg', 0);
    allocation = repmat(empty_alloc, n, 1);

    for si = 1:n
        sc  = seg_curves(si);
        t_i = min(max(t_alloc(si), 0), sc.max_time);

        % Fuel from interpolant
        f_i = max(sc.interp(t_i), 0);

        % Snap to nearest variant for an actionable coasting distance
        seg_vars = ok_variants([ok_variants.segment_idx] == sc.segment_idx);
        if ~isempty(seg_vars)
            t_diffs  = abs([seg_vars.time_penalty_sec] - t_i);
            [~, idx] = min(t_diffs);
            coast_m  = seg_vars(idx).coasting_point;
        else
            coast_m = 0;
        end

        allocation(si).segment_idx      = sc.segment_idx;
        allocation(si).segment_name     = sc.segment_name;
        allocation(si).coasting_dist_m  = coast_m;
        allocation(si).time_penalty_sec = t_i;
        allocation(si).fuel_saved_kg    = f_i;
    end
end

% --------------------------------------------------------------------------
function save_pareto_plot(pareto_curve, seg_curves, budget_used, optimal, output_dir)
    fig = figure('Visible', 'off', 'Position', [100 100 960 560]);
    ax  = axes(fig);
    hold(ax, 'on');

    seg_colors = lines(numel(seg_curves));

    % Individual variant scatter per segment
    for si = 1:numel(seg_curves)
        sc = seg_curves(si);
        scatter(ax, sc.time_vec(2:end), sc.fuel_vec(2:end), 28, seg_colors(si,:), ...
            'filled', 'MarkerFaceAlpha', 0.45, ...
            'DisplayName', sc.segment_name);
    end

    % Pareto frontier
    t_vec = pareto_curve.time_penalty_vec;
    f_vec = pareto_curve.fuel_saved_vec;
    plot(ax, t_vec, f_vec, 'k-', 'LineWidth', 2.5, 'DisplayName', 'Pareto frontier');

    % Budget line and optimal point
    xline(ax, budget_used, '--', 'Color', [0.85 0.33 0.1], 'LineWidth', 1.4, ...
        'HandleVisibility', 'off');
    plot(ax, optimal.total_time_penalty_sec, optimal.total_fuel_saved_kg, ...
        'o', 'MarkerSize', 11, ...
        'MarkerFaceColor', [0.85 0.33 0.1], 'MarkerEdgeColor', 'k', ...
        'LineWidth', 1.4, 'DisplayName', sprintf('Optimal (%.3f s)', budget_used));

    % Knee annotation
    [~, knee_idx] = find_knee(t_vec, f_vec);
    if ~isempty(knee_idx) && knee_idx > 1 && knee_idx < numel(t_vec)
        plot(ax, t_vec(knee_idx), f_vec(knee_idx), 'v', ...
            'MarkerSize', 8, 'MarkerFaceColor', [0 0.45 0.74], ...
            'MarkerEdgeColor', 'k', 'DisplayName', 'Efficiency knee');
    end

    xlabel(ax, 'Total Time Penalty (s)');
    ylabel(ax, 'Total Fuel Saved (kg)');
    title(ax, 'Fuel-Save Pareto Frontier — Optimal Cross-Segment Allocation', ...
        'FontWeight', 'bold');
    legend(ax, 'Location', 'southeast', 'FontSize', 8);
    grid(ax, 'on');
    box(ax, 'on');

    out_path = fullfile(output_dir, 'smp_fuel_save_pareto.png');
    exportgraphics(fig, out_path, 'Resolution', 150);
    close(fig);
    fprintf('[Optimizer] Pareto plot: %s\n', out_path);
end

% --------------------------------------------------------------------------
function save_optimal_xlsx(allocation, optimal, top10, output_dir)
    n = numel(allocation);
    seg_ids   = zeros(n, 1);
    seg_names = cell(n, 1);
    coast_m   = zeros(n, 1);
    t_pen     = zeros(n, 1);
    f_saved   = zeros(n, 1);
    effic     = zeros(n, 1);

    for ai = 1:n
        seg_ids(ai)   = allocation(ai).segment_idx;
        seg_names{ai} = allocation(ai).segment_name;
        coast_m(ai)   = allocation(ai).coasting_dist_m;
        t_pen(ai)     = allocation(ai).time_penalty_sec;
        f_saved(ai)   = allocation(ai).fuel_saved_kg;
        effic(ai)     = f_saved(ai) / max(t_pen(ai), 1e-9);
    end

    % Summary row
    seg_ids_out   = [seg_ids;   NaN];
    seg_names_out = [seg_names; {'TOTAL'}];
    coast_m_out   = [coast_m;   NaN];
    t_pen_out     = [t_pen;     optimal.total_time_penalty_sec];
    f_saved_out   = [f_saved;   optimal.total_fuel_saved_kg];
    effic_out     = [effic;     optimal.total_fuel_saved_kg / max(optimal.total_time_penalty_sec, 1e-9)];

    T = table(seg_ids_out, seg_names_out, coast_m_out, t_pen_out, f_saved_out, effic_out, ...
        'VariableNames', {'Segment_ID', 'Segment_Name', 'Coasting_Dist_m', ...
                          'Time_Penalty_sec', 'Fuel_Saved_kg', 'Efficiency_kg_per_s'});

    out_path = fullfile(output_dir, 'smp_fuel_save_optimal.xlsx');
    writetable(T, out_path, 'Sheet', 'OptimalAllocation');

    % Write top-10 sheet
    if ~isempty(top10)
        n10 = numel(top10);
        ranks       = (1:n10)';
        t10_time    = [top10.total_time_penalty_sec]';
        t10_fuel    = [top10.total_fuel_saved_kg]';
        t10_eff     = [top10.efficiency_kg_per_s]';
        seg_coast_cols = top10(1).coast_m_per_seg;   % just for sizing
        n_s = numel(seg_coast_cols);
        coast_mat = zeros(n10, n_s);
        for ri = 1:n10
            coast_mat(ri, :) = top10(ri).coast_m_per_seg;
        end
        T10 = table(ranks, t10_fuel, t10_time, t10_eff, ...
            'VariableNames', {'Rank', 'Fuel_Saved_kg', 'Time_Penalty_sec', 'Efficiency_kg_per_s'});
        % Append per-segment coast columns
        for si = 1:n_s
            col_name = matlab.lang.makeValidName(top10(1).seg_names{si});
            T10.(col_name) = coast_mat(:, si);
        end
        writetable(T10, out_path, 'Sheet', 'Top10_Combinations');
    end

    fprintf('[Optimizer] Optimal allocation XLSX: %s\n', out_path);
end

% --------------------------------------------------------------------------
function [knee_t, knee_idx] = find_knee(t_vec, f_vec)
% Maximum Menger curvature point on the normalised Pareto curve.
    n = numel(t_vec);
    if n < 3
        knee_t   = [];
        knee_idx = [];
        return;
    end

    t_r = range(t_vec);
    f_r = range(f_vec);
    t_n = (t_vec - min(t_vec)) / max(t_r, eps);
    f_n = (f_vec - min(f_vec)) / max(f_r, eps);

    curvature = zeros(n, 1);
    for i = 2:n-1
        dx1 = t_n(i)   - t_n(i-1);  dy1 = f_n(i)   - f_n(i-1);
        dx2 = t_n(i+1) - t_n(i);    dy2 = f_n(i+1) - f_n(i);
        cross_p = abs(dx1*dy2 - dy1*dx2);
        d1 = hypot(dx1, dy1);
        d2 = hypot(dx2, dy2);
        d3 = hypot(t_n(i+1)-t_n(i-1), f_n(i+1)-f_n(i-1));
        curvature(i) = 2 * cross_p / max(d1*d2*d3, eps);
    end

    [~, knee_idx] = max(curvature);
    knee_t = t_vec(knee_idx);
end

% --------------------------------------------------------------------------
function top10 = rank_top_combos(pareto_curve, seg_curves, ok_v, n_top)
% Select up to n_top sweep points with the highest fuel_saved/time_penalty
% ratio (most fuel per second of lap time lost).  Only points with a
% meaningful time penalty (> 1 ms) are considered so the origin is excluded.
    t_vec = pareto_curve.time_penalty_vec;
    f_vec = pareto_curve.fuel_saved_vec;
    tmat  = pareto_curve.segment_time_mat;   % [N x n_segs]

    valid = t_vec > 0.001 & f_vec > 1e-6;
    if ~any(valid)
        top10 = [];
        return;
    end

    eff = f_vec ./ t_vec;          % efficiency at each sweep point
    eff(~valid) = -Inf;

    [eff_sorted, order] = sort(eff, 'descend');
    n_pick = min(n_top, sum(valid));
    top10  = [];

    for ri = 1:n_pick
        pi        = order(ri);
        t_alloc_i = tmat(pi, :);   % [1 x n_segs] seconds per segment
        alloc_i   = build_allocation(seg_curves, t_alloc_i(:), ok_v);

        s.rank                   = ri;
        s.efficiency_kg_per_s    = eff_sorted(ri);
        s.total_fuel_saved_kg    = f_vec(pi);
        s.total_time_penalty_sec = t_vec(pi);
        s.allocation             = alloc_i;
        s.coast_m_per_seg        = [alloc_i.coasting_dist_m];
        s.seg_names              = {alloc_i.segment_name};

        % First assignment establishes field names; subsequent ones append.
        if isempty(top10)
            top10 = s;
        else
            top10(end + 1) = s;  %#ok<AGROW>
        end
    end
end

% --------------------------------------------------------------------------
function print_top10(top10, seg_curves)
    if isempty(top10)
        return;
    end
    n_segs = numel(seg_curves);
    seg_header = '';
    for si = 1:n_segs
        % Truncate long names to 8 chars for column header
        nm = seg_curves(si).segment_name;
        if numel(nm) > 8; nm = nm(1:8); end
        seg_header = [seg_header, sprintf('  %8s', nm)]; %#ok<AGROW>
    end

    fprintf('\n');
    fprintf('===========================================\n');
    fprintf('  TOP 10 MOST EFFICIENT FUEL-SAVE COMBINATIONS\n');
    fprintf('  Ranked by kg saved per second of lap time lost\n');
    fprintf('===========================================\n');
    fprintf('  %4s  %9s  %9s  %10s%s\n', ...
        'Rank', 'Fuel(kg)', 'Time(s)', 'Eff(kg/s)', seg_header);
    fprintf('  %s\n', repmat('-', 1, 36 + n_segs * 10));
    for ri = 1:numel(top10)
        t = top10(ri);
        coast_str = '';
        for si = 1:n_segs
            if si <= numel(t.coast_m_per_seg) && t.coast_m_per_seg(si) > 0.5
                coast_str = [coast_str, sprintf('  %8.1f', t.coast_m_per_seg(si))]; %#ok<AGROW>
            else
                coast_str = [coast_str, sprintf('  %8s', '-')]; %#ok<AGROW>
            end
        end
        fprintf('  %4d  %9.4f  %9.3f  %10.4f%s\n', ...
            ri, t.total_fuel_saved_kg, t.total_time_penalty_sec, ...
            t.efficiency_kg_per_s, coast_str);
    end
    fprintf('\n  Coast distances are metres before the brake marker.\n\n');
end

% --------------------------------------------------------------------------
function out = cummax_local(x)
    out = x;
    for i = 2:numel(x)
        if out(i) < out(i-1)
            out(i) = out(i-1);
        end
    end
end

% --------------------------------------------------------------------------
function result = ifelse_local(cond, a, b)
    if cond; result = a; else; result = b; end
end
