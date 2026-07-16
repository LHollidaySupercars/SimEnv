%% alignTrack.m
% Align two fastest laps using damper-based alignment.
% No distance_interp dependency — builds distance axis directly from
% Ground_Speed integration on laps_best{1,i}.channels.
%
% Two alignment methods (set ALIGN_METHOD):
%   'peaks' — finds the most prominent damper peak in the window per car,
%             offset = difference in peak positions. Robust to shape
%             differences between cars. Best for a single sharp feature
%             (kerb, heavy braking zone).
%   'xcorr' — cross-correlates the full window shape between cars.
%             Best when both cars have similar damper response profiles.
%
% Produces 2 figures:
%   Figure 1 — Before alignment
%   Figure 2 — After alignment (offset applied to x-axis)

clear; clc; close all;

%% =========================================================
%  CONFIG
%% =========================================================

LD_FILES = {'E:\02_AGP - Copy\_Team Data\01_T8R\20260305-243060003.ld', ...
            'E:\02_AGP - Copy\_Team Data\02_TFR\20260305-156850003_1.ld' ...
};

LABELS = {'Ford', 'Chev'};

% Speed channel name (km/h) — used to integrate distance
SPEED_CH = 'Ground_Speed';

% Damper channel used for alignment
DAMPER_CH = 'C1_Damper_Pos_FL';

% Alignment method: 'peaks' or 'xcorr'
ALIGN_METHOD = 'peaks';

% Distance window [m] containing a clear, repeatable damper feature
% For 'peaks': zoom in on a single sharp event (kerb / heavy braking)
% For 'xcorr': can be wider — matches the whole shape
ALIGN_WINDOW = [4740, 4840];

% --- 'peaks' options ---
% Minimum peak prominence (in damper units) — filters out noise
PEAK_MIN_PROMINENCE = 2;
% Minimum distance between peaks (m) — prevents finding two peaks of the same event
PEAK_MIN_SEP_M = 10;

% Maximum allowable alignment offset (metres) — sanity cap
MAX_OFFSET_M = 60;

% Lap time filter
MIN_LAP_S = 85;
MAX_LAP_S = 115;

% Channels to plot (one subplot each)
PLOT_CHANNELS = { ...
    'C1_Damper_Pos_FL', ...
    'Brake_Pressure_FL', ...
};

% Distance grid resolution (m)
DIST_RES = 1;

% Colours: Ford Blue / Toyota Red / Chev Yellow
COLOURS = {[0.12 0.31 0.64], [0.84 0.13 0.13], [0.96 0.75 0.05]};

%% =========================================================
%  STEP 1: Load .ld files and find fastest lap
%% =========================================================

n_cars = numel(LD_FILES);
assert(n_cars >= 2 && n_cars <= 3, 'Provide 2 or 3 .ld files');

fprintf('Loading %d files...\n', n_cars);
laps_best = cell(1, n_cars);

for i = 1:n_cars
    fprintf('  [%d] %s\n', i, LD_FILES{i});
    channels = motec_ld_reader(LD_FILES{i});

    slice_opts.min_lap_time = MIN_LAP_S;
    slice_opts.max_lap_time = MAX_LAP_S;
    laps_raw = lap_slicer(channels, slice_opts);

    if isempty(laps_raw)
        error('No valid laps in file %d (%.0f-%.0fs filter)', i, MIN_LAP_S, MAX_LAP_S);
    end

    lap_times = [laps_raw.lap_time];
    [~, best] = min(lap_times);
    fprintf('    Fastest lap: %d  (%.3fs)\n', laps_raw(best).lap_number, lap_times(best));
    laps_best{i} = laps_raw(best);
end

%% =========================================================
%  STEP 2: Build distance axis from Ground_Speed integration
%% =========================================================

fprintf('\nBuilding distance axes from "%s"...\n', SPEED_CH);

spd_time = cell(1, n_cars);
dist_raw = cell(1, n_cars);

for i = 1:n_cars
    ch        = laps_best{i}.channels;
    spd_field = find_field(ch, SPEED_CH);
    if isempty(spd_field)
        fnames = fieldnames(ch);
        error('Speed channel "%s" not found in car %d.\nAvailable: %s', ...
              SPEED_CH, i, strjoin(fnames(contains(lower(fnames),'speed'))', ', '));
    end
    t           = ch.(spd_field).time;
    spd_ms      = max(ch.(spd_field).data / 3.6, 0);
    d           = cumtrapz(t, spd_ms);
    spd_time{i} = t;
    dist_raw{i} = d;
    fprintf('  Car %d: %.0fm total  (%d samples at %.0fHz)\n', ...
        i, d(end), numel(d), ch.(spd_field).sample_rate);
end

%% =========================================================
%  STEP 3: Build common 1m distance grid and resample damper
%% =========================================================

common_len = min(cellfun(@(d) d(end), dist_raw));
dist_vec   = (0 : DIST_RES : common_len)';
n_pts      = numel(dist_vec);

fprintf('\nCommon grid: 0 to %.0fm (%d points at %gm)\n', common_len, n_pts, DIST_RES);

damp_on_dist = cell(1, n_cars);

for i = 1:n_cars
    ch         = laps_best{i}.channels;
    damp_field = find_field(ch, DAMPER_CH);
    if isempty(damp_field)
        fnames = fieldnames(ch);
        error('Damper channel "%s" not found in car %d.\nAvailable channels:\n  %s', ...
              DAMPER_CH, i, strjoin(fnames, '\n  '));
    end

    damp_t    = ch.(damp_field).time;
    damp_vals = ch.(damp_field).data;

    d_at_damp = interp1(spd_time{i}, dist_raw{i}, damp_t, 'linear', 'extrap');

    mono      = [true; diff(d_at_damp) > 0];
    d_at_damp = d_at_damp(mono);
    damp_vals = damp_vals(mono);

    dq = min(max(dist_vec, d_at_damp(1)), d_at_damp(end));
    damp_on_dist{i} = interp1(d_at_damp, damp_vals, dq, 'linear');
end

%% =========================================================
%  STEP 4: Compute alignment offset
%% =========================================================

win_mask = dist_vec >= ALIGN_WINDOW(1) & dist_vec <= ALIGN_WINDOW(2);
n_win    = sum(win_mask);
win_dist = dist_vec(win_mask);

if n_win < 10
    error('Alignment window [%.0f, %.0f]m has only %d samples — widen it.', ...
          ALIGN_WINDOW(1), ALIGN_WINDOW(2), n_win);
end

offsets_m    = zeros(1, n_cars);
peak_dists   = zeros(1, n_cars);   % only used for 'peaks' method

fprintf('\nAlignment method: %s\n', upper(ALIGN_METHOD));
fprintf('Window: [%.0f, %.0f]m (%d pts)  Channel: %s\n', ...
        ALIGN_WINDOW(1), ALIGN_WINDOW(2), n_win, DAMPER_CH);

switch lower(ALIGN_METHOD)

    % ----------------------------------------------------------
    case 'peaks'
    % Find the most prominent peak within the window for each car.
    % Offset = reference peak distance minus car N peak distance.
    % ----------------------------------------------------------
        min_sep_samples = max(1, round(PEAK_MIN_SEP_M / DIST_RES));

        for i = 1:n_cars
            sig = damp_on_dist{i}(win_mask);

            [locs, prom] = local_peaks(sig, min_sep_samples, PEAK_MIN_PROMINENCE);

            if isempty(locs)
                % Fallback: just take the global max in the window
                [~, locs] = max(sig);
                prom      = 0;
                warning('Car %d (%s): no peak met prominence threshold — using global max.', ...
                        i, LABELS{i});
            end

            % Use the most prominent peak
            [~, best_pk]  = max(prom);
            peak_d        = win_dist(locs(best_pk));
            peak_dists(i) = peak_d;

            fprintf('  %s: peak at %.1fm  (prominence=%.2f)\n', ...
                    LABELS{i}, peak_d, prom(best_pk));
        end

        % Offset each car relative to car 1
        for i = 2:n_cars
            offset_m = peak_dists(1) - peak_dists(i);

            if abs(offset_m) > MAX_OFFSET_M
                warning('Car %d offset %.1fm exceeds cap %.0fm — capping.', ...
                        i, offset_m, MAX_OFFSET_M);
                offset_m = sign(offset_m) * MAX_OFFSET_M;
            end

            offsets_m(i) = offset_m;
            fprintf('  %s vs %s: peak diff = %+.1fm\n', LABELS{i}, LABELS{1}, offset_m);
        end

    % ----------------------------------------------------------
    case 'xcorr'
    % Slide car N signal across car 1 signal, find best-match shift.
    % ----------------------------------------------------------
        ref_sig = damp_on_dist{1}(win_mask);
        ref_sig = ref_sig - mean(ref_sig, 'omitnan');

        for i = 2:n_cars
            sig = damp_on_dist{i}(win_mask);
            sig = sig - mean(sig, 'omitnan');

            [xc, lags]    = xcorr(ref_sig, sig);
            [~, peak_idx] = max(xc);
            lag_samples   = lags(peak_idx);
            offset_m      = lag_samples * DIST_RES;

            if abs(offset_m) > MAX_OFFSET_M
                warning('Car %d offset %.1fm exceeds cap %.0fm — capping.', ...
                        i, offset_m, MAX_OFFSET_M);
                offset_m = sign(offset_m) * MAX_OFFSET_M;
            end

            offsets_m(i) = offset_m;
            fprintf('  %s vs %s: lag=%d samples -> offset=%+.1fm\n', ...
                    LABELS{i}, LABELS{1}, lag_samples, offset_m);
        end

    otherwise
        error('Unknown ALIGN_METHOD "%s". Use ''peaks'' or ''xcorr''.', ALIGN_METHOD);
end

%% =========================================================
%  STEP 5: Resample all plot channels onto distance grid
%% =========================================================

n_plots      = numel(PLOT_CHANNELS);
chan_on_dist = cell(n_cars, n_plots);

for i = 1:n_cars
    ch = laps_best{i}.channels;
    for p = 1:n_plots
        fn = find_field(ch, PLOT_CHANNELS{p});
        if isempty(fn)
            warning('Channel "%s" not found in car %d.', PLOT_CHANNELS{p}, i);
            chan_on_dist{i,p} = NaN(n_pts, 1);
            continue;
        end
        ch_t    = ch.(fn).time;
        ch_vals = ch.(fn).data;

        d_at_ch = interp1(spd_time{i}, dist_raw{i}, ch_t, 'linear', 'extrap');
        mono    = [true; diff(d_at_ch) > 0];
        d_at_ch = d_at_ch(mono);
        ch_vals = ch_vals(mono);

        dq = min(max(dist_vec, d_at_ch(1)), d_at_ch(end));
        chan_on_dist{i,p} = interp1(d_at_ch, ch_vals, dq, 'linear');
    end
end

%% =========================================================
%  STEP 6: Figure 1 — Before alignment
%          Figure 2 — After alignment
%% =========================================================

fig_h = max(300, 200 * n_plots + 100);

for fig_idx = 1:2
    fig = figure('Color', 'white', ...
                 'Position', [40 + (fig_idx-1)*60, 60, 1300, fig_h]);

    if fig_idx == 1
        ttl = sprintf('Before Alignment  [method: %s]', upper(ALIGN_METHOD));
    else
        offset_str = strjoin(arrayfun(@(i) sprintf('%s: %+.1fm', LABELS{i}, offsets_m(i)), ...
                             2:n_cars, 'UniformOutput', false), '   ');
        ttl = sprintf('After Alignment (%s) — %s', upper(ALIGN_METHOD), offset_str);
    end

    for p = 1:n_plots
        ax = subplot(n_plots, 1, p);
        hold(ax, 'on');
        box(ax,  'on');
        grid(ax, 'on');
        set(ax, 'FontSize', 10, 'GridAlpha', 0.25, 'GridLineStyle', '--', ...
                'Color', [0.97 0.97 0.97]);

        for i = 1:n_cars
            dv  = dist_vec;
            sig = chan_on_dist{i, p};
            col = COLOURS{i};

            if fig_idx == 2
                dv = dv + offsets_m(i);
            end

            plot(ax, dv, sig, 'Color', col, 'LineWidth', 1.3, 'DisplayName', LABELS{i});
        end

        % Mark alignment window on the damper subplot
        pch_san = regexprep(PLOT_CHANNELS{p}, '[^a-zA-Z0-9]', '_');
        dch_san = regexprep(DAMPER_CH,        '[^a-zA-Z0-9]', '_');
        if strcmpi(pch_san, dch_san)
            xline(ax, ALIGN_WINDOW(1), '--k', 'LineWidth', 0.9, 'HandleVisibility', 'off');
            xline(ax, ALIGN_WINDOW(2), '--k', 'LineWidth', 0.9, 'HandleVisibility', 'off');

            % For 'peaks': mark detected peak positions
            if strcmpi(ALIGN_METHOD, 'peaks')
                for i = 1:n_cars
                    pk_x = peak_dists(i);
                    if fig_idx == 2
                        pk_x = pk_x + offsets_m(i);
                    end
                    xline(ax, pk_x, '-', 'LineWidth', 1.2, ...
                          'Color', COLOURS{i}, 'HandleVisibility', 'off');
                end
            end
        end

        ylabel(ax, strrep(PLOT_CHANNELS{p}, '_', ' '), ...
               'Interpreter', 'none', 'FontSize', 9);

        if p == 1
            legend(ax, 'Location', 'best', 'Box', 'off', 'FontSize', 9);
        end
        if p == n_plots
            xlabel(ax, 'Distance (m)', 'FontSize', 10);
        end
    end

    sgtitle(fig, ttl, 'FontSize', 11, 'FontWeight', 'bold');
end

fprintf('\nDone. Offsets:\n');
for i = 1:n_cars
    fprintf('  %s: %+.1fm\n', LABELS{i}, offsets_m(i));
end

%% =========================================================
%  LOCAL HELPER
%% =========================================================
function field = find_field(ch_struct, name)
% Case-insensitive lookup, also handles spaces -> underscores
    san    = regexprep(name, '[^a-zA-Z0-9_]', '_');
    san    = regexprep(san, '_+', '_');
    fnames = fieldnames(ch_struct);
    field  = '';
    for i  = 1:numel(fnames)
        if strcmpi(fnames{i}, name) || strcmpi(fnames{i}, san)
            field = fnames{i};
            return;
        end
    end
end

function [locs, prom] = local_peaks(sig, min_sep, min_prom)
% LOCAL_PEAKS  Toolbox-free peak finder. No Signal Processing Toolbox needed.
%   locs     — indices of peaks in sig
%   prom     — prominence of each peak
%   min_sep  — minimum samples between returned peaks
%   min_prom — minimum prominence threshold

    n    = numel(sig);
    locs = [];
    prom = [];

    if n < 3, return; end

    % --- Step 1: find all local maxima ---
    is_peak = false(n, 1);
    for k = 2:n-1
        if sig(k) > sig(k-1) && sig(k) > sig(k+1)
            is_peak(k) = true;
        end
    end
    cands = find(is_peak);   % indices of all local maxima

    if isempty(cands), return; end

    % --- Step 2: prominence for each candidate ---
    % Prominence = peak height minus the highest col between it and any
    % taller peak. We compute left_base and right_base independently.
    sig_cands = sig(cands);   % peak values — fixed array, no index growth issue
    n_cands   = numel(cands);
    p         = zeros(n_cands, 1);

    for j = 1:n_cands
        k    = cands(j);
        pk_v = sig(k);

        % Left base: min of sig between here and the nearest taller peak to the left
        taller_left = cands(1:j-1);
        taller_left = taller_left(sig_cands(1:j-1) >= pk_v);
        if isempty(taller_left)
            left_base = min(sig(1:k));
        else
            left_base = min(sig(taller_left(end):k));
        end

        % Right base: min of sig between here and the nearest taller peak to the right
        taller_right = cands(j+1:end);
        taller_right = taller_right(sig_cands(j+1:end) >= pk_v);
        if isempty(taller_right)
            right_base = min(sig(k:n));
        else
            right_base = min(sig(k:taller_right(1)));
        end

        p(j) = pk_v - max(left_base, right_base);
    end

    % --- Step 3: filter by minimum prominence ---
    keep  = p >= min_prom;
    cands = cands(keep);
    p     = p(keep);

    if isempty(cands), return; end

    % --- Step 4: enforce minimum separation (keep most prominent) ---
    [~, sort_idx] = sort(p, 'descend');
    kept = false(numel(cands), 1);
    for j = 1:numel(sort_idx)
        idx = sort_idx(j);
        if ~any(kept & abs(cands - cands(idx)) < min_sep)
            kept(idx) = true;
        end
    end

    locs = sort(cands(kept));
    prom = p(kept);
end