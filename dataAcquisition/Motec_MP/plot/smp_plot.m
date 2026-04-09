function fig = smp_plot(plot_type, plot_data, labels, colour_keys, cfg, opts)
% SMP_PLOT  Unified plotting function for all SMP Supercars report charts.
%
% All plots share the same styling, font sizing, and colour logic.
% Designed to work with both manufacturer and driver colour modes.
%
% -------------------------------------------------------------------------
% Usage:
%   fig = smp_plot(plot_type, plot_data, labels, colour_keys, cfg)
%   fig = smp_plot(plot_type, plot_data, labels, colour_keys, cfg, opts)
%
% -------------------------------------------------------------------------
% plot_type  (string)
%   'boxplot'        - one coloured box per group
%   'violin'         - kernel-density violin per group
%   'fallingMaxSpeed'- running max speed trace, sorted descending
%   'trace'          - time/distance channel trace, one line per dataset
%   'lapmax'         - session overview: per-lap maximum of a channel
%
% -------------------------------------------------------------------------
% plot_data  (cell array, one element per group / dataset)
%
%   For 'boxplot' | 'violin' | 'fallingMaxSpeed':
%     Each element is a numeric column vector of values.
%
%   For 'trace':
%     Each element is a struct with fields:
%       .x        numeric vector   x-axis (time or distance)
%       .y        numeric vector   channel values
%     OR a Nx2 matrix [x, y].
%     The fastest-lap variant is handled externally — just pass the lap
%     you want plotted here (see smp_excel_plot_traces helper below).
%
%   For 'lapmax':
%     Each element is a struct with fields:
%       .laps     numeric vector   lap numbers (x-axis)
%       .values   numeric vector   per-lap maximum value (y-axis)
%     OR a Nx2 matrix [lap, value].
%
% -------------------------------------------------------------------------
% labels        cell of strings — legend / tick labels, one per dataset
% colour_keys   cell of strings — manufacturer or driver name for colour lookup
% cfg           struct from smp_colours() with cfg.colours field  OR
%               the direct colours struct (backwards compat, auto-detected)
%
% -------------------------------------------------------------------------
% opts  (optional struct)
%   .title          string   chart title
%   .xLabel         string   x-axis label
%   .yLabel         string   y-axis label
%   .colourMode     string   'manufacturer' (default) | 'driver'
%   .figWidth       double   pixels (default 960)
%   .figHeight      double   pixels (default 540)
%   .fontSize       double   (default 11)
%   .showGrid       logical  (default true)
%   .yLim           [lo hi]  fix y-axis limits
%   .xLim           [lo hi]  fix x-axis limits (trace/lapmax)
%   .sortBy         string   'none'(default)|'median_asc'|'median_desc'
%   .lineWidth      double   trace/lapmax line width (default 1.8)
%   .markerSize     double   lapmax marker size (default 6)
%   .showMarkers    logical  lapmax: show dots on each lap point (default true)
%   .legendLocation string   (default 'best')
%   .legendInfo     cell     extra info per dataset appended to legend
%                            e.g. {'Car 97','Car 888'} appended as "(Car 97)"
%                            If empty, nothing is appended.

    % ------------------------------------------------------------------ %
    %  Defaults
    % ------------------------------------------------------------------ %
    if nargin < 6 || isempty(opts), opts = struct(); end
    opts = set_default(opts, 'title',          '');
    opts = set_default(opts, 'xLabel',         '');
    opts = set_default(opts, 'yLabel',         '');
    opts = set_default(opts, 'colourMode',     'manufacturer');
    opts = set_default(opts, 'figWidth',       960);
    opts = set_default(opts, 'figHeight',      540);
    opts = set_default(opts, 'fontSize',       11);
    opts = set_default(opts, 'showGrid',       true);
    opts = set_default(opts, 'yLim',           []);
    opts = set_default(opts, 'xLim',           []);
    opts = set_default(opts, 'sortBy',         'none');
    opts = set_default(opts, 'lineWidth',      1.8);
    opts = set_default(opts, 'markerSize',     6);
    opts = set_default(opts, 'showMarkers',    true);
    opts = set_default(opts, 'legendLocation', 'best');
    opts = set_default(opts, 'legendInfo',     {});

    % ------------------------------------------------------------------ %
    %  Normalise cfg — accept either smp_colours() output or raw struct
    % ------------------------------------------------------------------ %
    if isfield(cfg, 'colours')
        colour_cfg = cfg.colours;
    else
        colour_cfg = cfg;   % legacy: cfg IS the colours struct
    end

    % ------------------------------------------------------------------ %
    %  Optional sort (statistical plots only)
    % ------------------------------------------------------------------ %
    if ~strcmp(opts.sortBy, 'none') && iscell(plot_data)
        can_sort = true;
        try
            cellfun(@(v) median(v(~isnan(v))), plot_data);
        catch
            can_sort = false;
        end
        if can_sort
            medians = cellfun(@(v) median(v(~isnan(v))), plot_data);
            if strcmp(opts.sortBy, 'median_asc')
                [~, ord] = sort(medians, 'ascend');
            else
                [~, ord] = sort(medians, 'descend');
            end
            plot_data   = plot_data(ord);
            labels      = labels(ord);
            colour_keys = colour_keys(ord);
            if ~isempty(opts.legendInfo)
                opts.legendInfo = opts.legendInfo(ord);
            end
        end
    end

    % ------------------------------------------------------------------ %
    %  Build colour array
    % ------------------------------------------------------------------ %
    n_groups = numel(labels);
    colours  = zeros(n_groups, 3);
    for i = 1:n_groups
        colours(i,:) = get_colour(colour_cfg, colour_keys{i}, opts.colourMode);
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
    %  Build legend labels with optional extra info
    % ------------------------------------------------------------------ %
    leg_labels = labels;
    if ~isempty(opts.legendInfo) && numel(opts.legendInfo) == numel(labels)
        for i = 1:numel(labels)
            extra = strtrim(char(string(opts.legendInfo{i})));
            if ~isempty(extra)
                leg_labels{i} = sprintf('%s  (%s)', labels{i}, extra);
            end
        end
    end

    % ------------------------------------------------------------------ %
    %  Dispatch
    % ------------------------------------------------------------------ %
    switch lower(plot_type)

        case 'boxplot'
            draw_boxplot(ax, plot_data, leg_labels, colours, opts);

        case 'violin'
            draw_violin(ax, plot_data, leg_labels, colours, opts);

        case 'fallingmaxspeed'
            draw_falling_max_speed(ax, plot_data, leg_labels, colours, opts);

        case 'trace'
            draw_trace(ax, plot_data, leg_labels, colours, opts);

        case 'lapmax'
            draw_lapmax(ax, plot_data, leg_labels, colours, opts);

        otherwise
            error('smp_plot: Unknown plot_type "%s".\nValid types: boxplot | violin | fallingMaxSpeed | trace | lapmax', plot_type);
    end

    % ------------------------------------------------------------------ %
    %  Common formatting
    % ------------------------------------------------------------------ %
    if ~isempty(opts.title),  title(ax,  opts.title,  'FontSize', opts.fontSize+1, 'FontWeight', 'bold'); end
    if ~isempty(opts.xLabel), xlabel(ax, opts.xLabel, 'FontSize', opts.fontSize); end
    if ~isempty(opts.yLabel), ylabel(ax, opts.yLabel, 'FontSize', opts.fontSize); end
    if ~isempty(opts.yLim),   ylim(ax, opts.yLim); end
    if ~isempty(opts.xLim),   xlim(ax, opts.xLim); end

    ax.XColor = [0.2 0.2 0.2];
    ax.YColor = [0.2 0.2 0.2];
    fig.Color = 'white';
    ax.Color  = [0.97 0.97 0.97];
end


% ======================================================================= %
%  TRACE — outing or lap channel trace
% ======================================================================= %
function draw_trace(ax, plot_data, labels, colours, opts)
% One line per dataset.  plot_data{i} is either:
%   - struct with .x and .y fields
%   - Nx2 matrix [x, y]

    n = numel(plot_data);
    leg_handles = gobjects(n, 1);

    for i = 1:n
        [x, y] = unpack_xy(plot_data{i});
        if isempty(x), continue; end

        col = colours(i,:);
        leg_handles(i) = plot(ax, x, y, '-', ...
            'Color',       col, ...
            'LineWidth',   opts.lineWidth, ...
            'DisplayName', labels{i});
    end

    valid = isgraphics(leg_handles) & isgraphics(leg_handles, 'line');
    if any(valid)
        legend(ax, leg_handles(valid), ...
            'Location', opts.legendLocation, ...
            'FontSize',  opts.fontSize - 1, ...
            'Box',       'off', ...
            'Interpreter', 'none');
    end
end


% ======================================================================= %
%  LAPMAX — per-lap maximum of a channel (session overview)
% ======================================================================= %
function draw_lapmax(ax, plot_data, labels, colours, opts)
% plot_data{i} is either:
%   - struct with .laps and .values
%   - Nx2 matrix [lap, value]
%
% Each dataset gets a line + optional markers.
% Useful for viewing how e.g. max brake pressure evolves across a session.

    n = numel(plot_data);
    leg_handles = gobjects(n, 1);

    marker_style = 'o';
    if ~opts.showMarkers
        marker_style = 'none';
    end

    for i = 1:n
        [laps, vals] = unpack_lapmax(plot_data{i});
        if isempty(laps), continue; end

        % Remove NaN
        ok   = ~isnan(laps) & ~isnan(vals);
        laps = laps(ok);
        vals = vals(ok);
        if isempty(laps), continue; end

        col = colours(i,:);
        leg_handles(i) = plot(ax, laps, vals, ...
            ['-', marker_style], ...
            'Color',            col, ...
            'LineWidth',        opts.lineWidth, ...
            'MarkerSize',       opts.markerSize, ...
            'MarkerFaceColor',  col, ...
            'MarkerEdgeColor',  col * 0.7, ...
            'DisplayName',      labels{i});
    end

    valid = isgraphics(leg_handles) & isgraphics(leg_handles, 'line');
    if any(valid)
        legend(ax, leg_handles(valid), ...
            'Location',    opts.legendLocation, ...
            'FontSize',    opts.fontSize - 1, ...
            'Box',         'off', ...
            'Interpreter', 'none');
    end

    if isempty(ax.XLabel.String)
        xlabel(ax, 'Lap', 'FontSize', opts.fontSize);
    end
end


% ======================================================================= %
%  BOXPLOT
% ======================================================================= %
function draw_boxplot(ax, plot_data, labels, colours, opts) %#ok<INUSD>

    n = numel(plot_data);
    all_vals  = [];
    all_grp   = [];
    grp_order = {};
    for i = 1:n
        v = plot_data{i};
        v = v(~isnan(v) & isfinite(v));
        if isempty(v), continue; end
        all_vals  = [all_vals;  v(:)];
        all_grp   = [all_grp;   repmat(i, numel(v), 1)];
        grp_order{end+1} = labels{i};
    end

    if isempty(all_vals), return; end

    bp = boxplot(ax, all_vals, all_grp, ...
        'Labels',   grp_order, ...
        'Widths',   0.6, ...
        'Symbol',   '+', ...
        'OutlierSize', 4);

    boxes  = findobj(bp, 'Tag', 'Box');
    meds   = findobj(bp, 'Tag', 'Median');
    caps   = [findobj(bp, 'Tag', 'Upper Cap'); findobj(bp, 'Tag', 'Lower Cap')];
    whisk  = [findobj(bp, 'Tag', 'Upper Whisker'); findobj(bp, 'Tag', 'Lower Whisker')];
    outs   = findobj(bp, 'Tag', 'Outliers');

    n_valid = numel(boxes);
    for i = 1:n_valid
        j = n_valid - i + 1;
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

    n = numel(plot_data);
    for i = 1:n
        v = plot_data{i};
        v = v(~isnan(v) & isfinite(v));
        if numel(v) < 3, continue; end

        col = colours(i,:);
        [f, xi] = ksdensity(v);
        f = f / max(f) * 0.4;
        xp = [i + f, fliplr(i - f)];
        yp = [xi,     fliplr(xi)];
        fill(ax, xp, yp, col, 'FaceAlpha', 0.65, 'EdgeColor', col*0.75, 'LineWidth', 0.8);

        med = median(v);
        plot(ax, [i-0.15, i+0.15], [med med], '-', 'Color', col*0.5, 'LineWidth', 2);
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
function draw_falling_max_speed(ax, plot_data, labels, colours, opts)

    n = numel(plot_data);
    leg_handles = gobjects(n,1);

    for i = 1:n
        v = plot_data{i};
        v = v(~isnan(v) & isfinite(v));
        if isempty(v), continue; end

        v_sorted = sort(v, 'descend');
        x = 1:numel(v_sorted);
        col = colours(i,:);
        leg_handles(i) = plot(ax, x, v_sorted, '-', ...
            'Color',       col, ...
            'LineWidth',   opts.lineWidth, ...
            'DisplayName', labels{i});
    end

    valid = isgraphics(leg_handles) & isgraphics(leg_handles, 'line');
    if any(valid)
        legend(ax, leg_handles(valid), 'Location', opts.legendLocation, ...
            'FontSize', opts.fontSize - 1, 'Box', 'off');
    end
    if isempty(ax.XLabel.String), xlabel(ax, 'Rank'); end
    if isempty(ax.YLabel.String), ylabel(ax, 'Speed'); end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %
function [x, y] = unpack_xy(d)
% Unpack trace data from struct or matrix.
    if isstruct(d)
        x = d.x(:);
        y = d.y(:);
    elseif isnumeric(d) && size(d,2) >= 2
        x = d(:,1);
        y = d(:,2);
    else
        x = [];  y = [];
    end
    % Remove NaN pairs
    ok = ~isnan(x) & ~isnan(y);
    x  = x(ok);
    y  = y(ok);
end


function [laps, vals] = unpack_lapmax(d)
% Unpack lapmax data from struct or matrix.
    if isstruct(d)
        if isfield(d, 'laps')
            laps = d.laps(:);
            vals = d.values(:);
        else
            laps = d.x(:);
            vals = d.y(:);
        end
    elseif isnumeric(d) && size(d,2) >= 2
        laps = d(:,1);
        vals = d(:,2);
    else
        laps = [];  vals = [];
    end
end


function s = set_default(s, field, val)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = val;
    end
end
