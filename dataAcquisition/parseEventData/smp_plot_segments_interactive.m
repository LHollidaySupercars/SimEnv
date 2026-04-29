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
fig = figure('Name', 'Segment Review — drag lines to adjust, then click Accept', ...
             'NumberTitle', 'off', ...
             'Units', 'normalized', 'Position', [0.04 0.08 0.92 0.82]);

ax1 = subplot(2,1,1);
plot(distance, throttle, 'Color', [0.15 0.15 0.15], 'LineWidth', 1);
ylabel('Throttle (%)');
ylim([-5 105]);
grid on; hold on;
title(sprintf('%d segments detected  |  Green dashed = throttle-on  |  Drag to adjust', ...
      length(segments)), 'FontSize', 9);

ax2 = subplot(2,1,2);
plot(distance, brake, 'Color', [0.15 0.35 0.75], 'LineWidth', 1);
ylabel('Brake Pressure (psi)');
xlabel('Distance (m)');
grid on; hold on;

linkaxes([ax1 ax2], 'x');

col_start = [0.08 0.72 0.08];   % green  — throttle-on / sector start
col_end   = [0.08 0.72 0.08];   % green  — final sector end (same colour, solid)

n_seg = length(segments);

% Line handle storage: rows = segments, cols = [ax1, ax2]
start_lines = gobjects(n_seg, 2);
label_texts = gobjects(n_seg, 1);   % labels only on ax1

for s = 1:n_seg
    xs = segments(s).distance_start;

    for a = 1:2
        ax = [ax1 ax2];
        ax = ax(a);
        yl = ylim(ax);

        sl = line(ax, [xs xs], yl, ...
                  'Color', col_start, 'LineWidth', 1.8, 'LineStyle', '--', ...
                  'HitTest', 'on', 'PickableParts', 'all');
        sl.ButtonDownFcn = @(~,~) startDrag(fig, 'start', s);
        start_lines(s, a) = sl;
    end

    % Segment label — top of ax1 only
    yl1 = ylim(ax1);
    label_texts(s) = text(ax1, xs + 3, yl1(2) * 0.93, sprintf('S%02d', s), ...
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
fig.UserData = struct( ...
    'segments',    segments, ...
    'start_lines', start_lines, ...
    'end_lines',   end_lines, ...
    'end_label',   end_label, ...
    'label_texts', label_texts, ...
    'ax1', ax1, 'ax2', ax2, ...
    'dragging', false, ...
    'drag_type', '', ...
    'drag_seg',  0);

%% Accept button
uicontrol('Style', 'pushbutton', 'String', 'Accept', ...
          'Units', 'normalized', 'Position', [0.44 0.005 0.12 0.038], ...
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
    ud            = fig.UserData;
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
        ud.start_lines(s, 1).XData = [new_x new_x];
        ud.start_lines(s, 2).XData = [new_x new_x];
        % Move label
        ud.label_texts(s).Position(1) = new_x + 3;

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
