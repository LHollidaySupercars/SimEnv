function fig = smp_plot(plot_type, plot_data, labels, colour_keys, cfg, opts)
% SMP_PLOT  Unified plotting function for all SMP Supercars report charts.
%
% All plots share the same styling, font sizing, and colour logic.
% Designed to work with both manufacturer and driver colour modes.
%
% Usage:
%   fig = smp_plot(plot_type, plot_data, labels, colour_keys, cfg)
%   fig = smp_plot(plot_type, plot_data, labels, colour_keys, cfg, opts)
%
% Inputs:
%   plot_type    - string: 'boxplot' | 'violin' | 'fallingMaxSpeed'
%
%   plot_data    - cell array of numeric vectors, one per group.
%                  For 'fallingMaxSpeed', a numeric column vector of speeds.
%
%   labels       - cell array of group label strings (same length as plot_data)
%
%   colour_keys  - cell array of strings for colour lookup (same length as plot_data)
%                  e.g. {'Ford','Ford','Chev','Toyota'}
%                  or   {'T. Mostert','S. van Gisbergen', ...}
%
%   cfg          - main config struct (must include cfg.colours from smp_colours())
%
%   opts         - optional struct of overrides:
%     .title         string   chart title
%     .xLabel        string   x-axis label
%     .yLabel        string   y-axis label
%     .colourMode    string   'manufacturer' (default) or 'driver'
%     .figWidth      double   pixels (default: 960)
%     .figHeight     double   pixels (default: 540)
%     .fontSize      double   base font size (default: 11)
%     .showGrid      logical  (default: true)
%     .yLim          [lo hi]  fix y-axis limits
%     .sortBy        string   'none'(default)|'median_asc'|'median_desc'
%
% Output:
%   fig   - invisible figure handle. Pass to insert_figure_to_slide().

    % ------------------------------------------------------------------ %
    %  Defaults
    % ------------------------------------------------------------------ %
    if nargin < 6 || isempty(opts), opts = struct(); end
    opts = set_default(opts, 'title',      '');
    opts = set_default(opts, 'xLabel',     '');
    opts = set_default(opts, 'yLabel',     '');
    opts = set_default(opts, 'colourMode', 'manufacturer');
    opts = set_default(opts, 'figWidth',   960);
    opts = set_default(opts, 'figHeight',  540);
    opts = set_default(opts, 'fontSize',   11);
    opts = set_default(opts, 'showGrid',   true);
    opts = set_default(opts, 'yLim',       []);
    opts = set_default(opts, 'sortBy',     'none');

    % ------------------------------------------------------------------ %
    %  Optional sort
    % ------------------------------------------------------------------ %
    if ~strcmp(opts.sortBy, 'none') && iscell(plot_data)
        medians = cellfun(@(v) median(v(~isnan(v))), plot_data);
        if strcmp(opts.sortBy, 'median_asc')
            [~, ord] = sort(medians, 'ascend');
        else
            [~, ord] = sort(medians, 'descend');
        end
        plot_data   = plot_data(ord);
        labels      = labels(ord);
        colour_keys = colour_keys(ord);
    end

    % ------------------------------------------------------------------ %
    %  Build colour array
    % ------------------------------------------------------------------ %
    n_groups = numel(labels);
    colours  = zeros(n_groups, 3);
    for i = 1:n_groups
        colours(i,:) = get_colour(cfg.colours, colour_keys{i}, opts.colourMode);
    end

    % ------------------------------------------------------------------ %
    %  Create figure
    % ------------------------------------------------------------------ %
    fig = figure('Visible',  'off', ...
                 'Color',    'white', ...
                 'Position', [100 100 opts.figWidth opts.figHeight]);
    ax = axes(fig);
    hold(ax, 'on');
    set(ax, 'FontSize', opts.fontSize, 'FontName', 'Arial');
    box(ax, 'on');
    if opts.showGrid
        grid(ax, 'on');
        ax.GridAlpha      = 0.25;
        ax.GridLineStyle  = '--';
        ax.GridColor      = [0.7 0.7 0.7];
    end

    % ------------------------------------------------------------------ %
    %  Dispatch to sub-plot function
    % ------------------------------------------------------------------ %
    switch lower(plot_type)

        case 'boxplot'
            draw_boxplot(ax, plot_data, labels, colours, opts);

        case 'violin'
            draw_violin(ax, plot_data, labels, colours, opts);

        case 'fallingmaxspeed'
            draw_falling_max_speed(ax, plot_data, labels, colours, opts);

        otherwise
            error('smp_plot: Unknown plot_type "%s". Use boxplot|violin|fallingMaxSpeed.', plot_type);
    end

    % ------------------------------------------------------------------ %
    %  Common formatting
    % ------------------------------------------------------------------ %
    if ~isempty(opts.title),  title(ax,  opts.title,  'FontSize', opts.fontSize+1, 'FontWeight', 'bold'); end
    if ~isempty(opts.xLabel), xlabel(ax, opts.xLabel, 'FontSize', opts.fontSize); end
    if ~isempty(opts.yLabel), ylabel(ax, opts.yLabel, 'FontSize', opts.fontSize); end
    if ~isempty(opts.yLim),   ylim(ax, opts.yLim); end

    ax.XColor = [0.2 0.2 0.2];
    ax.YColor = [0.2 0.2 0.2];
    fig.Color = 'white';
    ax.Color  = [0.97 0.97 0.97];
end


% ======================================================================= %
%  BOXPLOT
% ======================================================================= %
function draw_boxplot(ax, plot_data, labels, colours, opts) %#ok<INUSD>
% Coloured boxplot, one box per group.

    n = numel(plot_data);

    % Build combined data vector + grouping vector for MATLAB's boxplot()
    all_vals  = [];
    all_grp   = [];
    grp_order = {};
    for i = 1:n
        v = plot_data{i};
        v = v(~isnan(v) & isfinite(v));
        if isempty(v), continue; end
        all_vals  = [all_vals;  v(:)];          %#ok
        all_grp   = [all_grp;   repmat(i, numel(v), 1)]; %#ok
        grp_order{end+1} = labels{i};            %#ok
    end

    if isempty(all_vals), return; end

    bp = boxplot(ax, all_vals, all_grp, ...
        'Labels',   grp_order, ...
        'Widths',   0.6, ...
        'Symbol',   '+', ...
        'OutlierSize', 4);

    % Colour each box
    boxes  = findobj(bp, 'Tag', 'Box');
    meds   = findobj(bp, 'Tag', 'Median');
    caps   = findobj(bp, 'Tag', 'Upper Cap');
    caps   = [caps; findobj(bp, 'Tag', 'Lower Cap')];
    whisk  = findobj(bp, 'Tag', 'Upper Whisker');
    whisk  = [whisk; findobj(bp, 'Tag', 'Lower Whisker')];
    outs   = findobj(bp, 'Tag', 'Outliers');

    n_valid = numel(boxes);
    for i = 1:n_valid
        j = n_valid - i + 1;   % boxplot returns in reverse order
        if j > size(colours,1), continue; end
        col = colours(j,:);
        patch(get(boxes(i), 'XData'), get(boxes(i), 'YData'), col, ...
            'FaceAlpha', 0.75, 'EdgeColor', col*0.7, 'LineWidth', 1.2, 'Parent', ax);
        set(meds(i), 'Color', col*0.5, 'LineWidth', 2);
    end
    for h = [caps; whisk]'
        set(h, 'Color', [0.4 0.4 0.4], 'LineWidth', 1);
    end
    if ~isempty(outs)
        set(outs, 'MarkerEdgeColor', [0.5 0.5 0.5]);
    end

    ax.XTickLabelRotation = 30;
end


% ======================================================================= %
%  VIOLIN
% ======================================================================= %
function draw_violin(ax, plot_data, labels, colours, ~)
% Kernel density violin plot, no toolbox required.

    n = numel(plot_data);

    for i = 1:n
        v = plot_data{i};
        v = v(~isnan(v) & isfinite(v));
        if numel(v) < 3, continue; end

        col = colours(i,:);

        % Kernel density estimate
        [f, xi] = ksdensity(v);
        f = f / max(f) * 0.4;   % normalise width to 0.4 units

        % Fill violin body
        xp = [i + f, fliplr(i - f)];
        yp = [xi,     fliplr(xi)];
        fill(ax, xp, yp, col, 'FaceAlpha', 0.65, 'EdgeColor', col*0.75, 'LineWidth', 0.8);

        % Median line
        med = median(v);
        plot(ax, [i-0.15, i+0.15], [med med], '-', 'Color', col*0.5, 'LineWidth', 2);

        % IQR bar
        q1 = prctile(v, 25);
        q3 = prctile(v, 75);
        plot(ax, [i i], [q1 q3], '-', 'Color', col*0.5, 'LineWidth', 3);
    end

    set(ax, 'XTick', 1:n, 'XTickLabel', labels);
    ax.XTickLabelRotation = 30;
    xlim(ax, [0.5, n+0.5]);
end


% ======================================================================= %
%  FALLING MAX SPEED
% ======================================================================= %
function draw_falling_max_speed(ax, plot_data, labels, colours, ~)
% Falling maximum speed trace — shows the running maximum speed
% across laps in descending order (fastest to slowest).
%
% plot_data : cell array of speed vectors, one per group.
% Each vector is sorted descending and plotted as a line.

    n = numel(plot_data);
    leg_handles = gobjects(n,1);

    for i = 1:n
        v = plot_data{i};
        v = v(~isnan(v) & isfinite(v));
        if isempty(v), continue; end

        % Sort descending
        v_sorted = sort(v, 'descend');
        x = 1:numel(v_sorted);

        col = colours(i,:);
        leg_handles(i) = plot(ax, x, v_sorted, '-', ...
            'Color',     col, ...
            'LineWidth', 1.8, ...
            'DisplayName', labels{i});
    end

    valid = isgraphics(leg_handles) & isgraphics(leg_handles, 'line');
    if any(valid)
        legend(ax, leg_handles(valid), 'Location', 'northeast', ...
            'FontSize', 9, 'Box', 'off');
    end
    xlabel(ax, 'Rank');
    if isempty(ax.YLabel.String)
        ylabel(ax, 'Speed');
    end
end


% ======================================================================= %
%  UTILITY
% ======================================================================= %
function s = set_default(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
