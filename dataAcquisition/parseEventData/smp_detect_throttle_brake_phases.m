function segments = smp_detect_throttle_brake_phases(lap)
% SMP_DETECT_THROTTLE_BRAKE_PHASES Auto-detect throttle-brake segments in a lap
%
% USAGE:
%   segments = smp_detect_throttle_brake_phases(lap)
%
% INPUT:
%   lap      (struct) Lap struct with channels, including:
%            .channels.Throttle_Pedal (%)
%            .channels.Brake_Pressure_Front (bar)
%            .channels.Distance (m)
%
% OUTPUT:
%   segments (struct array) Detected segments — one per full-throttle straight
%     .segment_idx         scalar
%     .segment_name        (e.g., 'Segment_01')
%     .distance_start      (m) throttle application point coming out of braking
%     .distance_end        (m) next throttle application point (start of next segment)
%     .brake_marker        (m) distance where throttle drops to 0% (throttle-off point / end of full-throttle phase)
%
% SEGMENT DEFINITION:
%   A segment runs from when the driver first applies throttle (0%->1%).
%   A candidate is only accepted if:
%     (1) throttle reaches >=98.5% within the interval before it drops to 0%, AND
%     (2) brake is applied (>=5 bar) within 200 m of that throttle drop to 0%.
%   Segment runs to the distance_start of the next accepted segment.

% Validate required channels
if ~isfield(lap, 'channels')
    error('Lap struct missing .channels field');
end

if ~isfield(lap.channels, 'Distance')
    error('Lap missing Distance channel');
end

% --- Get distance as the master axis ---
distance = lap.channels.Distance.dist;
if isempty(distance)
    distance = lap.channels.Distance.data;
end
distance = distance(:);

if numel(distance) < 2
    error('Distance channel has fewer than 2 samples — lap slice may be corrupt or too short to analyse.');
end

% --- Align throttle onto distance axis ---
if ~isfield(lap.channels, 'Throttle_Pedal')
    warning('Lap missing Throttle_Pedal channel - using zero throttle');
    throttle = zeros(size(distance));
elseif numel(lap.channels.Throttle_Pedal.dist) < 2
    warning('Throttle_Pedal channel has fewer than 2 samples after lap slice - using zero throttle');
    throttle = zeros(size(distance));
else
    throttle = interp1(lap.channels.Throttle_Pedal.dist(:), ...
                       lap.channels.Throttle_Pedal.data(:), ...
                       distance, 'linear', 'extrap');
end

% --- Align brake onto distance axis ---
if ~isfield(lap.channels, 'Brake_Pressure_Front')
    warning('Lap missing Brake_Pressure_Front channel - using zero brake');
    brake = zeros(size(distance));
elseif numel(lap.channels.Brake_Pressure_Front.dist) < 2
    warning('Brake_Pressure_Front channel has fewer than 2 samples after lap slice - using zero brake');
    brake = zeros(size(distance));
else
    brake = interp1(lap.channels.Brake_Pressure_Front.dist(:), ...
                    lap.channels.Brake_Pressure_Front.data(:), ...
                    distance, 'linear', 'extrap');
end

% Clamp to physical range
throttle = max(0, min(100, throttle));
brake    = max(0, brake);

brake_threshold      = 72.5;  % psi — minimum pressure to count as real braking (≈5 bar)
brake_search_dist_m  = 200;   % m  — how far after throttle-off to look for braking

%% Step 1: Find all throttle rising edges (0% -> >=1%)
throttle_off    = throttle < 1.0;
rising_edge_idx = find(throttle_off(1:end-1) & ~throttle_off(2:end)) + 1;

%% Step 2: Find all throttle falling edges (>=1% -> 0%)
falling_edge_idx = find(~throttle_off(1:end-1) & throttle_off(2:end)) + 1;

%% Step 3: Qualify each rising edge as a segment
% New definition:
%   (1) throttle must reach >=98.5% before it next drops to 0%
%   (2) within 200m after that drop, brake must reach >=5 bar
% Pre-allocate as empty struct array with correct fields
segments = struct('segment_idx',    {}, ...
                  'segment_name',   {}, ...
                  'distance_start', {}, ...
                  'distance_end',   {}, ...
                  'brake_marker',   {});
seg_count = 0;

for e = 1:length(rising_edge_idx)
    start_idx = rising_edge_idx(e);

    % --- Find the NEXT falling edge after this rising edge ---
    next_fall = falling_edge_idx(falling_edge_idx > start_idx);
    if isempty(next_fall)
        continue  % throttle never dropped again — can't validate
    end
    off_idx = next_fall(1);  % first throttle-off after this application

    % Rule 1: throttle must reach >=98.5% between rising edge and drop
    if max(throttle(start_idx:off_idx)) < 98.5
        continue
    end

    % Rule 2: brake must be applied within 200 m of the throttle drop
    off_dist     = distance(off_idx);
    search_limit = off_dist + brake_search_dist_m;
    brake_window = brake(off_idx : end);
    dist_window  = distance(off_idx : end);

    in_range_mask = dist_window <= search_limit;
    brake_in_range = brake_window(in_range_mask);
    dist_in_range  = dist_window(in_range_mask);

    if isempty(brake_in_range) || max(brake_in_range) < brake_threshold
        continue
    end

    % Marker = where throttle dropped to 0% (falling edge after full-throttle phase)
    % The 200 m brake check above is a silent qualification gate only.
    brake_marker  = distance(off_idx);

    % Segment ends at sample before next rising edge (filled in after loop)
    if e < length(rising_edge_idx)
        end_idx = rising_edge_idx(e + 1) - 1;
    else
        end_idx = length(distance);
    end

    % Record segment
    seg_count = seg_count + 1;
    segments(end+1).segment_idx    = seg_count;
    segments(end  ).segment_name   = sprintf('Segment_%02d', seg_count);
    segments(end  ).distance_start = distance(start_idx);
    segments(end  ).distance_end   = distance(end_idx);
    segments(end  ).brake_marker   = brake_marker;
end

fprintf('Found %d throttle-apply events, %d qualified segments\n', ...
        length(rising_edge_idx), seg_count);

if seg_count == 0
    warning('No segments detected. Check throttle/brake channels and thresholds.');
    return;
end

%% Step 4: Fix distance_end — each segment ends where the NEXT accepted segment starts
for s = 1:seg_count - 1
    segments(s).distance_end = segments(s+1).distance_start;
end
% Last segment: keep its distance_end as-is (end of lap)

end
