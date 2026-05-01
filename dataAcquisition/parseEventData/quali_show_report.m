function quali_show_report(results, title_str)
% QUALI_SHOW_REPORT  Blocking pop-up showing qualifying fuel analysis results.
%
% One tab per car, each containing:
%   - flying-lap table (LapNum, LapTime, TyreSet, Fuel, Pressures, Temps)
%   - tyre pressure axes (if data available)
%
% Close the figure or press Enter to continue.
%
% Usage:
%   quali_show_report(results)
%   quali_show_report(results, 'TAS Q13')
%
% Inputs:
%   results    - struct from execute_quali_fuel_analysis, keyed by car.
%                Each field has: .tbl, .result, .driver, .car, .session
%   title_str  - (optional) string shown in the figure title bar

    if nargin < 2 || isempty(title_str), title_str = 'Qualifying Fuel Analysis'; end

    car_keys = fieldnames(results);
    n_cars   = numel(car_keys);
    if n_cars == 0
        fprintf('[quali_show_report] No results to display.\n');
        return
    end

    CORNERS       = {'FL', 'FR', 'RL', 'RR'};
    corner_labels = {'Front Left', 'Front Right', 'Rear Left', 'Rear Right'};

    BG       = [0.10 0.10 0.10];
    BG2      = [0.14 0.14 0.14];
    BG_ALT   = [0.18 0.18 0.18];
    FG       = [0.95 0.95 0.95];
    HDR_CLR  = [0.28 0.75 1.00];

    FIG_W    = 1100;
    HDR_H    = 50;
    TBL_H    = 240;
    AX_H     = 260;
    PAD      = 12;
    TAB_H    = HDR_H + PAD + TBL_H + PAD + AX_H + PAD + 30;

    fig = figure('Name', ['Quali Report — ' title_str], ...
                 'NumberTitle', 'off', ...
                 'Position', [80 60 FIG_W TAB_H + 30], ...
                 'Color', BG, ...
                 'CloseRequestFcn', @(src, ~) uiresume(src), ...
                 'KeyPressFcn',     @(src, evt) on_keypress(src, evt));

    % ---- Tab group ----
    tg = uitabgroup('Parent', fig, ...
                    'Units', 'pixels', ...
                    'Position', [0 0 FIG_W TAB_H + 30]);

    cmap = lines(n_cars);

    for ci = 1:n_cars
        key    = car_keys{ci};
        r      = results.(key);
        tbl    = r.tbl;
        laps   = r.result;
        driver = r.driver;
        car    = r.car;
        sess   = r.session;
        clr    = cmap(ci, :);

        tab_label = sprintf('Car %s  %s', car, driver);
        tab = uitab('Parent', tg, 'Title', tab_label, ...
                    'BackgroundColor', BG);

        y = TAB_H;  % running top-down cursor inside tab

        % ---- Header ----
        y = y - HDR_H;
        n_flying_tbl = sum(strcmp(tbl.LapType, 'flying'));
        uicontrol('Parent', tab, 'Style', 'text', ...
            'String', sprintf('Car %s  |  %s  |  %s  —  %d lap(s)  (%d flying)', ...
                              car, driver, sess, height(tbl), n_flying_tbl), ...
            'Units', 'pixels', 'Position', [5 y FIG_W-20 HDR_H-4], ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'ForegroundColor', HDR_CLR, 'BackgroundColor', BG, ...
            'HorizontalAlignment', 'left');

        y = y - PAD;

        % ---- Lap table ----
        y = y - TBL_H;

        % Convert table to cell for uitable
        n_rows = height(tbl);
        col_names = tbl.Properties.VariableNames;
        tbl_cell  = cell(n_rows, numel(col_names));
        for row = 1:n_rows
            for col = 1:numel(col_names)
                v = tbl.(col_names{col})(row);
                if isstring(v) || ischar(v)
                    tbl_cell{row, col} = char(v);
                elseif isnumeric(v)
                    if isnan(v)
                        tbl_cell{row, col} = '—';
                    elseif strcmp(col_names{col}, 'LapNum') || strcmp(col_names{col}, 'TyreSet')
                        tbl_cell{row, col} = v;
                    else
                        tbl_cell{row, col} = sprintf('%.3f', v);
                    end
                else
                    tbl_cell{row, col} = char(string(v));
                end
            end
        end

        col_widths = {45, 65, 80, 65, 55, 70, 100, 65, 65, 65, 65, 65, 65, 65, 65, 60, 60, 60, 60};
        col_widths = col_widths(1:min(numel(col_names), numel(col_widths)));

        uitable('Parent', tab, ...
            'Data', tbl_cell, ...
            'ColumnName', col_names, ...
            'ColumnWidth', col_widths, ...
            'Units', 'pixels', 'Position', [5 y FIG_W-20 TBL_H], ...
            'FontSize', 10, ...
            'BackgroundColor', [BG2; BG_ALT], ...
            'ForegroundColor', FG);

        y = y - PAD;

        % ---- Tyre pressure axes ----
        y = y - AX_H;
        ax_y0 = y + 6;
        ax_h  = AX_H - 16;
        ax_w  = floor((FIG_W - 80) / 4) - 8;

        has_press = false;
        for c = 1:4
            corner = CORNERS{c};
            vals = arrayfun(@(rr) rr.tyre_press.flying.(corner), laps);
            if any(~isnan(vals)), has_press = true; break; end
        end

        if has_press
            stints     = [laps.stint_number];
            lap_nums   = [laps.lap_number];
            u_stints   = unique(stints);
            stint_cmap = lines(numel(u_stints));

            for c = 1:4
                corner = CORNERS{c};
                ax_x   = 10 + (c-1) * (ax_w + 8);
                ax_c   = axes('Parent', tab, 'Units', 'pixels', ...  %#ok<LAXES>
                              'Position', [ax_x ax_y0 ax_w ax_h], ...
                              'Color', [0.08 0.08 0.08], ...
                              'XColor', [0.60 0.60 0.60], ...
                              'YColor', [0.60 0.60 0.60]);
                hold(ax_c, 'on'); grid(ax_c, 'on');
                ax_c.GridColor = [0.25 0.25 0.25];

                for s = 1:numel(u_stints)
                    mask = stints == u_stints(s);
                    vals = arrayfun(@(rr) rr.tyre_press.flying.(corner), laps(mask));
                    lnums = lap_nums(mask);
                    scatter(ax_c, lnums, vals, 50, 'filled', ...
                        'MarkerFaceColor', stint_cmap(s,:), ...
                        'DisplayName', sprintf('Stint %d', u_stints(s)));
                    valid = ~isnan(vals);
                    if sum(valid) >= 2
                        mn = mean(vals(valid), 'omitnan');
                        x_range = [min(lnums(valid))-0.5, max(lnums(valid))+0.5];
                        plot(ax_c, x_range, [mn mn], '--', ...
                            'Color', stint_cmap(s,:), 'LineWidth', 1.2, ...
                            'HandleVisibility', 'off');
                    end
                end

                title(ax_c, corner_labels{c}, 'Color', 'w', 'FontSize', 9);
                xlabel(ax_c, 'Lap', 'Color', [0.65 0.65 0.65], 'FontSize', 8);
                if c == 1
                    ylabel(ax_c, 'Pressure (bar)', 'Color', [0.65 0.65 0.65], 'FontSize', 8);
                    lg = legend(ax_c, 'show', 'Location', 'best');
                    set(lg, 'TextColor', 'w', 'Color', [0.14 0.14 0.14], 'FontSize', 7);
                end
            end
        else
            uicontrol('Parent', tab, 'Style', 'text', ...
                'String', 'No tyre pressure data available', ...
                'Units', 'pixels', 'Position', [5 ax_y0 FIG_W-20 ax_h], ...
                'FontSize', 11, 'ForegroundColor', [0.70 0.70 0.70], ...
                'BackgroundColor', BG, 'HorizontalAlignment', 'center');
        end
    end

    % ---- Combined tyre pressure tab (all cars) ----
    if n_cars > 1
        tab_all = uitab('Parent', tg, 'Title', 'All Cars — Tyre Pressure', ...
                        'BackgroundColor', BG);
        y_all = TAB_H - HDR_H - PAD;

        uicontrol('Parent', tab_all, 'Style', 'text', ...
            'String', 'Combined Tyre Pressures — All Cars', ...
            'Units', 'pixels', 'Position', [5 y_all FIG_W-20 HDR_H-4], ...
            'FontSize', 13, 'FontWeight', 'bold', ...
            'ForegroundColor', HDR_CLR, 'BackgroundColor', BG, ...
            'HorizontalAlignment', 'left');

        y_all = y_all - PAD;
        ax_h2  = TAB_H - HDR_H - PAD - PAD - 40;
        ax_w2  = floor((FIG_W - 80) / 4) - 8;

        for c = 1:4
            corner = CORNERS{c};
            ax_x   = 10 + (c-1) * (ax_w2 + 8);
            ax_c2  = axes('Parent', tab_all, 'Units', 'pixels', ...  %#ok<LAXES>
                          'Position', [ax_x y_all - ax_h2 ax_w2 ax_h2], ...
                          'Color', [0.08 0.08 0.08], ...
                          'XColor', [0.60 0.60 0.60], ...
                          'YColor', [0.60 0.60 0.60]);
            hold(ax_c2, 'on'); grid(ax_c2, 'on');
            ax_c2.GridColor = [0.25 0.25 0.25];

            for ci = 1:n_cars
                key    = car_keys{ci};
                r_laps = results.(key).result;
                car_lbl = sprintf('Car %s', results.(key).car);
                clr    = cmap(ci, :);
                lnums  = [r_laps.lap_number];
                vals   = arrayfun(@(rr) rr.tyre_press.flying.(corner), r_laps);
                valid  = ~isnan(vals);
                if any(valid)
                    scatter(ax_c2, lnums(valid), vals(valid), 45, 'filled', ...
                        'MarkerFaceColor', clr, 'DisplayName', car_lbl);
                    mn = mean(vals(valid), 'omitnan');
                    x_range = [min(lnums(valid))-0.5, max(lnums(valid))+0.5];
                    plot(ax_c2, x_range, [mn mn], '--', 'Color', clr, ...
                        'LineWidth', 1.0, 'HandleVisibility', 'off');
                end
            end

            title(ax_c2, corner_labels{c}, 'Color', 'w', 'FontSize', 9);
            xlabel(ax_c2, 'Lap', 'Color', [0.65 0.65 0.65], 'FontSize', 8);
            if c == 1
                ylabel(ax_c2, 'Pressure (bar)', 'Color', [0.65 0.65 0.65], 'FontSize', 8);
                lg2 = legend(ax_c2, 'show', 'Location', 'best');
                set(lg2, 'TextColor', 'w', 'Color', [0.14 0.14 0.14], 'FontSize', 7);
            end
        end
    end

    drawnow;

    uiwait(fig);
    if ishandle(fig), delete(fig); end
end

% -------------------------------------------------------------------------
function on_keypress(fig, evt)
    if strcmp(evt.Key, 'return')
        uiresume(fig);
    end
end
