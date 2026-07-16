function doe = smp_doe_fuel_save(variants, segments, varargin)
% SMP_DOE_FUEL_SAVE  Full Design of Experiments across all lift-and-coast segments
%
% Enumerates every combination of coasting level across all segments using
% the pre-computed discrete variants (no new simulation required).  For
% each combination the total fuel saved and total lap-time penalty are just
% the sum of the individual segment contributions — the problem is fully
% separable so no interaction terms exist.
%
% USAGE:
%   doe = smp_doe_fuel_save(variants, segments)
%   doe = smp_doe_fuel_save(variants, segments, 'n_top', 20, 'output_dir', './out')
%
% INPUTS:
%   variants  (struct array)  Output from smp_fuel_save_coasting.
%   segments  (struct array)  Segment definitions (used for naming only).
%
% OPTIONAL PARAMETERS:
%   n_top       (integer)  Number of top combinations to return. [default: 10]
%   output_dir  (string)   Folder for output PNG and XLSX.       [default: './fuel_save_output']
%   max_combos  (integer)  Abort threshold — if total combinations exceed
%                          this, the function warns and returns empty.
%                          Increase if you have a large grid but enough RAM.
%                          [default: 10e6]
%
% OUTPUT:
%   doe (struct)
%     .combos          (struct array, n_top×1)  Top combinations, sorted by
%                       efficiency (fuel_saved_kg / time_penalty_sec).
%                       Each entry:
%                         .rank
%                         .total_fuel_saved_kg
%                         .total_time_penalty_sec
%                         .efficiency_kg_per_s
%                         .allocation  (struct array, n_segs×1):
%                             .segment_idx, .segment_name,
%                             .coasting_dist_m, .time_penalty_sec, .fuel_saved_kg
%     .n_total_combos  Total combinations evaluated (including no-coast).
%     .seg_names       Cell array of segment names.
%
% ALGORITHM:
%   1. Collect discrete (coast_m, time_s, fuel_kg) options per segment from
%      successful variants.  Prepend a (0, 0, 0) row for "no coast".
%   2. Compute total combinations = prod(n_opts_per_seg).
%   3. Build a (total_combos × n_segs) index matrix using modular arithmetic
%      — fully vectorised, no loops over combinations.
%   4. For each segment column, gather option values by index; accumulate
%      totals with a single vector addition.
%   5. Compute efficiency = fuel / max(time, 1e-9).  Partial sort to find
%      top-n_top rows.
%   6. Reconstruct per-segment allocations for the top-n_top.
%   7. Print table, save XLSX and Pareto-scatter PNG.

%% --- Input parsing ----------------------------------------------------------

p = inputParser;
addParameter(p, 'n_top',      10,                    @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'output_dir', './fuel_save_output',  @ischar);
addParameter(p, 'max_combos', Inf,                   @(x) isnumeric(x) && isscalar(x));
parse(p, varargin{:});

n_top      = round(p.Results.n_top);
output_dir = p.Results.output_dir;
max_combos = p.Results.max_combos;

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

%% --- Step 1: Build per-segment discrete option tables -----------------------

ok_mask = strcmp({variants.status}, 'success');
ok_v    = variants(ok_mask);

if isempty(ok_v)
    warning('smp_doe_fuel_save: no successful variants — cannot run DOE.');
    doe = [];
    return;
end

seg_ids = unique([ok_v.segment_idx]);
n_segs  = numel(seg_ids);

% seg_opts{si} is (n_opts_si × 3): [coast_m, time_s, fuel_kg]
% Row 1 is always (0, 0, 0) = "no coast for this segment"
seg_opts  = cell(n_segs, 1);
seg_names = cell(n_segs, 1);
n_opts    = zeros(n_segs, 1);

for si = 1:n_segs
    sid  = seg_ids(si);
    mask = ([ok_v.segment_idx] == sid);
    sv   = ok_v(mask);

    coast_m = [sv.coasting_point]';
    time_s  = [sv.time_penalty_sec]';
    fuel_kg = [sv.fuel_saved_kg]';

    % Sort by coasting distance ascending (smallest coast first)
    [coast_m, order] = sort(coast_m);
    time_s  = time_s(order);
    fuel_kg = fuel_kg(order);

    % Prepend no-coast option
    opts = [0, 0, 0; coast_m, time_s, fuel_kg];

    seg_opts{si}  = opts;
    seg_names{si} = sv(1).segment_name;
    n_opts(si)    = size(opts, 1);
end

%% --- Step 2: Check feasibility ----------------------------------------------

total_combos = prod(n_opts);
fprintf('[DOE] Segments: %d  |  Options per seg: [%s]  |  Total combinations: %s\n', ...
    n_segs, num2str(n_opts', '%d '), format_large(total_combos));

if total_combos > max_combos
    warning(['smp_doe_fuel_save: %s combinations exceeds max_combos (%s). ' ...
        'Reduce Coasting_Steps in the config or increase max_combos. ' ...
        'Use smp_optimize_fuel_save instead for large grids.'], ...
        format_large(total_combos), format_large(max_combos));
    doe = [];
    return;
end

%% --- Steps 3-5: Chunked enumeration, evaluation, and top-N ranking --------
% Combinations are processed in fixed-size chunks so peak memory is bounded
% regardless of total_combos.  A running top-N pool accumulates the best
% candidates, and a reservoir sample is collected for the scatter plot.

chunk_size = 5e6;     % ~140 MB per chunk at n_segs = 4
n_chunks   = ceil(double(total_combos) / chunk_size);

% Pre-convert seg_opts to single once
seg_opts_s = cellfun(@(x) single(x), seg_opts, 'UniformOutput', false);

% Running top-N pool (global combo index, 0-based uint64)
pool_global = zeros(n_top, 1, 'uint64');
pool_time   = repmat(single(-Inf), n_top, 1);
pool_fuel   = zeros(n_top, 1, 'single');
pool_eff    = repmat(single(-Inf), n_top, 1);
pool_n      = 0;

% Reservoir sample for scatter plot (uniformly spaced across all combos)
scat_max    = 50000;
scat_period = max(1, floor(double(total_combos) / scat_max));
scat_time   = zeros(scat_max, 1, 'single');
scat_fuel   = zeros(scat_max, 1, 'single');
scat_eff    = zeros(scat_max, 1, 'single');
scat_n      = 0;

fprintf('[DOE] Processing %s combinations in %d chunk(s) of %.0fM...\n', ...
    format_large(total_combos), n_chunks, chunk_size / 1e6);

for chunk_i = 1:n_chunks
    i_start = uint64(chunk_i - 1) * uint64(chunk_size);
    i_end   = min(i_start + uint64(chunk_size) - uint64(1), uint64(total_combos - 1));
    n_this  = double(i_end - i_start) + 1;

    % Decode global indices -> per-segment option indices (1-based uint16)
    idx_chunk = zeros(n_this, n_segs, 'uint16');
    remaining = i_start + uint64(0 : n_this - 1)';
    for si = n_segs : -1 : 1
        n_i = uint64(n_opts(si));
        idx_chunk(:, si) = uint16(mod(remaining, n_i)) + 1;
        remaining        = idivide(remaining, n_i, 'floor');
    end
    clear remaining;

    % Accumulate time and fuel for this chunk
    chunk_time = zeros(n_this, 1, 'single');
    chunk_fuel = zeros(n_this, 1, 'single');
    for si = 1:n_segs
        o    = seg_opts_s{si};
        rows = double(idx_chunk(:, si));
        chunk_time = chunk_time + o(rows, 2);
        chunk_fuel = chunk_fuel + o(rows, 3);
    end
    clear idx_chunk;

    % Efficiency; mask pure no-coast rows
    chunk_eff = chunk_fuel ./ max(chunk_time, single(1e-9));
    chunk_eff(chunk_time < single(1e-6)) = single(-Inf);

    % Update running top-N pool
    n_cand = min(n_top, n_this);
    [~, top_local] = maxk(double(chunk_eff), n_cand);
    cand_global = i_start + uint64(top_local(:) - 1);
    cand_time   = chunk_time(top_local);
    cand_fuel   = chunk_fuel(top_local);
    cand_eff    = chunk_eff(top_local);

    if pool_n > 0
        mg = [pool_global(1:pool_n); cand_global];
        mt = [pool_time(1:pool_n);   cand_time];
        mf = [pool_fuel(1:pool_n);   cand_fuel];
        me = [pool_eff(1:pool_n);    cand_eff];
    else
        mg = cand_global; mt = cand_time; mf = cand_fuel; me = cand_eff;
    end
    [~, ord] = sort(double(me), 'descend');
    keep = min(n_top, numel(ord));
    pool_global(1:keep) = mg(ord(1:keep));
    pool_time(1:keep)   = mt(ord(1:keep));
    pool_fuel(1:keep)   = mf(ord(1:keep));
    pool_eff(1:keep)    = me(ord(1:keep));
    pool_n = keep;

    % Reservoir sample (uniformly spaced within each chunk)
    if scat_n < scat_max
        samp_idx = 1 : scat_period : n_this;
        n_add    = min(numel(samp_idx), scat_max - scat_n);
        samp_idx = samp_idx(1:n_add);
        scat_time(scat_n+1 : scat_n+n_add) = chunk_time(samp_idx);
        scat_fuel(scat_n+1 : scat_n+n_add) = chunk_fuel(samp_idx);
        scat_eff(scat_n+1  : scat_n+n_add) = chunk_eff(samp_idx);
        scat_n = scat_n + n_add;
    end

    if mod(chunk_i, max(1, floor(n_chunks / 10))) == 0 || chunk_i == n_chunks
        fprintf('[DOE] Progress: %d/%d (%.0f%%)\n', chunk_i, n_chunks, 100 * chunk_i / n_chunks);
    end
end

fprintf('[DOE] Top-%d selected. Best efficiency: %.4f kg/s\n', pool_n, pool_eff(1));

%% --- Step 6: Reconstruct top-N allocations from global indices -------------

combos = [];
for ri = 1:pool_n
    global_ci = pool_global(ri);

    % Decode per-segment option indices (same modular arithmetic as encoding)
    rem_dec   = global_ci;
    alloc_row = zeros(1, n_segs, 'uint32');
    for si = n_segs : -1 : 1
        n_i = uint64(n_opts(si));
        alloc_row(si) = uint32(mod(rem_dec, n_i)) + 1;
        rem_dec = idivide(rem_dec, n_i, 'floor');
    end

    alloc = [];
    for si = 1:n_segs
        row = double(alloc_row(si));
        opt = seg_opts{si}(row, :);   % [coast_m, time_s, fuel_kg]

        a.segment_idx      = seg_ids(si);
        a.segment_name     = seg_names{si};
        a.coasting_dist_m  = opt(1);
        a.time_penalty_sec = opt(2);
        a.fuel_saved_kg    = opt(3);

        if isempty(alloc)
            alloc = a;
        else
            alloc(end + 1) = a;  %#ok<AGROW>
        end
    end

    c.rank                   = ri;
    c.total_fuel_saved_kg    = double(pool_fuel(ri));
    c.total_time_penalty_sec = double(pool_time(ri));
    c.efficiency_kg_per_s    = double(pool_eff(ri));
    c.allocation             = alloc;

    if isempty(combos)
        combos = c;
    else
        combos(end + 1) = c;  %#ok<AGROW>
    end
end

doe.combos         = combos;
doe.n_total_combos = total_combos;
doe.seg_names      = seg_names;

%% --- Step 7: Print results --------------------------------------------------

print_doe_table(combos, seg_names);

%% --- Step 8: Save outputs --------------------------------------------------

save_doe_xlsx(combos, seg_names, output_dir);
% Pass pre-filtered reservoir sample — no full-array copy needed
scat_mask = scat_time(1:scat_n) > single(1e-4) & scat_fuel(1:scat_n) > single(1e-6);
save_doe_plot(combos, scat_time(scat_mask), scat_fuel(scat_mask), scat_eff(scat_mask), seg_names, output_dir);

fprintf('[DOE] Complete. Output saved to: %s\n\n', output_dir);

end % main function


%% ===========================================================================
%  PRINT
%% ===========================================================================
function print_doe_table(combos, seg_names)
    n_segs = numel(seg_names);

    % Build segment column headers (8 char max)
    seg_hdr = '';
    for si = 1:n_segs
        nm = seg_names{si};
        if numel(nm) > 8; nm = nm(1:8); end
        seg_hdr = [seg_hdr, sprintf('  %8s', nm)];  %#ok<AGROW>
    end

    col_w = 36 + n_segs * 10;
    fprintf('\n');
    fprintf('===========================================\n');
    fprintf('  FULL DOE — TOP %d COMBINATIONS\n', numel(combos));
    fprintf('  Ranked by efficiency: kg fuel saved per second of lap time lost\n');
    fprintf('  Coast distances in metres before brake marker  (0 = no coast)\n');
    fprintf('===========================================\n');
    fprintf('  %4s  %9s  %9s  %10s%s\n', 'Rank', 'Fuel(kg)', 'Time(s)', 'Eff(kg/s)', seg_hdr);
    fprintf('  %s\n', repmat('-', 1, col_w));

    for ri = 1:numel(combos)
        c = combos(ri);
        coast_str = '';
        for si = 1:n_segs
            if si <= numel(c.allocation)
                d = c.allocation(si).coasting_dist_m;
                if d > 0.5
                    coast_str = [coast_str, sprintf('  %8.1f', d)];  %#ok<AGROW>
                else
                    coast_str = [coast_str, sprintf('  %8s', '-')];   %#ok<AGROW>
                end
            end
        end
        fprintf('  %4d  %9.4f  %9.3f  %10.4f%s\n', ...
            ri, c.total_fuel_saved_kg, c.total_time_penalty_sec, ...
            c.efficiency_kg_per_s, coast_str);
    end
    fprintf('  %s\n\n', repmat('-', 1, col_w));
end


%% ===========================================================================
%  XLSX
%% ===========================================================================
function save_doe_xlsx(combos, seg_names, output_dir)
    n  = numel(combos);
    n_segs = numel(seg_names);

    ranks    = (1:n)';
    t_pen    = [combos.total_time_penalty_sec]';
    f_saved  = [combos.total_fuel_saved_kg]';
    effic    = [combos.efficiency_kg_per_s]';

    T = table(ranks, f_saved, t_pen, effic, ...
        'VariableNames', {'Rank', 'Fuel_Saved_kg', 'Time_Penalty_sec', 'Efficiency_kg_per_s'});

    % Append one column per segment with coasting distance
    for si = 1:n_segs
        col_name = matlab.lang.makeValidName(seg_names{si});
        col_data = zeros(n, 1);
        for ri = 1:n
            if si <= numel(combos(ri).allocation)
                col_data(ri) = combos(ri).allocation(si).coasting_dist_m;
            end
        end
        T.(col_name) = col_data;
    end

    out_path = fullfile(output_dir, 'smp_doe_top_combinations.xlsx');
    writetable(T, out_path, 'Sheet', 'DOE_Top_Combinations');
    fprintf('[DOE] XLSX saved: %s\n', out_path);
end


%% ===========================================================================
%  SCATTER PLOT
%% ===========================================================================
function save_doe_plot(combos, scat_time, scat_fuel, scat_eff, seg_names, output_dir)
    fig = figure('Visible', 'off', 'Position', [100 100 1000 580]);
    ax  = axes(fig);
    hold(ax, 'on');

    % Pre-filtered and pre-subsampled reservoir sample from chunked evaluation
    t_all = double(scat_time);
    f_all = double(scat_fuel);
    e_all = double(scat_eff);

    scatter(ax, t_all, f_all, 6, e_all, 'filled', 'MarkerFaceAlpha', 0.3);
    colormap(ax, 'parula');

    % Highlight top-N
    top_colors = lines(numel(combos));
    for ri = 1:numel(combos)
        c = combos(ri);
        scatter(ax, c.total_time_penalty_sec, c.total_fuel_saved_kg, ...
            120, top_colors(ri, :), 'filled', 'MarkerEdgeColor', 'k', ...
            'LineWidth', 1.2, 'DisplayName', sprintf('Rank %d', ri));
        text(ax, c.total_time_penalty_sec, c.total_fuel_saved_kg, ...
            sprintf('  #%d', ri), 'FontSize', 8, 'Color', top_colors(ri, :));
    end

    % Labels, legend, grid — all BEFORE colorbar to avoid listener conflict
    xlabel(ax, 'Total Time Penalty (s)');
    ylabel(ax, 'Total Fuel Saved (kg)');
    title(ax, sprintf('Full DOE — All Combinations (%d segs: %s)', ...
        numel(seg_names), strjoin(seg_names, ', ')), 'FontWeight', 'bold');
    legend(ax, 'Location', 'southeast', 'FontSize', 8);
    grid(ax, 'on');
    box(ax, 'on');

    % Colorbar added last
    cb = colorbar(ax);
    cb.Label.String = 'Efficiency (kg/s)';

    out_path = fullfile(output_dir, 'smp_doe_scatter.png');
    exportgraphics(fig, out_path, 'Resolution', 150);
    close(fig);
    fprintf('[DOE] Scatter plot saved: %s\n', out_path);
end


%% ===========================================================================
%  UTILITIES
%% ===========================================================================
function s = format_large(n)
    if n >= 1e9
        s = sprintf('%.2fB', n / 1e9);
    elseif n >= 1e6
        s = sprintf('%.2fM', n / 1e6);
    elseif n >= 1e3
        s = sprintf('%.1fK', n / 1e3);
    else
        s = sprintf('%d', n);
    end
end
