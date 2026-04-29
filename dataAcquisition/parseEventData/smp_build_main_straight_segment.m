function segment = smp_build_main_straight_segment(lap, first_timed_segment, preceding_lap)
% SMP_BUILD_MAIN_STRAIGHT_SEGMENT  Build a Segment_00 covering the main straight.
%
% The main straight segment spans from the last full-throttle-on point before
% the finish line all the way to where the driver brakes for Turn 1.
%
%   brake_marker / distance_end: derived from the TIMED LAP (first_timed_segment)
%       — the throttle-off point of the first qualifying full-throttle zone is
%         the T1 brake point, which is always available.
%
%   distance_start: derived from the PRECEDING LAP (optional)
%       — the last qualifying throttle-on point before the finish line, expressed
%         as a negative distance offset (metres before the start/finish line).
%       — if preceding_lap is absent or no qualifying zone is found, falls back
%         to distance_start = 0 (i.e. the segment starts at the finish line).
%
% Inputs:
%   lap                 - timed lap struct (channels with .data / .dist)
%   first_timed_segment - first segment from smp_detect_throttle_brake_phases
%                         (provides brake_marker and distance_end)
%   preceding_lap       - (optional) lap struct from smp_load_preceding_lap.
%                         Pass [] to skip.
%
% Output:
%   segment  - struct matching smp_detect_throttle_brake_phases format, or []
%              if the timed lap provides no usable first segment.

    segment = [];

    if isempty(first_timed_segment)
        fprintf('[smp_build_main_straight_segment] No timed segment provided — cannot build S01.\n');
        return;
    end

    % ------------------------------------------------------------------
    %  brake_marker and distance_end come directly from the timed lap's
    %  first segment.  These are always available.
    % ------------------------------------------------------------------
    d_brake  = first_timed_segment.brake_marker;      % throttle-off, T1 entry
    d_end    = first_timed_segment.distance_start;    % where timed-lap S02 begins

    % ------------------------------------------------------------------
    %  distance_start — try the preceding lap first.
    %  Falls back to 0 (start/finish line) if not available.
    % ------------------------------------------------------------------
    d_start = 0;   % default: segment starts at the finish line

    if nargin >= 3 && ~isempty(preceding_lap) && isfield(preceding_lap, 'channels')

        dist_candidates = {'Distance', 'Odometer', 'Lap_Distance'};
        dist_ch_name    = '';
        for k = 1:numel(dist_candidates)
            if isfield(preceding_lap.channels, dist_candidates{k})
                dist_ch_name = dist_candidates{k};
                break;
            end
        end

        if ~isempty(dist_ch_name)
            dist_raw = preceding_lap.channels.(dist_ch_name).dist;
            if isempty(dist_raw)
                dist_raw = preceding_lap.channels.(dist_ch_name).data;
            end
            dist_raw   = dist_raw(:);
            % Offset so that the finish line = 0; preceding lap = negative
            dist_offset = dist_raw - dist_raw(end);

            throttle_raw = get_channel(preceding_lap, {'Throttle_Pedal','Throttle'}, dist_raw);
            brake_raw    = get_channel(preceding_lap, {'Brake_Pressure_Front','Brake'}, dist_raw);

            if ~isempty(throttle_raw)
                if isempty(brake_raw), brake_raw = zeros(size(dist_offset)); end
                throttle_raw = max(0, min(100, throttle_raw));
                brake_raw    = max(0, brake_raw);

                brake_threshold     = 72.5;  % psi — minimum pressure to count as real braking (≈5 bar)
                brake_search_dist_m = 200;

                throttle_off     = throttle_raw < 1.0;
                rising_edge_idx  = find(throttle_off(1:end-1) & ~throttle_off(2:end)) + 1;
                falling_edge_idx = find(~throttle_off(1:end-1) & throttle_off(2:end)) + 1;

                last_valid_rising = [];
                for e = 1:length(rising_edge_idx)
                    start_idx = rising_edge_idx(e);
                    next_fall = falling_edge_idx(falling_edge_idx > start_idx);
                    if isempty(next_fall), continue; end
                    off_idx = next_fall(1);

                    if max(throttle_raw(start_idx:off_idx)) < 98.5, continue; end

                    off_dist   = dist_offset(off_idx);
                    in_range   = dist_offset(off_idx:end) <= off_dist + brake_search_dist_m;
                    brake_win  = brake_raw(off_idx:end);
                    if isempty(brake_win(in_range)) || max(brake_win(in_range)) < brake_threshold
                        continue;
                    end

                    last_valid_rising = start_idx;
                end

                if ~isempty(last_valid_rising)
                    d_start = dist_offset(last_valid_rising);   % negative value
                    fprintf('[smp_build_main_straight_segment] Preceding lap throttle-on at %.1f m.\n', d_start);
                else
                    fprintf('[smp_build_main_straight_segment] No qualifying zone in preceding lap — using finish line as start.\n');
                end
            end
        end
    else
        fprintf('[smp_build_main_straight_segment] No preceding lap — segment starts at finish line (0 m).\n');
    end

    % ------------------------------------------------------------------
    %  Assemble segment
    % ------------------------------------------------------------------
    segment.segment_idx    = 0;              % caller renumbers to 1
    segment.segment_name   = 'Segment_01';
    segment.distance_start = d_start;
    segment.distance_end   = d_end;
    segment.brake_marker   = d_brake;

    fprintf('[smp_build_main_straight_segment] S01: %.1f m → %.1f m  (brake marker at %.1f m)\n', ...
        d_start, d_end, d_brake);
end


% -----------------------------------------------------------------------
function vals = get_channel(lap, name_candidates, dist_axis)
    vals = [];
    for k = 1:numel(name_candidates)
        nm = name_candidates{k};
        if isfield(lap.channels, nm)
            ch = lap.channels.(nm);
            cd = ch.dist(:);
            cv = ch.data(:);
            if isempty(cd) || numel(cd) < 2, continue; end
            vals = interp1(cd, cv, dist_axis, 'linear', 'extrap');
            return;
        end
    end
end
