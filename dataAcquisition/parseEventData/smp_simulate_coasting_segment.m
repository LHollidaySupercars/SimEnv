function [lap_modified, fuel_saved, time_penalty, details] = ...
    smp_simulate_coasting_segment(lap, segment, coasting_point, varargin)
% SMP_SIMULATE_COASTING_SEGMENT  Simulate a fuel-saving coast in one segment
%
% USAGE:
%   [lap_mod, fuel_saved, time_penalty, details] = ...
%       smp_simulate_coasting_segment(lap, segment, coasting_point, ...
%                                     'accel', -3.194, 'fuel_rate', 0.0025)
%
% INPUTS:
%   lap            (struct) Lap channels with .dist and .data fields
%   segment        (struct) .brake_marker, .distance_start, .distance_end
%   coasting_point (double) m before brake_marker to start coast (negative,
%                           e.g. -80 = start coasting 80 m before brake marker)
%
% OPTIONAL:
%   accel          (double) Coast deceleration m/s², negative  [default: -11.5/3.6]
%   fuel_rate      (double) Normal driving fuel rate kg/s       [default: 0.0025]
%
% OUTPUTS:
%   lap_modified   (struct) Lap with Ground_Speed.data replaced in coast zone (km/h)
%   fuel_saved     (double) kg saved (fuel_rate * original time in coast zone)
%   time_penalty   (double) extra seconds in coast zone (positive = slower)
%   details        (struct) diagnostic fields:
%     .coasting_start_dist  m from lap start
%     .coasting_end_dist    m (= brake_marker — fixed rejoin)
%     .v0_kmh               speed at coast start
%     .v_at_marker_kmh      coasted speed arriving at brake marker
%     .dt_original_sec      original time from coast_start → brake_marker
%     .dt_coasted_sec       coasted  time from coast_start → brake_marker
%     .fail_reason          '' on success, message string on failure
%
% PHYSICS MODEL:
%   Peak speed  = highest speed in [distance_start, distance_end]
%   Coast zone  = [d_peak_speed - abs(coasting_point), d_peak_speed]
%   v_coast(d)  = sqrt(max(0, v0² + 2·accel·(d - d_coast_start)))
%   Time penalty = integral(1/v_coast) - integral(1/v_orig) over coast zone
%   Fuel saved   = fuel_rate × original time in coast zone
%   After peak speed point: original speed trace resumes (braking unchanged).

%% --- Parse inputs --------------------------------------------------------
p = inputParser;
addParameter(p, 'accel',     -11.5/3.6, @isnumeric);
addParameter(p, 'fuel_rate',  0.0025,   @isnumeric);
parse(p, varargin{:});
accel     = p.Results.accel;
fuel_rate = p.Results.fuel_rate;

assert(accel < 0, 'accel must be negative (deceleration)');
assert(fuel_rate > 0, 'fuel_rate must be positive');

%% --- 1. Build master distance axis + speed ------------------------------
distance = lap.channels.Distance.dist(:);
if isempty(distance)
    distance = lap.channels.Distance.data(:);
end

speed_raw = lap.channels.Ground_Speed.data(:);
dist_spd  = lap.channels.Ground_Speed.dist(:);
speed_kmh = interp1(dist_spd, speed_raw, distance, 'linear', 'extrap');
speed_ms  = max(0, speed_kmh / 3.6);

%% --- 2. Synthesise time array (integrate dd/v over distance) ------------
dd       = [0; diff(distance)];
v_safe   = max(speed_ms, 0.5);   % avoid div/0 at standstill
time_arr = cumsum(dd ./ v_safe);

%% --- 3. Find peak speed in sector & set coasting start -----------------
% Peak speed = highest point in [distance_start, distance_end]
seg_mask = distance >= segment.distance_start & distance <= segment.distance_end;
if ~any(seg_mask)
    error('COAST_FAIL:noseg', 'No distance samples found within segment bounds.');
end
[~, peak_rel]  = max(speed_ms(seg_mask));
seg_dist       = distance(seg_mask);
d_peak_speed   = seg_dist(peak_rel);

% coasting_point is the distance before peak speed to start coasting (always positive after abs())
d_coast_start = d_peak_speed - abs(coasting_point);

if d_coast_start < distance(1)
    error('COAST_FAIL:range', ...
          'Coasting start (%.1f m) is before lap data start (%.1f m). Reduce coasting distance or check preceding lap stitch.', ...
          d_coast_start, distance(1));
end
if d_coast_start >= d_peak_speed
    error('COAST_FAIL:range', ...
          'Coasting start (%.1f m) must be before peak speed point (%.1f m).', ...
          d_coast_start, d_peak_speed);
end

v0_ms = interp1(distance, speed_ms, d_coast_start, 'pchip');

%% --- 4. Fine grid: coast start → local speed minimum (find natural rejoin) ------
% Coasting continues past d_peak_speed into the braking zone.
% We search up to the local speed minimum after the peak (the corner apex),
% not just to segment.distance_end which can be mid-braking zone.
post_peak  = distance > d_peak_speed;
pk_dist    = distance(post_peak);
pk_spd     = speed_ms(post_peak);
spd_diff   = diff(pk_spd);
min_rel    = find(spd_diff >= 0, 1);   % first non-decreasing = local min
if ~isempty(min_rel) && min_rel > 1
    d_seg_end = pk_dist(min_rel);
else
    d_seg_end = segment.distance_end;
end
% Safety cap: don't search more than 600 m past the peak
d_seg_end = min(d_seg_end, d_peak_speed + 600);
n_fine    = 8000;
d_fine    = linspace(d_coast_start, d_seg_end, n_fine)';
s_fine    = d_fine - d_coast_start;

v_coast_sq  = v0_ms^2 + 2 * accel * s_fine;
v_orig_fine = max(0, interp1(distance, speed_ms, d_fine, 'pchip', 'extrap'));
v_coast_fine = sqrt(max(0, v_coast_sq));

% Rejoin: original brakes hard from v_peak, plummeting below the coasting
% trace. Before peak v_orig > v_coast; rejoin is the first point past the
% peak where v_orig drops back down to v_coast level (v_orig <= v_coast).
past_peak_mask = d_fine > d_peak_speed;
intersect_mask = past_peak_mask & (v_coast_sq <= 0 | v_orig_fine <= v_coast_fine);

details.fail_reason = '';
if ~any(intersect_mask)
    details.fail_reason = sprintf( ...
        'No rejoin before segment end (%.1f m): original (%.1f km/h) still above coast (%.1f km/h). Try larger coasting distance.', ...
        d_seg_end, v_orig_fine(end)*3.6, v_coast_fine(end)*3.6);
    error('COAST_FAIL:nointersect', '%s', details.fail_reason);
end

idx_rejoin = find(intersect_mask, 1);
d_rejoin   = d_fine(idx_rejoin);

% Guard: coast speed must not hit zero before rejoin
if any(v_coast_sq(1:idx_rejoin) <= 0)
    d_zero = d_fine(find(v_coast_sq <= 0, 1));
    details.fail_reason = sprintf( ...
        'Speed reaches 0 at %.1f m before rejoining. Start coasting later.', d_zero);
    error('COAST_FAIL:speedzero', '%s', details.fail_reason);
end

%% --- 5. Time in coast zone (coast_start → rejoin) -----------------------
t0            = interp1(distance, time_arr, d_coast_start, 'pchip');
t_rejoin_orig = interp1(distance, time_arr, d_rejoin,      'pchip');
dt_orig       = max(0, t_rejoin_orig - t0);

d_coast_zone = d_fine(1:idx_rejoin);
v_coast_zone = v_coast_fine(1:idx_rejoin);
dt_coasted   = trapz(d_coast_zone, 1 ./ max(v_coast_zone, 0.1));

%% --- 6. Fuel & time delta -----------------------------------------------
% Fuel only saved over full-throttle phase [coast_start, d_peak_speed].
% In the braking zone throttle is off regardless — no extra fuel saving.
d_fuel_end   = min(d_rejoin, d_peak_speed);
t_fuel_end   = interp1(distance, time_arr, d_fuel_end, 'pchip');
dt_fuel_zone = max(0, t_fuel_end - t0);

% Normal fuel burned in zone: integrate actual fuel-flow channel (g/s→kg/s)
% over the time the car normally spends in [coast_start, d_fuel_end].
% If channel absent, fall back to fuel_rate as net savings rate (original behaviour).
fuel_used_normal = NaN;
ff_ch_name = smp_find_fuel_channel(lap);
if ~isempty(ff_ch_name)
    ff_ch   = lap.channels.(ff_ch_name);
    ff_dist = ff_ch.dist(:);
    ff_kgs  = max(0, ff_ch.data(:) / 1000);          % g/s → kg/s, clamp negative
    ff_at_d = interp1(ff_dist, ff_kgs, distance, 'linear', 'extrap');
    ff_at_d = max(0, ff_at_d);                        % clamp extrapolation artefacts
    zone_mask = distance >= d_coast_start & distance <= d_fuel_end;
    if sum(zone_mask) >= 2
        fuel_used_normal = trapz(time_arr(zone_mask), ff_at_d(zone_mask));
    end
end

if ~isnan(fuel_used_normal)
    % Channel available: saved = (normal burn) − (idle burn while coasting)
    fuel_used_idle = fuel_rate * dt_fuel_zone;
    fuel_saved     = max(0, fuel_used_normal - fuel_used_idle);
else
    % Fallback: treat fuel_rate as the net saving rate per second of coasting
    fuel_saved = fuel_rate * dt_fuel_zone;
end
time_penalty = dt_coasted - dt_orig;        % positive = slower

%% --- 7. Modified speed trace on original distance grid ------------------
speed_modified_ms = speed_ms;
coast_mask = distance >= d_coast_start & distance < d_rejoin;
if any(coast_mask)
    s_zone = distance(coast_mask) - d_coast_start;
    speed_modified_ms(coast_mask) = sqrt(max(0, v0_ms^2 + 2*accel*s_zone));
end
% After rejoin: original speed resumes

lap_modified = lap;
lap_modified.channels.Ground_Speed.data = speed_modified_ms * 3.6;  % km/h
lap_modified.channels.Ground_Speed.dist = distance;

%% --- 8. Details ---------------------------------------------------------
v_at_rejoin_ms = v_coast_fine(idx_rejoin);

details.coasting_start_dist = d_coast_start;
details.coasting_end_dist   = d_rejoin;
details.peak_speed_dist     = d_peak_speed;
details.v0_kmh              = v0_ms * 3.6;
details.v_at_marker_kmh     = v_at_rejoin_ms * 3.6;
details.dt_original_sec     = dt_orig;
details.dt_coasted_sec      = dt_coasted;

end
