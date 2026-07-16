function smp_plot_fuel_save_variants(variants, segments, lap_original, output_dir, varargin)
% SMP_PLOT_FUEL_SAVE_VARIANTS  Speed-trace plots per segment + master lap trace
%
% OPTIONAL name-value:
%   fuel_rate      (double) kg/s — used to compute % of qualifying fuel [default: NaN]
%   lap_time       (double) s   — qualifying lap time                   [default: NaN]
%   preceding_lap  (struct) lap struct — extends dist axis into negatives [default: []]

p = inputParser;
addParameter(p, 'fuel_rate',     NaN, @isnumeric);
addParameter(p, 'lap_time',      NaN, @isnumeric);
addParameter(p, 'preceding_lap', [],  @(x) isempty(x)||isstruct(x));
parse(p, varargin{:});
fuel_rate     = p.Results.fuel_rate;
lap_time      = p.Results.lap_time;
preceding_lap = p.Results.preceding_lap;

% Fall back to lap struct field if lap_time not supplied
if isnan(lap_time) && isfield(lap_original, 'lap_time')
    lap_time = lap_original.lap_time;
end

% Total qualifying lap fuel (kg): integrate actual fuel-flow channel (g/s) if
% available; otherwise fall back to fuel_rate * lap_time (constant-rate estimate).
total_qual_fuel = NaN;
ff_ch_name_q    = smp_find_fuel_channel(lap_original);   % '' if not found
if ~isempty(ff_ch_name_q)
    ff_ch_q  = lap_original.channels.(ff_ch_name_q);
    ff_d_q   = ff_ch_q.dist(:);
    ff_kgs_q = max(0, ff_ch_q.data(:) / 1000);          % g/s → kg/s
    % Build time axis from original lap speed
    d_tmp   = lap_original.channels.Distance.dist(:);
    if isempty(d_tmp), d_tmp = lap_original.channels.Distance.data(:); end
    spd_tmp = interp1(lap_original.channels.Ground_Speed.dist(:), ...
                      lap_original.channels.Ground_Speed.data(:), ...
                      d_tmp, 'linear', 'extrap');
    spd_tmp_ms  = max(spd_tmp / 3.6, 0.5);
    time_q      = cumsum([0; diff(d_tmp)] ./ spd_tmp_ms);
    ff_q_at_d   = max(0, interp1(ff_d_q, ff_kgs_q, d_tmp, 'linear', 'extrap'));
    total_qual_fuel = trapz(time_q, ff_q_at_d);
    fprintf('[FUEL] Total lap fuel from channel "%s": %.4f kg\n', ff_ch_name_q, total_qual_fuel);
elseif ~isnan(fuel_rate) && ~isnan(lap_time)
    total_qual_fuel = fuel_rate * lap_time;
    fprintf('[FUEL] Fuel_Flow channel not found — using rate fallback: %.4f kg\n', total_qual_fuel);
end

if ~exist(output_dir, 'dir'), mkdir(output_dir); end

n_seg = length(segments);
if n_seg == 0, warning('No segments to plot.'); return; end

%% ── Master distance axis from original lap (extended with preceding lap) ─────
dist_orig  = lap_original.channels.Distance.dist(:);
if isempty(dist_orig)
    dist_orig = lap_original.channels.Distance.data(:);
end
spd_raw    = lap_original.channels.Ground_Speed.data(:);
dist_spd   = lap_original.channels.Ground_Speed.dist(:);
spd_orig   = interp1(dist_spd, spd_raw, dist_orig, 'linear', 'extrap');  % km/h

% Prepend preceding lap so S01 has an original trace before the finish line
if ~isempty(preceding_lap) && isfield(preceding_lap, 'channels')
    dist_cands = {'Distance','Odometer','Lap_Distance'};
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
    if ~isempty(p_dist_raw)
        p_dist = p_dist_raw - p_dist_raw(end);   % negative offsets
        keep_p = p_dist < 0;
        p_spd  = interp1(preceding_lap.channels.Ground_Speed.dist(:), ...
                         preceding_lap.channels.Ground_Speed.data(:), ...
                         p_dist_raw(keep_p), 'linear', 'extrap');
        dist_orig = [p_dist(keep_p); dist_orig];
        spd_orig  = [p_spd(:);       spd_orig];
    end
end

%% ── Figure 1: Combined speed trace — all segments on one axes ───────────
fig1 = figure('Name', 'Coasting Check — All Segments', ...
              'NumberTitle', 'off', ...
              'Units', 'normalized', 'Position', [0.03 0.05 0.94 0.55]);
ax1 = axes(fig1);
hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

cmap_seg = lines(n_seg);

% Coloured variant lines drawn first (original overlaid last so it stays visible)
for si = 1:n_seg
    seg       = segments(si);
    seg_vars  = variants([variants.segment_idx] == si);
    ok_vars   = seg_vars(strcmp({seg_vars.status}, 'success'));
    fail_vars = seg_vars(strcmp({seg_vars.status}, 'fail'));

    % Print failures to terminal
    for fi = 1:length(fail_vars)
        fv = fail_vars(fi);
        fprintf('[PLOT] Seg %d coast=%.0f m  FAIL: %s\n', ...
                si, fv.coasting_point, fv.details.fail_reason);
    end

    n_ok = length(ok_vars);
    col  = cmap_seg(min(si, size(cmap_seg,1)), :);

    if n_ok > 0
        % Sort: smallest magnitude first (least coasting = closest to original)
        [~, sort_i] = sort([ok_vars.coasting_point], 'descend');
        ok_vars = ok_vars(sort_i);
    end

    first_in_seg = true;
    for vi = 1:n_ok
        v    = ok_vars(vi);
        d_v  = v.distance(:);
        sp_v = v.speed_trace(:);

        % Show full segment: green line → green line
        % The coast dip is visible mid-segment; before & after = original speed
        d_start_plot = seg.distance_start;
        d_end_plot   = seg.distance_end;
        win = d_v >= d_start_plot & d_v <= d_end_plot;
        if ~any(win), continue; end

        % Fade colour dark → light as coasting distance increases
        frac     = 0.3 + 0.7 * (vi / n_ok);
        line_col = 1 - frac * (1 - col);   % blend toward white

        if first_in_seg
            lbl = sprintf('S%02d  %.0f–%.0f m', si, seg.distance_start, seg.distance_end);
            first_in_seg = false;
            plot(ax1, d_v(win), sp_v(win), '-', 'Color', line_col, ...
                 'LineWidth', 1.4, 'DisplayName', lbl);
        else
            plot(ax1, d_v(win), sp_v(win), '-', 'Color', line_col, ...
                 'LineWidth', 1.4, 'HandleVisibility', 'off');
        end
    end

    % Segment boundary: green dashed at throttle-on only
    yl = ylim(ax1);
    plot(ax1, [seg.distance_start seg.distance_start], yl, '--', ...
         'Color', [0.08 0.72 0.08], 'LineWidth', 1.0, 'HandleVisibility', 'off');
end

% Final sector end line (green solid) — matches the draggable END marker
last_seg = segments(end);
yl = ylim(ax1);
plot(ax1, [last_seg.distance_end last_seg.distance_end], yl, '-', ...
     'Color', [0.08 0.72 0.08], 'LineWidth', 2.0, 'HandleVisibility', 'off');

% Clip x-axis to first sector start → last sector end
xlim(ax1, [segments(1).distance_start - 50, last_seg.distance_end + 50]);

% Original full-lap trace drawn last so it sits on top
plot(ax1, dist_orig, spd_orig, 'k-', 'LineWidth', 2.0, 'DisplayName', 'Original');

xlabel(ax1, 'Distance (m)', 'FontSize', 10);
ylabel(ax1, 'Speed (km/h)', 'FontSize', 10);
title(ax1, 'Coasting variants — all segments  (original = black | green dashed = sector start)', ...
      'FontSize', 9);
legend(ax1, 'Location', 'best', 'FontSize', 8);

saveas(fig1, fullfile(output_dir, 'smp_fuel_save_speed_traces.png'));
fprintf('Saved: smp_fuel_save_speed_traces.png\n');

%% ── Figure 2: Fuel vs Time trade-off — surf plot ────────────────────────
% Build a grid: rows = segments, cols = coasting distances
ok_all2   = variants(strcmp({variants.status}, 'success'));
all_cpts2 = sort(unique([ok_all2.coasting_point]), 'ascend');  % e.g. [-75 -68 ... -8]
n_cpts2   = numel(all_cpts2);

% Grids: NaN where a variant doesn't exist for that segment/coasting combo
fuel_grid = NaN(n_seg, n_cpts2);
time_grid = NaN(n_seg, n_cpts2);

for si = 1:n_seg
    seg_vars = variants([variants.segment_idx] == si);
    ok_vars  = seg_vars(strcmp({seg_vars.status}, 'success'));
    for vi = 1:numel(ok_vars)
        ci = find(abs(all_cpts2 - ok_vars(vi).coasting_point) < 0.1, 1);
        if ~isempty(ci)
            fuel_grid(si, ci) = ok_vars(vi).fuel_saved_kg;
            time_grid(si, ci) = ok_vars(vi).time_penalty_sec;
        end
    end
end

% X = coasting distance (m, absolute), Y = segment index
X_surf = repmat(abs(all_cpts2(:)'), n_seg, 1);   % n_seg × n_cpts2
Y_surf = repmat((1:n_seg)', 1, n_cpts2);           % n_seg × n_cpts2

fig2 = figure('Name', 'Fuel–Time Trade-off Surface', ...
              'NumberTitle', 'off', ...
              'Units', 'normalized', 'Position', [0.08 0.08 0.60 0.60]);

% Two subplots: fuel saved surface and time penalty surface
subplot(1, 2, 1);
surf(X_surf, Y_surf, fuel_grid, 'EdgeAlpha', 0.3, 'FaceAlpha', 0.85);
xlabel('Coasting Distance (m)', 'FontSize', 10);
ylabel('Segment',               'FontSize', 10);
zlabel('Fuel Saved (kg)',       'FontSize', 10);
title('Fuel Saved',             'FontSize', 11);
colorbar; colormap(gca, 'parula');
yticks(1:n_seg);
yticklabels(arrayfun(@(s) sprintf('S%02d', s), 1:n_seg, 'UniformOutput', false));
view(45, 30); grid on;

subplot(1, 2, 2);
surf(X_surf, Y_surf, time_grid, 'EdgeAlpha', 0.3, 'FaceAlpha', 0.85);
xlabel('Coasting Distance (m)', 'FontSize', 10);
ylabel('Segment',               'FontSize', 10);
zlabel('Time Penalty (s)',      'FontSize', 10);
title('Time Penalty',           'FontSize', 11);
colorbar; colormap(gca, 'hot');
yticks(1:n_seg);
yticklabels(arrayfun(@(s) sprintf('S%02d', s), 1:n_seg, 'UniformOutput', false));
view(45, 30); grid on;

sgtitle('Fuel vs Time Trade-off by Segment & Coasting Distance', ...
        'FontSize', 12, 'FontWeight', 'bold');

saveas(fig2, fullfile(output_dir, 'smp_fuel_save_tradeoff.png'));
fprintf('Saved: smp_fuel_save_tradeoff.png\n');

%% ── Figure 3: One full figure per segment — all coasting iterations ──────
% Distinct colours per iteration so every line is clearly separable.
% Original lap = thick black. Coast iterations ordered short→long coast.

for si = 1:n_seg
    seg      = segments(si);
    seg_vars = variants([variants.segment_idx] == si);
    ok_vars  = seg_vars(strcmp({seg_vars.status}, 'success'));

    if isempty(ok_vars), continue; end

    % Sort: least coasting first (-20 m), most coasting last (-200 m)
    [~, sort_i] = sort([ok_vars.coasting_point], 'descend');
    ok_vars = ok_vars(sort_i);
    n_ok = length(ok_vars);

    % Colour palette — use distinguishable set (lines() up to 7, then extend)
    if n_ok <= 7
        cpal = lines(n_ok);
    else
        cpal = hsv(n_ok);
    end

    % x-window: from furthest coast start (with margin) to segment end
    % Use actual coasting_start_dist from details so S01 (where brake_marker
    % lies outside [distance_start, distance_end]) is handled correctly.
    all_csd = arrayfun(@(v) v.details.coasting_start_dist, ok_vars);
    d_win_start = min(all_csd) - 40;
    d_win_end   = seg.distance_end;
    % Safety guard: ensure window is valid (e.g. wrap-around segments)
    if d_win_start >= d_win_end
        d_win_start = seg.distance_start;
    end

    fig3 = figure('Name', sprintf('S%02d Speed Traces', si), ...
                  'NumberTitle', 'off', ...
                  'Visible', 'off', ...
                  'Units', 'normalized', 'Position', [0.05 0.08 0.9 0.78]);
    ax3 = axes(fig3);
    hold(ax3, 'on'); grid(ax3, 'on'); box(ax3, 'on');

    % Original lap
    win_mask = dist_orig >= d_win_start & dist_orig <= d_win_end;
    plot(ax3, dist_orig(win_mask), spd_orig(win_mask), ...
         'k-', 'LineWidth', 3, 'DisplayName', 'Original');

    % Coasting variants
    for vi = 1:n_ok
        v   = ok_vars(vi);
        col = cpal(vi, :);

        d_v  = v.distance;
        sp_v = v.speed_trace;  % km/h
        if isempty(d_v), continue; end

        v_mask = d_v >= d_win_start & d_v <= d_win_end;
        if ~any(v_mask), continue; end

        lbl = sprintf('Coast %.0f m  |  %.4f kg  |  +%.3f s', ...
                      v.coasting_point, v.fuel_saved_kg, v.time_penalty_sec);
        plot(ax3, d_v(v_mask), sp_v(v_mask), ...
             '-', 'Color', col, 'LineWidth', 1.8, 'DisplayName', lbl);

        % Vertical tick at coast start
        d_cs = v.details.coasting_start_dist;
        if ~isnan(d_cs)
            yl = ylim(ax3);
            plot(ax3, [d_cs d_cs], [yl(2)-5 yl(2)], ...
                 '-', 'Color', col, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        end
    end

    % Brake marker & throttle-on lines
    yl = ylim(ax3);
    plot(ax3, [seg.brake_marker seg.brake_marker], yl, ...
         'r--', 'LineWidth', 1.5, 'DisplayName', 'Brake marker');
    plot(ax3, [seg.distance_start seg.distance_start], yl, ...
         'g--', 'LineWidth', 1.5, 'DisplayName', 'Throttle on');

    title(ax3, sprintf('Segment %02d — Speed Traces (%.0f–%.0f m)', ...
          si, seg.distance_start, seg.distance_end), 'FontSize', 12, 'FontWeight', 'bold');
    xlabel(ax3, 'Lap Distance (m)', 'FontSize', 11);
    ylabel(ax3, 'Speed (km/h)',     'FontSize', 11);
    xlim(ax3, [d_win_start d_win_end]);
    legend(ax3, 'Location', 'best', 'FontSize', 9);
    ax3.FontSize = 10;

    fname = fullfile(output_dir, sprintf('smp_speed_traces_seg%02d.png', si));
    saveas(fig3, fname);
    fprintf('Saved: smp_speed_traces_seg%02d.png\n', si);
    close(fig3);  % suppress — saved to disk, no need to keep on screen
end

fprintf('Plots saved to: %s\n', output_dir);

%% ── Figure 4: Master lap speed trace — all segments combined ────────────
% For each unique coasting distance, build a combined lap:
%   - original speed everywhere
%   - each enabled segment replaced by its coasted version at that distance
% Annotate with total fuel saved (% of qualifying) and total time penalty.

% Collect all unique coasting points that have at least one success
ok_all        = variants(strcmp({variants.status}, 'success'));
if isempty(ok_all)
    fprintf('No successful variants — skipping master trace.\n');
    return
end
all_cpts      = unique([ok_all.coasting_point]);
all_cpts      = sort(all_cpts, 'descend');   % -20 first, -200 last
n_cpts        = length(all_cpts);

if n_cpts > 1
    cpal_master = lines(n_cpts);
else
    cpal_master = [0.2 0.5 0.9];
end

fig4 = figure('Name', 'Master Lap — All Segments Coasting', ...
              'NumberTitle', 'off', ...
              'Units', 'normalized', 'Position', [0.03 0.05 0.94 0.78]);
ax4  = axes(fig4);
hold(ax4, 'on'); grid(ax4, 'on'); box(ax4, 'on');

% Plot original lap
plot(ax4, dist_orig, spd_orig, 'k-', 'LineWidth', 3, 'DisplayName', 'Original lap');

for ci = 1:n_cpts
    cpt = all_cpts(ci);
    col = cpal_master(ci, :);

    % Build combined speed trace: start from original
    spd_combined = spd_orig;   % km/h on dist_orig axis

    total_fuel_saved = 0;
    total_time_loss  = 0;

    for si = 1:n_seg
        seg      = segments(si);
        seg_vars = variants([variants.segment_idx] == si);

        % Find variant at this coasting point
        match = seg_vars(strcmp({seg_vars.status}, 'success') & ...
                         abs([seg_vars.coasting_point] - cpt) < 0.1);
        if isempty(match), continue; end
        v = match(1);

        % Replace speed in the coasted zone
        d_v  = v.distance;
        sp_v = v.speed_trace;   % km/h
        if isempty(d_v), continue; end

        % Map coasted trace onto dist_orig grid
        zone_mask = dist_orig >= v.details.coasting_start_dist & ...
                    dist_orig <= v.details.coasting_end_dist;
        if any(zone_mask)
            spd_combined(zone_mask) = interp1(d_v, sp_v, dist_orig(zone_mask), ...
                                              'linear', 'extrap');
        end

        total_fuel_saved = total_fuel_saved + v.fuel_saved_kg;
        total_time_loss  = total_time_loss  + v.time_penalty_sec;
    end

    % Build label
    if ~isnan(total_qual_fuel) && total_qual_fuel > 0
        fuel_pct = total_fuel_saved / total_qual_fuel * 100;
        lbl = sprintf('Coast %.0f m  |  %.2f%% fuel  |  +%.3f s', ...
                      cpt, fuel_pct, total_time_loss);
    else
        lbl = sprintf('Coast %.0f m  |  %.4f kg  |  +%.3f s', ...
                      cpt, total_fuel_saved, total_time_loss);
    end

    plot(ax4, dist_orig, spd_combined, '-', 'Color', col, ...
         'LineWidth', 1.6, 'DisplayName', lbl);
end

% Mark segment start/end regions as shaded bands
yl = ylim(ax4);
for si = 1:n_seg
    seg = segments(si);
    x_patch = [seg.distance_start seg.distance_end seg.distance_end seg.distance_start];
    y_patch = [yl(1) yl(1) yl(2) yl(2)];
    patch(ax4, x_patch, y_patch, [0.9 0.9 0.9], ...
          'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    text(ax4, seg.distance_start + 3, yl(2) * 0.97, sprintf('S%02d', si), ...
         'FontSize', 7.5, 'Color', [0.4 0.4 0.4], 'Clipping', 'on');
end 

title(ax4, 'Master Lap Speed Trace — Combined Coasting Across All Segments', ...
      'FontSize', 12, 'FontWeight', 'bold');
segOne = segments(1);
segEnd = segments(end);
xlim([segOne.distance_start segEnd.distance_end])
xlabel(ax4, 'Lap Distance (m)', 'FontSize', 11);
ylabel(ax4, 'Speed (km/h)',     'FontSize', 11);
legend(ax4, 'Location', 'best', 'FontSize', 9);
ax4.FontSize = 10;

if ~isnan(total_qual_fuel)
    yl4 = ylim(ax4);
    text(ax4, ax4.XLim(1), yl4(1) - 0.04*diff(yl4), ...
         sprintf('Qualifying fuel est. %.3f kg  (%.1f s lap @ %.4f kg/s)', ...
                 total_qual_fuel, lap_time, fuel_rate), ...
         'FontSize', 8, 'Color', [0.4 0.4 0.4], 'Clipping', 'off');
end

saveas(fig4, fullfile(output_dir, 'smp_master_speed_trace.png'));
fprintf('Saved: smp_master_speed_trace.png\n');

fprintf('Plots saved to: %s\n', output_dir);

%% ── Figure 5: Lap-time summary table ─────────────────────────────────────
% Two sheets in Excel; one uitable shown in MATLAB:
%   Sheet "Summary"  — one row per coasting step (all segments combined)
%   Sheet "Detailed" — one row per segment × coasting step

ok_all2   = variants(strcmp({variants.status}, 'success'));
if isempty(ok_all2)
    fprintf('No successful variants — skipping lap-time table.\n');
    return
end

all_cpts2 = unique([ok_all2.coasting_point]);
all_cpts2 = sort(all_cpts2, 'descend');   % smallest coast first
n_cpts2   = length(all_cpts2);

%% Build summary rows (one per coasting step, all segments combined) -------
sum_rows = cell(n_cpts2, 0);
sum_coast  = zeros(n_cpts2, 1);
sum_dt     = zeros(n_cpts2, 1);
sum_lapT   = zeros(n_cpts2, 1);
sum_fuelKg = zeros(n_cpts2, 1);
sum_fuelPct= nan(n_cpts2, 1);

for ci = 1:n_cpts2
    cpt = all_cpts2(ci);
    tf  = 0;
    fs  = 0;
    for si = 1:n_seg
        seg_vars = variants([variants.segment_idx] == si);
        match = seg_vars(strcmp({seg_vars.status}, 'success') & ...
                         abs([seg_vars.coasting_point] - cpt) < 0.1);
        if isempty(match), continue; end
        tf = tf + match(1).time_penalty_sec;
        fs = fs + match(1).fuel_saved_kg;
    end
    sum_coast(ci)  = abs(cpt);   % positive = metres before peak speed
    sum_dt(ci)     = tf;
    sum_lapT(ci)   = lap_time + tf;
    sum_fuelKg(ci) = fs;
    if ~isnan(total_qual_fuel) && total_qual_fuel > 0
        sum_fuelPct(ci) = fs / total_qual_fuel * 100;
    end
end

%% Build detailed rows (one per segment × coasting step) ------------------
det_rows   = {};
det_seg    = [];
det_coast  = [];
det_dt     = [];
det_lapT   = [];
det_fuelKg = [];
det_fuelPct= [];

for si = 1:n_seg
    for ci = 1:n_cpts2
        cpt = all_cpts2(ci);
        seg_vars = variants([variants.segment_idx] == si);
        match = seg_vars(strcmp({seg_vars.status}, 'success') & ...
                         abs([seg_vars.coasting_point] - cpt) < 0.1);
        if isempty(match), continue; end
        v = match(1);
        fp = NaN;
        if ~isnan(total_qual_fuel) && total_qual_fuel > 0
            fp = v.fuel_saved_kg / total_qual_fuel * 100;
        end
        det_seg(end+1,1)    = si;
        det_coast(end+1,1)  = abs(cpt);
        det_dt(end+1,1)     = v.time_penalty_sec;
        det_lapT(end+1,1)   = lap_time + v.time_penalty_sec;
        det_fuelKg(end+1,1) = v.fuel_saved_kg;
        det_fuelPct(end+1,1)= fp;
    end
end

%% MATLAB figure with uitable (summary) -----------------------------------
has_pct = ~all(isnan(sum_fuelPct));
sum_eff = sum_fuelKg ./ max(sum_dt, 1e-6);   % Efficiency: fuel saved per second of penalty

if isnan(lap_time)
    fprintf('[Fig 5] lap_time not available — skipping lap time table.\n');
else

if has_pct
    col_names = {'Coast (m)', 'Time Penalty (s)', 'Est. Lap Time (s)', ...
                 'Fuel Saved (kg)', 'Fuel Saved (%)', 'Efficiency (kg/s)'};
    tbl_data  = num2cell(round([sum_coast, sum_dt, sum_lapT, sum_fuelKg, sum_fuelPct, sum_eff], 4));
else
    col_names = {'Coast (m)', 'Time Penalty (s)', 'Est. Lap Time (s)', ...
                 'Fuel Saved (kg)', 'Efficiency (kg/s)'};
    tbl_data  = num2cell(round([sum_coast, sum_dt, sum_lapT, sum_fuelKg, sum_eff], 4));
end

fig5 = figure('Name', 'Lap Time Summary Table', ...
              'NumberTitle', 'off', ...
              'Units', 'normalized', 'Position', [0.1 0.15 0.8 0.65]);

% Header annotation
annotation(fig5, 'textbox', [0 0.92 1 0.08], ...
    'String', sprintf('Lap Time Summary — Original: %.4f s | %d segments coasted  (Efficiency = fuel saved / time penalty)', ...
                      lap_time, n_seg), ...
    'FontSize', 11, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'EdgeColor', 'none');

% uitable
uit = uitable(fig5, ...
    'Data',               tbl_data, ...
    'ColumnName',         col_names, ...
    'RowName',            arrayfun(@(i) sprintf('Step %d', i), (1:n_cpts2)', 'UniformOutput', false), ...
    'Units',              'normalized', ...
    'Position',           [0.02 0.05 0.96 0.84], ...
    'FontSize',           11, ...
    'ColumnWidth',        repmat({160}, 1, length(col_names)));

% Highlight row with best efficiency (most fuel per second of penalty)
[~, best_eff_row] = max(sum_eff);
row_colors = repmat([1 1 1], n_cpts2, 1);
if ~isempty(best_eff_row)
    row_colors(best_eff_row, :) = [0.82 0.96 0.82];   % green = most efficient
end
uit.BackgroundColor = row_colors;

fprintf('Lap time table displayed in Figure 5.\n');

end  % if ~isnan(lap_time)

%% Excel export ------------------------------------------------------------
xlsx_path = fullfile(output_dir, 'smp_lap_time_summary.xlsx');

% Summary sheet
if has_pct
    T_sum = table(sum_coast, sum_dt, sum_lapT, sum_fuelKg, sum_fuelPct, sum_eff, ...
        'VariableNames', {'CoastBeforePeak_m', 'TimePenalty_s', ...
                          'EstLapTime_s', 'FuelSaved_kg', 'FuelSaved_pct', 'Efficiency_kg_per_s'});
else
    T_sum = table(sum_coast, sum_dt, sum_lapT, sum_fuelKg, sum_eff, ...
        'VariableNames', {'CoastBeforePeak_m', 'TimePenalty_s', ...
                          'EstLapTime_s', 'FuelSaved_kg', 'Efficiency_kg_per_s'});
end
writetable(T_sum, xlsx_path, 'Sheet', 'Summary');

% Detailed sheet
if has_pct
    T_det = table(det_seg, det_coast, det_dt, det_lapT, det_fuelKg, det_fuelPct, ...
        'VariableNames', {'Segment', 'CoastBeforePeak_m', 'TimePenalty_s', ...
                          'EstLapTime_s', 'FuelSaved_kg', 'FuelSaved_pct'});
else
    T_det = table(det_seg, det_coast, det_dt, det_lapT, det_fuelKg, ...
        'VariableNames', {'Segment', 'CoastBeforePeak_m', 'TimePenalty_s', ...
                          'EstLapTime_s', 'FuelSaved_kg'});
end
writetable(T_det, xlsx_path, 'Sheet', 'Detailed');

fprintf('Saved: smp_lap_time_summary.xlsx\n');

%% ── Figure 6: Cumulative fuel consumed vs distance ───────────────────────
% Original lap: fuel accumulates at fuel_rate everywhere.
% Coasted lap:  fuel accumulation is zero in [coast_start, d_peak_speed]
%               for each segment (throttle-off / coasting zone).
%               After d_peak_speed the car is already braking — no change.
%
% One line per unique coasting step (all segments combined), same colour
% scheme as Figure 4.

if isnan(fuel_rate)
    fprintf('[Fig 6] fuel_rate not provided — skipping cumulative fuel plot.\n');
    return
end

%% Build original cumulative fuel trace on dist_orig axis
dd_orig   = [0; diff(dist_orig)];
v_ms_orig = max(spd_orig / 3.6, 0.5);        % km/h → m/s, guard div/0
dt_orig_v = dd_orig ./ v_ms_orig;             % time step at each sample

% Use fuel-flow channel if available, otherwise constant-rate fallback
ff_ch_name6 = smp_find_fuel_channel(lap_original);
if ~isempty(ff_ch_name6)
    ff_ch6   = lap_original.channels.(ff_ch_name6);
    ff_kgs6  = max(0, ff_ch6.data(:) / 1000);    % g/s → kg/s
    % Build time axis on timed-lap distance, interpolate fuel rate onto dist_orig
    d_lap6   = lap_original.channels.Distance.dist(:);
    if isempty(d_lap6), d_lap6 = lap_original.channels.Distance.data(:); end
    spd_lap6 = interp1(lap_original.channels.Ground_Speed.dist(:), ...
                       lap_original.channels.Ground_Speed.data(:), d_lap6, 'linear','extrap');
    dt_lap6  = [0; diff(d_lap6)] ./ max(spd_lap6/3.6, 0.5);
    t_lap6   = cumsum(dt_lap6);
    ff_at_dorig = max(0, interp1(ff_ch6.dist(:), ff_kgs6, dist_orig, 'linear', 0));
    % Zero samples before S01 — cumsum then starts from 0 at S01 naturally
    d_seg1_start = segments(1).distance_start;
    idx_seg1 = find(dist_orig >= d_seg1_start, 1, 'first');
    if ~isempty(idx_seg1), ff_at_dorig(1:idx_seg1-1) = 0; end
    cum_fuel_orig = cumsum(ff_at_dorig .* dt_orig_v);
else
    d_seg1_start = segments(1).distance_start;
    idx_seg1 = find(dist_orig >= d_seg1_start, 1, 'first');
    dt_orig_seg = dt_orig_v;
    if ~isempty(idx_seg1), dt_orig_seg(1:idx_seg1-1) = 0; end
    cum_fuel_orig = fuel_rate * cumsum(dt_orig_seg);
end

%% One trace per coasting step (all segments combined)
ok_all3   = variants(strcmp({variants.status}, 'success'));
if isempty(ok_all3)
    fprintf('[Fig 6] No successful variants — skipping cumulative fuel plot.\n');
    return
end

all_cpts3 = unique([ok_all3.coasting_point]);
all_cpts3 = sort(all_cpts3, 'descend');   % smallest coast first
n_cpts3   = length(all_cpts3);

if n_cpts3 > 1
    cpal6 = lines(n_cpts3);
else
    cpal6 = [0.2 0.5 0.9];
end

fig6 = figure('Name', 'Cumulative Fuel vs Distance', ...
              'NumberTitle', 'off', ...
              'Units', 'normalized', 'Position', [0.03 0.05 0.94 0.55]);
ax6 = axes(fig6);
hold(ax6, 'on'); grid(ax6, 'on'); box(ax6, 'on');

% Original trace first (black, thick)
plot(ax6, dist_orig + segOne.distance_start, cum_fuel_orig, 'k-', 'LineWidth', 2.5, 'DisplayName', 'Original lap');

for ci = 1:n_cpts3
    cpt = all_cpts3(ci);
    col = cpal6(ci, :);

    % Start from actual fuel-flow channel on dist_orig axis;
    % replace coast zone [coast_start, peak_speed] with idle rate only.
    if ~isempty(ff_ch_name6)
        fuel_flow_mask = ff_at_dorig;   % kg/s from channel (pre-S01 already 0)
    else
        fuel_flow_mask = ones(size(dist_orig)) * fuel_rate;
        if ~isempty(idx_seg1), fuel_flow_mask(1:idx_seg1-1) = 0; end
    end

    total_fuel_saved_ci = 0;
    for si = 1:n_seg
        seg_vars = variants([variants.segment_idx] == si);
        match = seg_vars(strcmp({seg_vars.status}, 'success') & ...
                         abs([seg_vars.coasting_point] - cpt) < 0.1);
        if isempty(match), continue; end
        v = match(1);

        d_cs   = v.details.coasting_start_dist;
        d_peak = v.details.peak_speed_dist;

        % In coast zone driver lifts — engine burns idle fuel only
        coast_zone = dist_orig >= d_cs & dist_orig < d_peak;
        fuel_flow_mask(coast_zone) = fuel_rate;   % idle rate, not zero

        total_fuel_saved_ci = total_fuel_saved_ci + v.fuel_saved_kg;
    end

    % Recompute time on the modified speed trace
    % Use original speed outside coast zones; coasting speed inside
    spd_combined_ms = spd_orig / 3.6;
    for si = 1:n_seg
        seg_vars = variants([variants.segment_idx] == si);
        match = seg_vars(strcmp({seg_vars.status}, 'success') & ...
                         abs([seg_vars.coasting_point] - cpt) < 0.1);
        if isempty(match), continue; end
        v = match(1);

        d_v  = v.distance(:);
        sp_v = v.speed_trace(:) / 3.6;   % km/h → m/s
        if isempty(d_v), continue; end

        zone = dist_orig >= v.details.coasting_start_dist & ...
               dist_orig <  v.details.coasting_end_dist;
        if any(zone)
            spd_combined_ms(zone) = interp1(d_v, sp_v, dist_orig(zone), 'linear', 'extrap');
        end
    end

    dd6      = [0; diff(dist_orig)];
    dt6      = dd6 ./ max(spd_combined_ms, 0.5);
    cum_fuel = cumsum(fuel_flow_mask .* dt6);  % starts from 0 at S01 naturally

    % Build label
    if ~isnan(total_qual_fuel) && total_qual_fuel > 0
        fuel_pct6 = total_fuel_saved_ci / total_qual_fuel * 100;
        lbl6 = sprintf('Coast %.0f m  |  −%.4f kg  (%.2f%%)', ...
                       abs(cpt), total_fuel_saved_ci, fuel_pct6);
    else
        lbl6 = sprintf('Coast %.0f m  |  −%.4f kg', abs(cpt), total_fuel_saved_ci);
    end

    plot(ax6, dist_orig + segOne.distance_start, cum_fuel, '-', 'Color', col, ...
         'LineWidth', 1.5, 'DisplayName', lbl6);
end

% Shade segment zones (same as Fig 4)
yl6 = ylim(ax6);
for si = 1:n_seg
    seg = segments(si);
    x_p = [seg.distance_start seg.distance_end seg.distance_end seg.distance_start];
    y_p = [yl6(1) yl6(1) yl6(2) yl6(2)];
    patch(ax6, x_p, y_p, [0.9 0.9 0.9], ...
          'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    text(ax6, seg.distance_start + 3, yl6(2) * 0.97, sprintf('S%02d', si), ...
         'FontSize', 7.5, 'Color', [0.4 0.4 0.4], 'Clipping', 'on');
end

xlabel(ax6, 'Lap Distance (m)', 'FontSize', 11);
ylabel(ax6, 'Cumulative Fuel Consumed (kg)', 'FontSize', 11);
segOne = segments(1);
segEnd = segments(end);
xlim([segOne.distance_start segEnd.distance_end])
title(ax6, 'Cumulative Fuel vs Distance — Original vs Coasting Variants', ...
      'FontSize', 11, 'FontWeight', 'bold');
legend(ax6, 'Location', 'best', 'FontSize', 9);
ax6.FontSize = 10;

if ~isnan(total_qual_fuel)
    yl6b = ylim(ax6);
    text(ax6, ax6.XLim(1), yl6b(1) - 0.04*diff(yl6b), ...
         sprintf('Qualifying fuel est. %.3f kg  (%.1f s @ %.4f kg/s)', ...
                 total_qual_fuel, lap_time, fuel_rate), ...
         'FontSize', 8, 'Color', [0.4 0.4 0.4], 'Clipping', 'off');
end

saveas(fig6, fullfile(output_dir, 'smp_cumulative_fuel.png'));
fprintf('Saved: smp_cumulative_fuel.png\n');

end
