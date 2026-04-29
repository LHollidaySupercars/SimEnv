function smp_plot_speed_trap(varargin)
% SMP_PLOT_SPEED_TRAP  Plot pit lane speed trap data coloured by manufacturer.
%
% Loads master_pit_speed.csv and produces a scatter plot of pit lane speed
% (kph) vs lap number, coloured by manufacturer (Ford/Chevrolet/Toyota),
% matching the V8SC Pit Wall colour scheme.
%
% Usage:
%   smp_plot_speed_trap                          % all events, all sessions
%   smp_plot_speed_trap('event', 'TAU')          % one event
%   smp_plot_speed_trap('event', 'TAU', 'session', 'R09')
%   smp_plot_speed_trap('event', {'TAU','RAU'})  % multiple events
%   smp_plot_speed_trap('report', 'top_speed')   % top speed data instead
%
% Name-value options:
%   event     string or cellstr   filter by event code(s)   (default: all)
%   session   string or cellstr   filter by session alias   (default: all)
%   report    'pit_speed'|'top_speed'                       (default: 'pit_speed')
%   sort      'none'|'descend'|'ascend'  sort x-axis by mean driver speed (default: 'none')
%   yLim      [lo hi]             manual y-axis limits       (default: auto)
%   title     string              override figure title      (default: auto)

    % ── Parse options ─────────────────────────────────────────────────────────
    p = inputParser;
    addParameter(p, 'event',   {});
    addParameter(p, 'session', {});
    addParameter(p, 'report',  'pit_speed');
    addParameter(p, 'sort',    'none');   % 'none' | 'descend' | 'ascend'
    addParameter(p, 'yLim',    []);
    addParameter(p, 'title',   '');
    addParameter(p, 'iqrScale', 1.5);     % outlier fence multiplier (0 = off)
    parse(p, varargin{:});
    opt = p.Results;

    % ── Load master CSV ───────────────────────────────────────────────────────
    timing_dir = fileparts(mfilename('fullpath'));
    if strcmp(opt.report, 'top_speed')
        master_path = fullfile(timing_dir, 'master_topspeed.csv');
        kph_col     = 'kph';
        y_label     = 'Top Speed (kph)';
    else
        master_path = fullfile(timing_dir, 'master_pit_speed.csv');
        kph_col     = 's1_kph';
        y_label     = 'Pit Lane Speed (kph)';
    end

    if ~isfile(master_path)
        error('smp_plot_speed_trap: master file not found:\n  %s\nRun smp_extract_folder first.', master_path);
    end

    T = readtable(master_path, 'Delimiter', ',', 'TextType', 'string');

    % Remove parse_error rows
    if ismember('parse_error', T.Properties.VariableNames)
        T = T(~strcmpi(T.parse_error, 'true'), :);
    end

    % ── Apply filters ─────────────────────────────────────────────────────────
    if ~isempty(opt.event)
        evs = string(opt.event);
        T   = T(ismember(upper(string(T.event)), upper(evs)), :);
    end
    if ~isempty(opt.session)
        ses = string(opt.session);
        T   = T(ismember(upper(string(T.session)), upper(ses)), :);
    end

    if height(T) == 0
        error('smp_plot_speed_trap: no rows after filtering. Check event/session names.');
    end

    % ── Ensure numeric lap and kph ────────────────────────────────────────────
    if isstring(T.lap) || iscell(T.lap)
        T.lap = str2double(string(T.lap));
    end
    if isstring(T.(kph_col)) || iscell(T.(kph_col))
        T.(kph_col) = str2double(string(T.(kph_col)));
    end

    % Remove rows with NaN kph or lap
    T = T(~isnan(T.(kph_col)) & ~isnan(T.lap), :);

    % ── IQR outlier filter ────────────────────────────────────────────────────
    % Applied globally (across all manufacturers) before plotting.
    % Filtered rows are collected for display in a separate table.
    T_filtered = T([], :);   % empty same-schema table
    if opt.iqrScale > 0 && height(T) >= 4
        q1      = quantile(T.(kph_col), 0.25);
        q3      = quantile(T.(kph_col), 0.75);
        iqr_val = q3 - q1;
        lo      = q1 - opt.iqrScale * iqr_val;
        hi      = q3 + opt.iqrScale * iqr_val;
        out_mask   = T.(kph_col) < lo | T.(kph_col) > hi;
        T_filtered = T(out_mask, :);
        T          = T(~out_mask, :);
    end

    % ── Sort each driver's speeds, assign incremental x index ────────────────
    if ~strcmp(opt.sort, 'none')
        T.x_pos = zeros(height(T), 1);
        cars = unique(string(T.car));
        for di = 1:numel(cars)
            mask = string(T.car) == cars(di);
            vals = T.(kph_col)(mask);
            [~, order] = sort(vals, opt.sort);   % sort this driver's speeds
            idx = find(mask);
            T.x_pos(idx(order)) = 1:sum(mask);   % x = 1, 2, 3... within driver
        end
        x_col   = 'x_pos';
        x_label = 'Observation (sorted by speed)';
        x_ticks  = [];
        x_labels = {};
    else
        x_col   = 'lap';
        x_label = 'Lap Number';
        x_ticks  = [];
        x_labels = {};
    end

    % ── Infer manufacturer ────────────────────────────────────────────────────
    % For pit_speed: derived from 'vehicle' column.
    % For top_speed: no vehicle column — look up car number in driverAlias.xlsx.
    if ismember('vehicle', T.Properties.VariableNames)
        T.manufacturer = infer_manufacturer(string(T.vehicle));
    else
        alias_path  = fullfile(timing_dir, '..', 'Motec_MP', 'alias', 'driverAlias.xlsx');
        driver_map  = smp_driver_alias_load(alias_path);
        car_mfr_map = build_car_mfr_map(driver_map);
        T.manufacturer = lookup_manufacturer_by_car(string(T.car), car_mfr_map);
    end

    % ── Colour map matching V8SC Pit Wall ─────────────────────────────────────
    mfr_colours = struct( ...
        'Ford',      [  0,  87, 184] / 255, ...
        'Chevrolet', [245, 196,   0] / 255, ...
        'Toyota',    [235,  10,  30] / 255, ...
        'Unknown',   [ 90, 102, 120] / 255  ...
    );

    % ── Build figure ──────────────────────────────────────────────────────────
    fig = figure('Color', [0.05 0.07 0.09], 'Units', 'normalized', ...
                 'Position', [0.05 0.1 0.88 0.75]);

    ax = axes(fig, 'Color', [0.05 0.07 0.09], ...
              'XColor', [0.35 0.4 0.47], 'YColor', [0.35 0.4 0.47], ...
              'GridColor', [1 1 1], 'GridAlpha', 0.04, ...
              'FontName', 'Consolas', 'FontSize', 9);
    hold(ax, 'on'); grid(ax, 'on'); box(ax, 'off');

    manufacturers = unique(T.manufacturer);
    h_legend      = gobjects(0);
    l_legend      = {};

    for mi = 1:numel(manufacturers)
        mfr  = char(manufacturers(mi));
        mask = T.manufacturer == manufacturers(mi);
        Tm   = T(mask, :);

        if isfield(mfr_colours, mfr)
            col = mfr_colours.(mfr);
        else
            col = mfr_colours.Unknown;
        end

        % One scatter handle per manufacturer (for legend)
        h = scatter(ax, Tm.(x_col), Tm.(kph_col), 22, col, 'filled', ...
                    'MarkerFaceAlpha', 0.7, 'MarkerEdgeAlpha', 0);

        h_legend(end+1) = h; %#ok<AGROW>
        l_legend{end+1} = mfr; %#ok<AGROW>
    end

    % ── Per-index manufacturer average dashes ────────────────────────────────
    % For each x position (1st fastest, 2nd fastest… or lap number), draw a
    % short horizontal dash showing the manufacturer's mean kph at that index.
    % Outliers are excluded using IQR fences computed across the full
    % manufacturer population before averaging (iqrScale=0 disables filtering).
    half_dash = 0.35;   % half-width in x-axis units

    for mi = 1:numel(manufacturers)
        mfr  = char(manufacturers(mi));
        mask = T.manufacturer == manufacturers(mi);
        Tm   = T(mask, :);

        if isfield(mfr_colours, mfr)
            col = mfr_colours.(mfr);
        else
            col = mfr_colours.Unknown;
        end

        % IQR outlier fence — computed on the full manufacturer population
        all_vals = Tm.(kph_col);
        if opt.iqrScale > 0 && sum(~isnan(all_vals)) >= 4
            q1  = quantile(all_vals, 0.25);
            q3  = quantile(all_vals, 0.75);
            iqr_val = q3 - q1;
            lo  = q1 - opt.iqrScale * iqr_val;
            hi  = q3 + opt.iqrScale * iqr_val;
            Tm  = Tm(Tm.(kph_col) >= lo & Tm.(kph_col) <= hi, :);
        end

        x_indices = unique(Tm.(x_col));
        for xi = 1:numel(x_indices)
            xv   = x_indices(xi);
            avg  = mean(Tm.(kph_col)(Tm.(x_col) == xv), 'omitnan');
            if isnan(avg), continue; end
            plot(ax, [xv - half_dash, xv + half_dash], [avg, avg], ...
                 '-', 'Color', [col, 1.0], 'LineWidth', 2.0, ...
                 'HandleVisibility', 'off');
        end
    end

    % ── Axis labels & title ───────────────────────────────────────────────────
    xlabel(ax, x_label,  'Color', [0.53 0.6 0.67], 'FontName', 'Consolas');
    ylabel(ax, y_label,  'Color', [0.53 0.6 0.67], 'FontName', 'Consolas');

    if ~isempty(x_ticks)
        ax.XTick      = x_ticks;
        ax.XTickLabel = x_labels;
        ax.XTickLabelRotation = 45;
        ax.TickLabelInterpreter = 'none';
    end

    if ~isempty(opt.title)
        title_str = opt.title;
    else
        events   = unique(upper(string(T.event)));
        sessions = unique(upper(string(T.session)));
        title_str = sprintf('%s — %s   |   %s', ...
            upper(opt.report), strjoin(events, ', '), strjoin(sessions, ' / '));
    end
    title(ax, title_str, 'Color', [0.91 0.93 0.95], 'FontName', 'Consolas', 'FontSize', 11, 'Interpreter', 'none');

    if ~isempty(opt.yLim)
        ylim(ax, opt.yLim);
    end

    % ── Legend ────────────────────────────────────────────────────────────────
    lg = legend(ax, h_legend, l_legend, 'Location', 'best', ...
                'TextColor', [0.53 0.6 0.67], 'FontName', 'Consolas', ...
                'EdgeColor', [0.2 0.23 0.27], 'Color', [0.08 0.1 0.13]);
    lg.FontSize = 9;

    % ── Filtered-out rows table ───────────────────────────────────────────────
    if height(T_filtered) > 0
        % Pick columns that are always present
        keep_cols = {'car','driver','lap', kph_col};
        if ismember('manufacturer', T_filtered.Properties.VariableNames)
            keep_cols{end+1} = 'manufacturer';
        end
        keep_cols = keep_cols(ismember(keep_cols, T_filtered.Properties.VariableNames));
        T_out = T_filtered(:, keep_cols);
        T_out = sortrows(T_out, kph_col, 'ascend');

        fprintf('\n── Filtered outliers (iqrScale=%.1f) ─────────────────────────────\n', opt.iqrScale);
        disp(T_out);
        fprintf('Total filtered: %d row(s)\n\n', height(T_out));
    end

end

% ── Local helper ──────────────────────────────────────────────────────────────

function mfr = infer_manufacturer(vehicle_col)
% Map vehicle name strings to manufacturer names.
    mfr = repmat("Unknown", numel(vehicle_col), 1);
    mfr(contains(vehicle_col, 'Ford',     'IgnoreCase', true)) = "Ford";
    mfr(contains(vehicle_col, 'Chev',     'IgnoreCase', true)) = "Chevrolet";
    mfr(contains(vehicle_col, 'Chevrolet','IgnoreCase', true)) = "Chevrolet";
    mfr(contains(vehicle_col, 'Toyota',   'IgnoreCase', true)) = "Toyota";
end

function car_mfr_map = build_car_mfr_map(driver_map)
% Build a car number -> manufacturer containers.Map from a smp_driver_alias_load struct.
    car_mfr_map = containers.Map('KeyType', 'char', 'ValueType', 'char');
    fields = fieldnames(driver_map);
    for i = 1:numel(fields)
        d = driver_map.(fields{i});
        if isfield(d, 'num') && isfield(d, 'manufacturer') && ~isempty(d.num) && ~isempty(d.manufacturer)
            car_mfr_map(d.num) = d.manufacturer;
        end
    end
end

function mfr = lookup_manufacturer_by_car(car_col, car_mfr_map)
% Look up manufacturer string for each car number using a containers.Map.
    mfr = repmat("Unknown", numel(car_col), 1);
    for i = 1:numel(car_col)
        key = strtrim(char(car_col(i)));
        if isKey(car_mfr_map, key)
            mfr(i) = string(car_mfr_map(key));
        end
    end
end
