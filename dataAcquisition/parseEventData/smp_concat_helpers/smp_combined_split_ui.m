% function result = smp_combined_split_ui(ert, aux, aux_label, labels, suggested_t, file_display_name)
% %% smp_combined_split_ui(ert, aux, aux_label, labels, suggested_t, file_display_name)
% % Visual split tool for a combined-session .ld file, e.g. "P01_P02".
% % Same interaction pattern as the Segment Alignment Tool in smp_pair_sessions.m:
% % left-click to place a marker, right-click to remove, auto-suggested
% % marker pre-placed, buttons to confirm / clear / skip.
% %
% % Inputs:
% %   ert                — struct with .time, .data (uptime channel, full file)
% %   aux                — struct with .time, .data — secondary channel for
% %                        visual context, e.g. Ground_Speed (optional, [] to omit)
% %   aux_label           — display name/axis label for aux, e.g. 'Ground Speed'
% %   labels              — cell array of N session labels, e.g. {'P01','P02'}
% %                         (N-1 markers are required — supports 3-way splits too)
% %   suggested_t         — auto-suggested marker time(s) (scalar for N=2)
% %   file_display_name   — string shown in the title bar
% %
% % Returns:
% %   result — sorted vector of numel(labels)-1 split times (s), or
% %            'SKIP' if the user chose to skip, or
% %            []     if the window was closed with no confirmation
% 
%     n_markers_needed = numel(labels) - 1;
%     markers = sort(suggested_t(:)');
%     if numel(markers) > n_markers_needed
%         markers = markers(1:n_markers_needed);
%     end
% 
%     setappdata(0, 'smp_combined_split_tmp', []);
% 
%     fig = figure('Name', 'Combined Session Split Tool', 'NumberTitle', 'off', ...
%         'Position', [60 60 1200 760], ...
%         'CloseRequestFcn', @on_close);
% 
%     ax = axes('Parent', fig, 'Position', [0.05 0.28 0.92 0.66]);
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Confirm Split', ...
%         'Units', 'pixels', 'Position', [20 90 130 30], ...
%         'BackgroundColor', [0.2 0.7 0.3], 'ForegroundColor', 'white', ...
%         'FontWeight', 'bold', ...
%         'Callback', @(~,~) do_confirm());
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Clear Markers', ...
%         'Units', 'pixels', 'Position', [160 90 120 30], ...
%         'Callback', @(~,~) clear_markers());
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Reset to Suggested', ...
%         'Units', 'pixels', 'Position', [290 90 150 30], ...
%         'Callback', @(~,~) reset_suggested());
% 
%     uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip This File', ...
%         'Units', 'pixels', 'Position', [450 90 130 30], ...
%         'BackgroundColor', [0.5 0.5 0.5], 'ForegroundColor', 'white', ...
%         'Callback', @(~,~) do_skip());
% 
%     status_txt = uicontrol(fig, 'Style', 'text', ...
%         'Units', 'pixels', 'Position', [20 130 1150 22], ...
%         'String', sprintf('Left-click to place/move split marker(s) — need %d for %d sessions. Right-click to remove.', ...
%             n_markers_needed, numel(labels)), ...
%         'HorizontalAlignment', 'left', 'FontSize', 9, ...
%         'ForegroundColor', [0.2 0.2 0.7], 'FontWeight', 'bold', ...
%         'BackgroundColor', get(fig, 'Color'));
% 
%     info_txt = uicontrol(fig, 'Style', 'text', ...
%         'Units', 'pixels', 'Position', [20 55 1150 28], ...
%         'String', '', ...
%         'HorizontalAlignment', 'left', 'FontSize', 8, ...
%         'ForegroundColor', [0.4 0.4 0.4], ...
%         'BackgroundColor', get(fig, 'Color'));
% 
%     set(ax, 'ButtonDownFcn', @on_click);
%     redraw();
%     waitfor(fig);
% 
%     result = getappdata(0, 'smp_combined_split_tmp');
%     if isappdata(0, 'smp_combined_split_tmp')
%         rmappdata(0, 'smp_combined_split_tmp');
%     end
% 
%     % -------------------------------------------------------------------
%     function redraw()
%         % cla() does NOT remove xline/yline (ConstantLine) objects — they
%         % must be deleted explicitly, or every redraw stacks another set
%         % of split markers on top of the old ones.
%         delete(findobj(ax, 'Type', 'ConstantLine'));
%         cla(ax); hold(ax, 'on');
% 
%         yyaxis(ax, 'left');
%         plot(ax, ert.time, ert.data, 'b-', 'LineWidth', 0.9, ...
%             'DisplayName', 'Uptime', 'HitTest', 'off');
%         ylabel(ax, 'Uptime (s)');
%         ax.YAxis(1).Exponent = 0;   % avoid confusing x10^n scaling
% 
%         if ~isempty(aux)
%             yyaxis(ax, 'right');
%             plot(ax, aux.time, aux.data, 'Color', [0.85 0.33 0.10], ...
%                 'LineWidth', 0.6, 'DisplayName', aux_label, 'HitTest', 'off');
%             ylabel(ax, aux_label);
%             ax.YAxis(2).Exponent = 0;
%             yyaxis(ax, 'left');
%             ax.YLim([0, 300])
%         end
% 
%         yl = ylim(ax);
%         seg_bounds = [ert.time(1), sort(markers), ert.time(end)];
%         colours = lines(numel(labels));
%         for si = 1 : numel(labels)
%             patch(ax, [seg_bounds(si) seg_bounds(si) seg_bounds(si+1) seg_bounds(si+1)], ...
%                 [yl(1) yl(2) yl(2) yl(1)], colours(si,:), ...
%                 'FaceAlpha', 0.06, 'EdgeColor', 'none', ...
%                 'HandleVisibility', 'off', 'HitTest', 'off');
%             mid_t = (seg_bounds(si) + seg_bounds(si+1)) / 2;
%             text(ax, mid_t, yl(2)*0.95, labels{si}, ...
%                 'HorizontalAlignment', 'center', 'FontSize', 10, ...
%                 'FontWeight', 'bold', 'Color', colours(si,:)*0.7, 'HitTest', 'off');
%         end
% 
%         for k = 1 : numel(markers)
%             xline(ax, markers(k), 'm--', 'LineWidth', 1.6, ...
%                 'Label', sprintf('split %d  t=%.0fs', k, markers(k)), ...
%                 'LabelVerticalAlignment', 'bottom', ...
%                 'HandleVisibility', 'off', 'HitTest', 'off');
%         end
% 
%         legend(ax, 'Location', 'northoutside', 'Orientation', 'horizontal', 'FontSize', 8);
%         xlabel(ax, 'Time (s)');
%         title(ax, sprintf('%s — click to set split boundary', file_display_name), ...
%             'Interpreter', 'none');
%         grid(ax, 'on'); hold(ax, 'off');
%         set(ax, 'ButtonDownFcn', @on_click);
% 
%         if numel(markers) == n_markers_needed
%             info_str = sprintf('Ready: %d marker(s) placed -> %s', ...
%                 n_markers_needed, mat2str(round(markers, 1)));
%             set(info_txt, 'ForegroundColor', [0.1 0.5 0.1], 'String', info_str);
%         else
%             info_str = sprintf('Need %d marker(s), have %d — Confirm disabled until correct count.', ...
%                 n_markers_needed, numel(markers));
%             set(info_txt, 'ForegroundColor', [0.7 0.2 0.1], 'String', info_str);
%         end
%     end
% 
%     function on_click(~, evt)
%         click_t = evt.IntersectionPoint(1);
%         btn     = evt.Button;
%         if btn == 1
%             if numel(markers) >= n_markers_needed
%                 % Replace the nearest marker instead of adding a new one
%                 [~, ri] = min(abs(markers - click_t));
%                 markers(ri) = click_t;
%             else
%                 markers = sort([markers, click_t]);
%             end
%             fprintf('[SPLIT] Marker set at %.2fs\n', click_t);
%         elseif btn == 3
%             if ~isempty(markers)
%                 [~, ri] = min(abs(markers - click_t));
%                 fprintf('[SPLIT] Marker at %.2fs removed\n', markers(ri));
%                 markers(ri) = [];
%             end
%         end
%         redraw();
%     end
% 
%     function clear_markers()
%         markers = [];
%         redraw();
%     end
% 
%     function reset_suggested()
%         markers = sort(suggested_t(:)');
%         if numel(markers) > n_markers_needed
%             markers = markers(1:n_markers_needed);
%         end
%         redraw();
%     end
% 
%     function do_confirm()
%         if numel(markers) ~= n_markers_needed
%             set(status_txt, 'ForegroundColor', [0.8 0.1 0.1], ...
%                 'String', sprintf('Cannot confirm: need exactly %d marker(s), have %d.', ...
%                 n_markers_needed, numel(markers)));
%             return;
%         end
%         setappdata(0, 'smp_combined_split_tmp', sort(markers));
%         delete(fig);
%     end
% 
%     function do_skip()
%         setappdata(0, 'smp_combined_split_tmp', 'SKIP');
%         delete(fig);
%     end
% 
%     function on_close(~,~)
%         if ~isappdata(0, 'smp_combined_split_tmp')
%             setappdata(0, 'smp_combined_split_tmp', []);
%         end
%         delete(fig);
%     end
% end

function result = smp_combined_split_ui(ert, aux, aux_label, labels, suggested_t, file_display_name)
%% smp_combined_split_ui(ert, aux, aux_label, labels, suggested_t, file_display_name)
% Visual split tool for a combined-session .ld file, e.g. "P01_P02".
% Same interaction pattern as the Segment Alignment Tool in smp_pair_sessions.m:
% left-click to place a marker, right-click to remove, auto-suggested
% marker pre-placed, buttons to confirm / clear / skip.
%
% Inputs:
%   ert                — struct with .time, .data (uptime channel, full file)
%   aux                — struct with .time, .data — secondary channel for
%                        visual context, e.g. Ground_Speed (optional, [] to omit)
%   aux_label           — display name/axis label for aux, e.g. 'Ground Speed'
%   labels              — cell array of N session labels, e.g. {'P01','P02'}
%                         (N-1 markers are required — supports 3-way splits too)
%   suggested_t         — auto-suggested marker time(s) (scalar for N=2)
%   file_display_name   — string shown in the title bar
%
% Returns:
%   result — sorted vector of numel(labels)-1 split times (s), or
%            'SKIP' if the user chose to skip, or
%            []     if the window was closed with no confirmation

    n_markers_needed = numel(labels) - 1;
    markers = sort(suggested_t(:)');
    if numel(markers) > n_markers_needed
        markers = markers(1:n_markers_needed);
    end

    setappdata(0, 'smp_combined_split_tmp', []);

    fig = figure('Name', 'Combined Session Split Tool', 'NumberTitle', 'off', ...
        'Position', [60 60 1200 760], ...
        'CloseRequestFcn', @on_close);

    ax = axes('Parent', fig, 'Position', [0.05 0.28 0.92 0.66]);

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Confirm Split', ...
        'Units', 'pixels', 'Position', [20 90 130 30], ...
        'BackgroundColor', [0.2 0.7 0.3], 'ForegroundColor', 'white', ...
        'FontWeight', 'bold', ...
        'Callback', @(~,~) do_confirm());

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Clear Markers', ...
        'Units', 'pixels', 'Position', [160 90 120 30], ...
        'Callback', @(~,~) clear_markers());

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Reset to Suggested', ...
        'Units', 'pixels', 'Position', [290 90 150 30], ...
        'Callback', @(~,~) reset_suggested());

    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Skip This File', ...
        'Units', 'pixels', 'Position', [450 90 130 30], ...
        'BackgroundColor', [0.5 0.5 0.5], 'ForegroundColor', 'white', ...
        'Callback', @(~,~) do_skip());

    status_txt = uicontrol(fig, 'Style', 'text', ...
        'Units', 'pixels', 'Position', [20 130 1150 22], ...
        'String', sprintf('Left-click to place/move split marker(s) — need %d for %d sessions. Right-click to remove.', ...
            n_markers_needed, numel(labels)), ...
        'HorizontalAlignment', 'left', 'FontSize', 9, ...
        'ForegroundColor', [0.2 0.2 0.7], 'FontWeight', 'bold', ...
        'BackgroundColor', get(fig, 'Color'));

    info_txt = uicontrol(fig, 'Style', 'text', ...
        'Units', 'pixels', 'Position', [20 55 1150 28], ...
        'String', '', ...
        'HorizontalAlignment', 'left', 'FontSize', 8, ...
        'ForegroundColor', [0.4 0.4 0.4], ...
        'BackgroundColor', get(fig, 'Color'));

    set(ax, 'ButtonDownFcn', @on_click);
    redraw();
    waitfor(fig);

    result = getappdata(0, 'smp_combined_split_tmp');
    if isappdata(0, 'smp_combined_split_tmp')
        rmappdata(0, 'smp_combined_split_tmp');
    end

    % -------------------------------------------------------------------
    function redraw()
        % cla() does NOT remove xline/yline (ConstantLine) objects — they
        % must be deleted explicitly, or every redraw stacks another set
        % of split markers on top of the old ones.
        delete(findobj(ax, 'Type', 'ConstantLine'));

        % cla() also only clears whichever yyaxis side is currently
        % active — clear both explicitly or old right-axis (aux) lines
        % keep accumulating underneath each redraw.
        yyaxis(ax, 'left');  cla(ax);
        yyaxis(ax, 'right'); cla(ax);
        yyaxis(ax, 'left');
        hold(ax, 'on');

        yyaxis(ax, 'left');
        plot(ax, ert.time, ert.data, 'b-', 'LineWidth', 0.9, ...
            'DisplayName', 'Uptime', 'HitTest', 'off');
        ylabel(ax, 'Uptime (s)');
        ax.YAxis(1).Exponent = 0;   % avoid confusing x10^n scaling

        if ~isempty(aux)
            yyaxis(ax, 'right');
            plot(ax, aux.time, aux.data, 'Color', [0.85 0.33 0.10], ...
                'LineWidth', 0.6, 'DisplayName', aux_label, 'HitTest', 'off');
            ylabel(ax, aux_label);
            ax.YAxis(2).Exponent = 0;
            ylim(ax, [0 300]);   % fixed speed-channel range, avoids auto-scale blowout
            yyaxis(ax, 'left');
        end

        % Defensive clamp — redraw() must never render more split lines
        % than n_markers_needed, no matter what state `markers` is in.
        markers = unique(sort(markers));
        if numel(markers) > n_markers_needed
            markers = markers(1:n_markers_needed);
        end

        yl = ylim(ax);
        seg_bounds = [ert.time(1), sort(markers), ert.time(end)];
        colours = lines(numel(labels));
        for si = 1 : numel(labels)
            patch(ax, [seg_bounds(si) seg_bounds(si) seg_bounds(si+1) seg_bounds(si+1)], ...
                [yl(1) yl(2) yl(2) yl(1)], colours(si,:), ...
                'FaceAlpha', 0.06, 'EdgeColor', 'none', ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            mid_t = (seg_bounds(si) + seg_bounds(si+1)) / 2;
            text(ax, mid_t, yl(2)*0.95, labels{si}, ...
                'HorizontalAlignment', 'center', 'FontSize', 10, ...
                'FontWeight', 'bold', 'Color', colours(si,:)*0.7, 'HitTest', 'off');
        end

        for k = 1 : numel(markers)
            xline(ax, markers(k), 'm--', 'LineWidth', 1.6, ...
                'Label', sprintf('split %d  t=%.0fs', k, markers(k)), ...
                'LabelVerticalAlignment', 'bottom', ...
                'HandleVisibility', 'off', 'HitTest', 'off');
        end

        legend(ax, 'Location', 'northoutside', 'Orientation', 'horizontal', 'FontSize', 8);
        xlabel(ax, 'Time (s)');
        title(ax, sprintf('%s — click to set split boundary', file_display_name), ...
            'Interpreter', 'none');
        grid(ax, 'on'); hold(ax, 'off');
        set(ax, 'ButtonDownFcn', @on_click);

        if numel(markers) == n_markers_needed
            info_str = sprintf('Ready: %d marker(s) placed -> %s', ...
                n_markers_needed, mat2str(round(markers, 1)));
            set(info_txt, 'ForegroundColor', [0.1 0.5 0.1], 'String', info_str);
        else
            info_str = sprintf('Need %d marker(s), have %d — Confirm disabled until correct count.', ...
                n_markers_needed, numel(markers));
            set(info_txt, 'ForegroundColor', [0.7 0.2 0.1], 'String', info_str);
        end
    end

    function on_click(~, evt)
        click_t = evt.IntersectionPoint(1);
        btn     = evt.Button;
        if btn == 1
            if numel(markers) >= n_markers_needed
                % Replace the nearest marker instead of adding a new one
                [~, ri] = min(abs(markers - click_t));
                markers(ri) = click_t;
            else
                markers = sort([markers, click_t]);
            end
            fprintf('[SPLIT] Marker set at %.2fs\n', click_t);
        elseif btn == 3
            if ~isempty(markers)
                [~, ri] = min(abs(markers - click_t));
                fprintf('[SPLIT] Marker at %.2fs removed\n', markers(ri));
                markers(ri) = [];
            end
        end
        redraw();
    end

    function clear_markers()
        markers = [];
        redraw();
    end

    function reset_suggested()
        markers = sort(suggested_t(:)');
        if numel(markers) > n_markers_needed
            markers = markers(1:n_markers_needed);
        end
        redraw();
    end

    function do_confirm()
        if numel(markers) ~= n_markers_needed
            set(status_txt, 'ForegroundColor', [0.8 0.1 0.1], ...
                'String', sprintf('Cannot confirm: need exactly %d marker(s), have %d.', ...
                n_markers_needed, numel(markers)));
            return;
        end
        setappdata(0, 'smp_combined_split_tmp', sort(markers));
        delete(fig);
    end

    function do_skip()
        setappdata(0, 'smp_combined_split_tmp', 'SKIP');
        delete(fig);
    end

    function on_close(~,~)
        if ~isappdata(0, 'smp_combined_split_tmp')
            setappdata(0, 'smp_combined_split_tmp', []);
        end
        delete(fig);
    end
end