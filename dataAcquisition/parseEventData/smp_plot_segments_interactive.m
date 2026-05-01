function segments = smp_plot_segments_interactive(lap, segments, preceding_lap)
% SMP_PLOT_SEGMENTS_INTERACTIVE  Review and adjust detected segment boundaries
%
% USAGE:
%   segments = smp_plot_segments_interactive(lap, segments)
%   segments = smp_plot_segments_interactive(lap, segments, preceding_lap)
%
% Shows throttle and brake pressure vs distance with draggable vertical lines:
%   Green dashed  — distance_start (throttle-on, rising edge 0->1%)
%
% Pass preceding_lap to extend the distance axis into negative values so
% that Segment_01 (main straight, pre-finish-line) is visible and draggable.
%
% Drag any line left/right to adjust it. Click Accept (or close) to return
% the updated segments struct.

if nargin < 3, preceding_lap = []; end

if isempty(segments)
    warning('smp_plot_segments_interactive: no segments to display.');
    return
end

%% Build channels on shared distance axis
% If a preceding lap is provided, prepend its data with negative offsets.
distance = lap.channels.Distance.dist(:);
if isempty(distance)
    distance = lap.channels.Distance.data(:);
end

throttle = interp1(lap.channels.Throttle_Pedal.dist(:), ...
                   lap.channels.Throttle_Pedal.data(:), ...
                   distance, 'linear', 'extrap');
throttle = max(0, min(100, throttle));

brake = interp1(lap.channels.Brake_Pressure_Front.dist(:), ...
                lap.channels.Brake_Pressure_Front.data(:), ...
                distance, 'linear', 'extrap');
brake = max(0, brake);

% Prepend preceding lap if available
if ~isempty(preceding_lap) && isfield(preceding_lap, 'channels')
    dist_cands = {'Distance','Odometer','Lap_Distance'};
    p_dist_raw = [];
    for kk = 1:numel(dist_cands)
        nm = dist_cands{kk};
        if isfield(preceding_lap.channels, nm)
            p_dist_raw = preceding_lap.channels.(nm).dist(:);
            if isempty(p_dist_raw), p_dist_raw = preceding_lap.channels.(nm).data(:); end
            break;
        end
    end
    if ~isempty(p_dist_raw)
        p_dist = p_dist_raw - p_dist_raw(end);   % negative offsets
        keep_p = p_dist < 0;
        p_dist = p_dist(keep_p);

        p_thr = interp1(preceding_lap.channels.Throttle_Pedal.dist(:), ...
                        preceding_lap.channels.Throttle_Pedal.data(:), ...
                        p_dist_raw(keep_p), 'linear', 'extrap');
        p_thr = max(0, min(100, p_thr));

        p_brk = interp1(preceding_lap.channels.Brake_Pressure_Front.dist(:), ...
                        preceding_lap.channels.Brake_Pressure_Front.data(:), ...
                        p_dist_raw(keep_p), 'linear', 'extrap');
        p_brk = max(0, p_brk);

        distance = [p_dist;  distance];
        throttle = [p_thr;   throttle];
        brake    = [p_brk;   brake];
    end
end

%% Create figure
lap_time_str = sprintf('%d:%06.3f', floor(lap.lap_time/60), mod(lap.lap_time, 60));
fig = figure('Name', sprintf('Lap %d (%s) — Segment Review — drag lines to adjust, then click Accept', lap.lap_number, lap_time_str), ...
             'NumberTitle', 'off', ...
             'Units', 'normalized', 'Position', [0.04 0.08 0.92 0.82]);

ax1 = subplot(2,1,1);
plot(distance, throttle, 'Color', [0.15 0.15 0.15], 'LineWidth', 1);
ylabel('Throttle (%)');
ylim([-5 105]);
grid on; hold on;
title(sprintf('Lap %d (%s)  |  %d segments detected  |  Green dashed = throttle-on  |  Drag to adjust', ...
      lap.lap_number, lap_time_str, length(segments)), 'FontSize', 9);

ax2 = subplot(2,1,2);
plot(distance, brake, 'Color', [0.15 0.35 0.75], 'LineWidth', 1);
ylabel('Brake Pressure (psi)');
xlabel('Distance (m)');
grid on; hold on;

linkaxes([ax1 ax2], 'x');

col_start = [0.08 0.72 0.08];   % green  — throttle-on / sector start
col_end   = [0.08 0.72 0.08];   % green  — final sector end (same colour, solid)

n_seg = length(segments);

% Line handle storage: cell arrays to allow dynamic add/remove
start_lines = cell(n_seg, 2);
label_texts = cell(n_seg, 1);

for s = 1:n_seg
    xs = segments(s).distance_start;

    for a = 1:2
        axArr = [ax1 ax2];
        curAx = axArr(a);
        yl = ylim(curAx);

        sl = line(curAx, [xs xs], yl, ...
                  'Color', col_start, 'LineWidth', 1.8, 'LineStyle', '--', ...
                  'HitTest', 'on', 'PickableParts', 'all');
        sl.ButtonDownFcn = @(~,~) startDrag(fig, 'start', s);
        start_lines{s, a} = sl;
    end

    % Segment label — top of ax1 only
    yl1 = ylim(ax1);
    label_texts{s} = text(ax1, xs + 3, yl1(2) * 0.93, sprintf('S%02d', s), ...
                          'Color', col_start, 'FontSize', 7.5, 'FontWeight', 'bold', ...
                          'Clipping', 'on');
end

% Draggable end-sector line (green solid) at the end of the last segment
xe = segments(end).distance_end;
end_lines = gobjects(1, 2);
for a = 1:2
    axe = [ax1 ax2];
    axe = axe(a);
    yl = ylim(axe);
    el = line(axe, [xe xe], yl, ...
              'Color', col_end, 'LineWidth', 2.2, 'LineStyle', '-', ...
              'HitTest', 'on', 'PickableParts', 'all');
    el.ButtonDownFcn = @(~,~) startDrag(fig, 'end', 0);
    end_lines(a) = el;
end
yl1 = ylim(ax1);
end_label = text(ax1, xe + 3, yl1(2) * 0.93, 'END', ...
                 'Color', col_end, 'FontSize', 7.5, 'FontWeight', 'bold', ...
                 'Clipping', 'on');

%% Store drag state in UserData
ud           = struct();
ud.segments  = segments;
ud.end_lines = end_lines;
ud.end_label = end_label;
ud.ax1       = ax1;
ud.ax2       = ax2;
ud.dragging  = false;
ud.drag_type = '';
ud.drag_seg  = 0;
ud.add_mode  = false;
fig.UserData = ud;
fig.UserData.start_lines = start_lines;
fig.UserData.label_texts = label_texts;

%% Sector edit buttons
uicontrol('Style', 'pushbutton', 'String', 'Add Sector', ...
          'Units', 'normalized', 'Position', [0.29 0.005 0.12 0.038], ...
          'FontSize', 10, ...
          'BackgroundColor', [0.22 0.44 0.78], 'ForegroundColor', 'white', ...
          'Callback', @(~,~) enableAddMode(fig));

uicontrol('Style', 'pushbutton', 'String', 'Remove Last', ...
          'Units', 'normalized', 'Position', [0.44 0.005 0.12 0.038], ...
          'FontSize', 10, ...
          'BackgroundColor', [0.78 0.30 0.22], 'ForegroundColor', 'white', ...
          'Callback', @(~,~) removeLastSector(fig));

%% Accept button
uicontrol('Style', 'pushbutton', 'String', 'Accept', ...
          'Units', 'normalized', 'Position', [0.59 0.005 0.12 0.038], ...
          'FontSize', 11, 'FontWeight', 'bold', ...
          'BackgroundColor', [0.22 0.68 0.22], 'ForegroundColor', 'white', ...
          'Callback', @(~,~) uiresume(fig));

%% Block until Accept or window closed
uiwait(fig);

if isvalid(fig)
    segments = fig.UserData.segments;
    close(fig);
end

end % main function

%% ── Drag callbacks ────────────────────────────────────────────────────────

function startDrag(fig, drag_type, seg_idx)
    ud = fig.UserData;
    if isfield(ud, 'add_mode') && ud.add_mode, return; end
    ud.dragging   = true;
    ud.drag_type  = drag_type;
    ud.drag_seg   = seg_idx;
    fig.UserData  = ud;
    set(fig, 'WindowButtonMotionFcn', @(f,~) moveDrag(f), ...
             'WindowButtonUpFcn',     @(f,~) stopDrag(f), ...
             'Pointer', 'left');
end

function moveDrag(fig)
    ud = fig.UserData;
    if ~ud.dragging, return; end

    cp    = get(ud.ax1, 'CurrentPoint');
    new_x = cp(1, 1);
    s     = ud.drag_seg;

    if strcmp(ud.drag_type, 'start')
        ud.segments(s).distance_start = new_x;
        % If this segment starts where the previous one ended, keep them linked
        if s > 1
            ud.segments(s-1).distance_end = new_x;
        end
        ud.start_lines{s, 1}.XData = [new_x new_x];
        ud.start_lines{s, 2}.XData = [new_x new_x];
        % Move label
        ud.label_texts{s}.Position(1) = new_x + 3;

    elseif strcmp(ud.drag_type, 'end')
        ud.segments(end).distance_end = new_x;
        ud.end_lines(1).XData = [new_x new_x];
        ud.end_lines(2).XData = [new_x new_x];
        ud.end_label.Position(1) = new_x + 3;
    end

    fig.UserData = ud;
    drawnow limitrate;
end

function stopDrag(fig)
    ud           = fig.UserData;
    ud.dragging  = false;
    fig.UserData = ud;
    set(fig, 'WindowButtonMotionFcn', '', 'WindowButtonUpFcn', '', 'Pointer', 'arrow');
end

%% ── Add / Remove sector callbacks ────────────────────────────────────────

function enableAddMode(fig)
    ud          = fig.UserData;
    ud.add_mode = true;
    fig.UserData = ud;
    set(fig, 'WindowButtonDownFcn', @(f,~) addSectorAtClick(f), 'Pointer', 'crosshair');
    title(ud.ax1, 'Click on the plot to place new sector boundary — press Esc to cancel', ...
          'FontSize', 9, 'Color', [0.22 0.44 0.78]);
end

function addSectorAtClick(fig)
    ud = fig.UserData;
    if ~isfield(ud, 'add_mode') || ~ud.add_mode, return; end

    % Reset add mode immediately
    ud.add_mode  = false;
    fig.UserData = ud;
    set(fig, 'WindowButtonDownFcn', '', 'Pointer', 'arrow');

    % Get click x on ax1
    cp    = get(ud.ax1, 'CurrentPoint');
    new_x = cp(1, 1);

    segs = ud.segments;
    n    = length(segs);

    % Find insertion position (insert a new start line at new_x)
    starts      = [segs.distance_start];
    insert_after = sum(starts < new_x);   % number of segments whose start is left of click

    if insert_after == 0 || insert_after >= n
        % Click was before first segment or after last — nothing sensible to split
        title(ud.ax1, sprintf('%d segments  |  Add Sector: click between existing sector starts', n), ...
              'FontSize', 9, 'Color', 'k');
        return;
    end

    % Split segment(insert_after): its end becomes new_x; new segment covers new_x to old end
    new_seg                = segs(insert_after);
    new_seg.distance_start = new_x;
    new_seg.distance_end   = segs(insert_after).distance_end;
    segs(insert_after).distance_end = new_x;

    % Shift segments after insertion point
    new_n = n + 1;
    new_segs(1:insert_after)     = segs(1:insert_after);
    new_segs(insert_after + 1)   = new_seg;
    new_segs(insert_after+2:new_n) = segs(insert_after+1:n);

    % Re-number all segments
    for s = 1:new_n
        new_segs(s).segment_idx  = s;
        new_segs(s).segment_name = sprintf('Segment_%02d', s);
    end

    % Create new line objects for the inserted sector
    col_start = [0.08 0.72 0.08];
    axes_arr  = [ud.ax1 ud.ax2];
    new_line_handles = cell(1, 2);
    for a = 1:2
        curAx = axes_arr(a);
        yl    = ylim(curAx);
        sl    = line(curAx, [new_x new_x], yl, ...
                     'Color', col_start, 'LineWidth', 1.8, 'LineStyle', '--', ...
                     'HitTest', 'on', 'PickableParts', 'all');
        sl.ButtonDownFcn    = @(~,~) startDrag(fig, 'start', insert_after + 1);
        new_line_handles{a} = sl;
    end

    % Build new start_lines cell array
    sl_old  = ud.start_lines;
    sl_new  = cell(new_n, 2);
    for s = 1:insert_after
        sl_new{s, 1} = sl_old{s, 1};
        sl_new{s, 2} = sl_old{s, 2};
    end
    sl_new{insert_after+1, 1} = new_line_handles{1};
    sl_new{insert_after+1, 2} = new_line_handles{2};
    for s = insert_after+2:new_n
        sl_new{s, 1} = sl_old{s-1, 1};
        sl_new{s, 2} = sl_old{s-1, 2};
        % Rebind drag callback with updated index
        idx = s;
        sl_new{s, 1}.ButtonDownFcn = @(~,~) startDrag(fig, 'start', idx);
        sl_new{s, 2}.ButtonDownFcn = @(~,~) startDrag(fig, 'start', idx);
    end

    % Build new label_texts cell array
    yl1     = ylim(ud.ax1);
    new_lbl = text(ud.ax1, new_x + 3, yl1(2) * 0.93, ...
                   sprintf('S%02d', insert_after + 1), ...
                   'Color', col_start, 'FontSize', 7.5, 'FontWeight', 'bold', ...
                   'Clipping', 'on');
    lt_old  = ud.label_texts;
    lt_new  = cell(new_n, 1);
    for s = 1:insert_after
        lt_new{s} = lt_old{s};
    end
    lt_new{insert_after+1} = new_lbl;
    for s = insert_after+2:new_n
        lt_new{s}        = lt_old{s-1};
        lt_new{s}.String = sprintf('S%02d', s);
    end

    ud.segments    = new_segs;
    ud.start_lines = sl_new;
    ud.label_texts = lt_new;
    fig.UserData   = ud;

    title(ud.ax1, sprintf('%d segments  |  Green dashed = sector start  |  Drag to adjust', new_n), ...
          'FontSize', 9, 'Color', 'k');
end

function removeLastSector(fig)
    ud   = fig.UserData;
    segs = ud.segments;
    n    = length(segs);

    if n <= 1
        return;  % Never remove the last remaining segment
    end

    % Extend second-to-last segment to cover the removed range
    segs(n-1).distance_end = segs(n).distance_end;
    segs = segs(1:n-1);

    % Delete graphical objects for last segment
    try, delete(ud.start_lines{n, 1}); catch, end
    try, delete(ud.start_lines{n, 2}); catch, end
    try, delete(ud.label_texts{n});    catch, end

    ud.start_lines = ud.start_lines(1:n-1, :);
    ud.label_texts = ud.label_texts(1:n-1);
    ud.segments    = segs;
    fig.UserData   = ud;

    title(ud.ax1, sprintf('%d segments  |  Green dashed = sector start  |  Drag to adjust', n-1), ...
          'FontSize', 9, 'Color', 'k');
end
