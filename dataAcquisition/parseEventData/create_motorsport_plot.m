function fig = create_motorsport_plot(plot_type, plot_data, cfg, opts)
% CREATE_MOTORSPORT_PLOT  Unified plotting function for motorsport data.
%
% All plot types share consistent styling and respect manufacturer/driver
% colour assignments.
%
% Usage:
%   fig = create_motorsport_plot(plot_type, plot_data, cfg)
%   fig = create_motorsport_plot(plot_type, plot_data, cfg, opts)
%
% -----------------------------------------------------------------------
%  PLOT TYPES
% -----------------------------------------------------------------------
%
%  'box'           Box plot — distribution of a stat per group
%  'violin'        Violin plot — same data as box but with KDE shape
%  'lap_trend'     Line plot of a stat value across lap numbers per group
%  'trace'         Overlaid distance-based channel traces per group
%  'falling_max'   Falling max speed profile (sorted descending per group)
%
% -----------------------------------------------------------------------
%  PLOT DATA FORMAT (varies by type)
% -----------------------------------------------------------------------
%
%  For 'box' and 'violin':
%    plot_data is a struct array, one per group:
%      plot_data(i).label   (char)   group label shown on x-axis
%      plot_data(i).values  (Nx1)    raw values (e.g. lap times)
%      plot_data(i).colour  (1x3)    RGB colour (optional — uses cfg.C if absent)
%
%  For 'lap_trend':
%    plot_data is a struct array, one per group:
%      plot_data(i).label       (char)
%      plot_data(i).lap_numbers (1xN)
%      plot_data(i).values      (1xN)
%      plot_data(i).colour      (1x3, optional)
%
%  For 'trace':
%    plot_data is a struct array, one per group:
%      plot_data(i).label      (char)
%      plot_data(i).dist_vec   (Mx1)   common distance grid (m)
%      plot_data(i).traces     (MxL)   each column = one lap trace
%      plot_data(i).colour     (1x3, optional)
%      plot_data(i).highlight_lap (integer, optional)  which column to draw bold
%
%  For 'falling_max':
%    plot_data is a struct array, one per group:
%      plot_data(i).label      (char)
%      plot_data(i).values     (1xN)   max speeds (one per lap)
%      plot_data(i).colour     (1x3, optional)
%
% -----------------------------------------------------------------------
%  CFG FIELDS
% -----------------------------------------------------------------------
%   cfg.C           Colours struct from colours.m (required if colours not
%                   embedded in plot_data)
%   cfg.title       Plot title
%   cfg.y_label     Y-axis label
%   cfg.x_label     X-axis label (overrides default for type)
%   cfg.units       Units string appended to y_label if provided
%
% -----------------------------------------------------------------------
%  OPTS FIELDS  (all optional)
% -----------------------------------------------------------------------
%   opts.fig_size       [width height] in pixels (default: [900 500])
%   opts.show_grid      (default: true)
%   opts.show_legend    (default: true, for trace/lap_trend)
%   opts.y_lim          [ymin ymax] manual y-axis limits
%   opts.x_lim          [xmin xmax] manual x-axis limits
%   opts.font_size      Base font size (default: 11)
%   opts.line_width     Line width for traces/trends (default: 1.5)
%   opts.alpha          Face alpha for box/violin fills (default: 0.75)
%   opts.show_outliers  Show outlier points on box plot (default: true)
%   opts.mean_marker    Show mean as marker on box/violin (default: true)
%   opts.trace_alpha    Alpha for individual lap traces (default: 0.35)
%   opts.tight_layout   Call tight axis (default: true)

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 4, opts = struct(); end

    fig_size     = get_opt(opts, 'fig_size',      [900 500]);
    show_grid    = get_opt(opts, 'show_grid',      true);
    show_legend  = get_opt(opts, 'show_legend',    true);
    font_size    = get_opt(opts, 'font_size',      11);
    line_width   = get_opt(opts, 'line_width',     1.5);
    alpha_val    = get_opt(opts, 'alpha',          0.75);
    show_outliers= get_opt(opts, 'show_outliers',  true);
    mean_marker  = get_opt(opts, 'mean_marker',    true);
    trace_alpha  = get_opt(opts, 'trace_alpha',    0.35);

    y_lim        = get_opt(opts, 'y_lim',          []);
    x_lim        = get_opt(opts, 'x_lim',          []);

    % ------------------------------------------------------------------
    %  Figure setup
    % ------------------------------------------------------------------
    fig = figure('Visible','on', ...
                 'Position',[100 100 fig_size(1) fig_size(2)], ...
                 'Color','white');
    ax  = axes('Parent', fig);
    hold(ax, 'on');

    % Apply base styling
    set(ax, 'FontSize', font_size, ...
            'FontName', 'Helvetica', ...
            'Color',    [0.97 0.97 0.97], ...
            'XColor',   [0.2 0.2 0.2], ...
            'YColor',   [0.2 0.2 0.2], ...
            'LineWidth', 0.8);

    if show_grid
        grid(ax, 'on');
        ax.GridColor      = [1 1 1];
        ax.GridLineStyle  = '-';
        ax.GridAlpha      = 0.9;
        ax.MinorGridAlpha = 0.4;
    end

    % ------------------------------------------------------------------
    %  Resolve colours
    %  Priority: plot_data(i).colour → cfg.C → built-in mfg lookup → fallback palette
    % ------------------------------------------------------------------

    % Built-in manufacturer colours (used when cfg.C is not provided)
    BUILTIN_MFG = struct();
    BUILTIN_MFG.ford       = [0.00  0.27  0.68];
    BUILTIN_MFG.chev       = [0.95  0.80  0.00];
    BUILTIN_MFG.chevrolet  = [0.95  0.80  0.00];
    BUILTIN_MFG.toyota     = [0.85  0.10  0.10];
    BUILTIN_MFG.holden     = [0.95  0.80  0.00];
    BUILTIN_MFG.mustang    = [0.00  0.27  0.68];
    BUILTIN_MFG.camaro     = [0.95  0.80  0.00];
    BUILTIN_MFG.camry      = [0.85  0.10  0.10];

    FALLBACK_PAL = [
        0.12  0.47  0.71;
        0.90  0.33  0.05;
        0.20  0.63  0.17;
        0.65  0.14  0.55;
        0.55  0.34  0.29;
        0.80  0.47  0.74;
        0.50  0.50  0.50;
    ];
    fallback_idx = 0;

    for i = 1:numel(plot_data)
        % Skip if colour already set directly on plot_data
        if isfield(plot_data(i),'colour') && ~isempty(plot_data(i).colour)
            continue;
        end

        assigned = false;

        % 1) Try cfg.C (colours() struct passed in)
        if isfield(cfg, 'C') && ~assigned
            try
                plot_data(i).colour = cfg.C.get(plot_data(i).label);
                assigned = true;
            catch
            end
        end

        % 2) Try built-in manufacturer lookup against the label string
        if ~assigned
            key = lower(strtrim(plot_data(i).label));
            % Strip trailing suffixes like "Gen 3", "Car 97", team codes
            key = regexprep(key, '\s+(gen|car|team|racing|motorsport|#).*$', '');
            key = strtrim(key);
            parts = strsplit(key, ' ');
            for p = 1:numel(parts)
                k = regexprep(parts{p}, '[^a-z]', '');
                if isfield(BUILTIN_MFG, k)
                    plot_data(i).colour = BUILTIN_MFG.(k);
                    assigned = true;
                    break;
                end
            end
        end

        % 3) Cycle through fallback palette
        if ~assigned
            fallback_idx = mod(fallback_idx, size(FALLBACK_PAL,1)) + 1;
            plot_data(i).colour = FALLBACK_PAL(fallback_idx, :);
        end
    end

    % ------------------------------------------------------------------
    %  Dispatch to plot type
    % ------------------------------------------------------------------
    switch lower(plot_type)
        case 'box'
            draw_box(ax, plot_data, alpha_val, show_outliers, mean_marker, line_width);
            default_x_label = '';
            if isfield(cfg,'x_label'), default_x_label = cfg.x_label; end
        case 'violin'
            draw_violin(ax, plot_data, alpha_val, mean_marker, line_width);
            default_x_label = '';
            if isfield(cfg,'x_label'), default_x_label = cfg.x_label; end
        case 'lap_trend'
            draw_lap_trend(ax, plot_data, line_width, show_legend);
            default_x_label = 'Lap Number';
            if isfield(cfg,'x_label'), default_x_label = cfg.x_label; end
        case 'trace'
            draw_trace(ax, plot_data, line_width, trace_alpha, show_legend);
            default_x_label = 'Distance (m)';
            if isfield(cfg,'x_label'), default_x_label = cfg.x_label; end
        case 'falling_max'
            draw_falling_max(ax, plot_data, line_width, show_legend);
            default_x_label = 'Rank';
            if isfield(cfg,'x_label'), default_x_label = cfg.x_label; end
        otherwise
            error('create_motorsport_plot: unknown plot type "%s".', plot_type);
    end

    % ------------------------------------------------------------------
    %  Labels, limits, title
    % ------------------------------------------------------------------
    if isfield(cfg,'title') && ~isempty(cfg.title)
        title(ax, cfg.title, 'FontSize', font_size+1, 'FontWeight','bold', ...
              'Color', [0.15 0.15 0.15]);
    end

    y_lbl = '';
    if isfield(cfg,'y_label'), y_lbl = cfg.y_label; end
    if isfield(cfg,'units') && ~isempty(cfg.units)
        y_lbl = sprintf('%s  [%s]', y_lbl, cfg.units);
    end
    ylabel(ax, y_lbl, 'FontSize', font_size);

    if exist('default_x_label','var') && ~isempty(default_x_label)
        xlabel(ax, default_x_label, 'FontSize', font_size);
    end

    if ~isempty(y_lim), ylim(ax, y_lim); end
    if ~isempty(x_lim), xlim(ax, x_lim); end

    box(ax, 'off');
end


% =======================================================================
%  BOX PLOT
% =======================================================================
function draw_box(ax, pd, alpha_val, show_outliers, mean_marker, lw)
    n = numel(pd);
    for i = 1:n
        v   = pd(i).values;
        v   = v(isfinite(v));
        if isempty(v), continue; end
        c   = pd(i).colour;
        dark_c = c * 0.6;

        q1  = quantile(v, 0.25);
        q3  = quantile(v, 0.75);
        med = median(v);
        iqr_v = q3 - q1;
        w_lo  = max(v(v >= q1 - 1.5*iqr_v));
        w_hi  = min(v(v <= q3 + 1.5*iqr_v));

        bw = 0.35;
        % Box fill
        fill(ax, [i-bw i+bw i+bw i-bw], [q1 q1 q3 q3], c, ...
             'FaceAlpha',alpha_val, 'EdgeColor',dark_c, 'LineWidth',lw);
        % Median line
        line(ax, [i-bw i+bw], [med med], 'Color',dark_c, 'LineWidth',lw*1.8);
        % Whiskers
        line(ax, [i i], [w_lo q1],  'Color',dark_c, 'LineWidth',lw);
        line(ax, [i i], [q3  w_hi], 'Color',dark_c, 'LineWidth',lw);
        % Whisker caps
        cap_w = bw * 0.4;
        line(ax, [i-cap_w i+cap_w], [w_lo w_lo], 'Color',dark_c, 'LineWidth',lw);
        line(ax, [i-cap_w i+cap_w], [w_hi w_hi], 'Color',dark_c, 'LineWidth',lw);

        % Outliers
        if show_outliers
            out_v = v(v < w_lo | v > w_hi);
            if ~isempty(out_v)
                scatter(ax, repmat(i,size(out_v)), out_v, 18, dark_c, ...
                    'filled','MarkerFaceAlpha',0.6);
            end
        end

        % Mean marker
        if mean_marker
            mn = mean(v);
            scatter(ax, i, mn, 40, 'w', 'd', 'filled', ...
                'MarkerEdgeColor', dark_c, 'LineWidth', 1);
        end
    end

    ax.XTick      = 1:n;
    ax.XTickLabel = {pd.label};
    ax.XLim       = [0.4, n+0.6];
end


% =======================================================================
%  VIOLIN PLOT
% =======================================================================
function draw_violin(ax, pd, alpha_val, mean_marker, lw)
    n = numel(pd);
    for i = 1:n
        v = pd(i).values;
        v = v(isfinite(v));
        if numel(v) < 4
            % Fall back to a simple line
            line(ax,[i i],[min(v) max(v)],'Color',pd(i).colour,'LineWidth',lw*2);
            continue;
        end

        c      = pd(i).colour;
        dark_c = c * 0.6;
        light_c = min(c + 0.3, 1);

        [f, xi] = ksdensity(v);
        vw = 0.38;
        f  = f / max(f) * vw;

        xR = i + f;
        xL = i - f;
        fill(ax, [xR, fliplr(xL)], [xi, fliplr(xi)], light_c, ...
            'EdgeColor',dark_c, 'LineWidth',1.0, 'FaceAlpha',alpha_val);

        % Median
        med  = median(v);
        hw   = interp1(xi, f, med, 'linear', 0);
        line(ax, [i-hw i+hw], [med med], 'Color',dark_c, 'LineWidth',lw*1.8);

        % IQR box
        q1  = quantile(v,0.25);  q3 = quantile(v,0.75);
        hw1 = interp1(xi, f, q1, 'linear', 0);
        hw3 = interp1(xi, f, q3, 'linear', 0);
        fill(ax, [i-hw1 i+hw1 i+hw3 i-hw3], [q1 q1 q3 q3], dark_c, ...
            'FaceAlpha',0.35,'EdgeColor','none');

        if mean_marker
            mn = mean(v);
            scatter(ax, i, mn, 40, 'w', 'd', 'filled', ...
                'MarkerEdgeColor', dark_c, 'LineWidth', 1);
        end
    end

    ax.XTick      = 1:n;
    ax.XTickLabel = {pd.label};
    ax.XLim       = [0.4, n+0.6];
end


% =======================================================================
%  LAP TREND
% =======================================================================
function draw_lap_trend(ax, pd, lw, show_legend)
    h = gobjects(numel(pd),1);
    for i = 1:numel(pd)
        v    = pd(i).values;
        laps = pd(i).lap_numbers;
        c    = pd(i).colour;

        valid = isfinite(v);
        h(i) = plot(ax, laps(valid), v(valid), '-o', ...
            'Color', c, 'LineWidth', lw, ...
            'MarkerSize', 5, 'MarkerFaceColor', c, ...
            'DisplayName', pd(i).label);
    end

    if show_legend && numel(pd) > 1
        leg = legend(ax, h, 'Location','best');
        leg.Box = 'off';
        leg.FontSize = 9;
    end
end


% =======================================================================
%  DISTANCE TRACE
% =======================================================================
function draw_trace(ax, pd, lw, trace_alpha, show_legend)
    h = gobjects(numel(pd),1);
    for i = 1:numel(pd)
        dv  = pd(i).dist_vec;
        tr  = pd(i).traces;          % M x L matrix
        c   = pd(i).colour;

        if isempty(tr), continue; end

        n_traces = size(tr, 2);
        hl_lap   = [];
        if isfield(pd(i),'highlight_lap') && ~isempty(pd(i).highlight_lap)
            hl_lap = pd(i).highlight_lap;
        end

        % Draw background laps
        for t = 1:n_traces
            if ~isempty(hl_lap) && t == hl_lap, continue; end
            plot(ax, dv, tr(:,t), '-', 'Color',[c, trace_alpha], ...
                'LineWidth', lw*0.6, 'HandleVisibility','off');
        end

        % Draw highlighted lap (or mean trace if no highlight)
        if ~isempty(hl_lap)
            h(i) = plot(ax, dv, tr(:,hl_lap), '-', 'Color',c, ...
                'LineWidth', lw*1.8, 'DisplayName', pd(i).label);
        else
            mean_tr = nanmean(tr, 2);
            h(i) = plot(ax, dv, mean_tr, '-', 'Color',c, ...
                'LineWidth', lw*1.5, 'DisplayName', pd(i).label);
        end
    end

    if show_legend && numel(pd) > 1
        leg = legend(ax, h(isgraphics(h)), 'Location','best');
        leg.Box = 'off';
        leg.FontSize = 9;
    end
end


% =======================================================================
%  FALLING MAX SPEED
% =======================================================================
function draw_falling_max(ax, pd, lw, show_legend)
    h = gobjects(numel(pd),1);
    for i = 1:numel(pd)
        v   = pd(i).values;
        v   = v(isfinite(v));
        v_s = sort(v, 'descend');
        c   = pd(i).colour;

        h(i) = plot(ax, 1:numel(v_s), v_s, '-o', ...
            'Color', c, 'LineWidth', lw, ...
            'MarkerSize', 4, 'MarkerFaceColor', c, ...
            'DisplayName', pd(i).label);
    end

    xlabel(ax, 'Rank');

    if show_legend && numel(pd) > 1
        leg = legend(ax, h(isgraphics(h)), 'Location','best');
        leg.Box = 'off';
        leg.FontSize = 9;
    end
end


% =======================================================================
%  HELPERS
% =======================================================================
function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end