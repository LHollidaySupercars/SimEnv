function lap_stitched = smp_stitch_preceding_lap(preceding_lap, timed_lap)
% SMP_STITCH_PRECEDING_LAP  Prepend the preceding lap onto the timed lap.
%
% The preceding lap is expressed in negative distance (metres before the
% start/finish line = 0).  The timed lap starts at 0.  The result is a
% single lap struct whose distance axis runs from -(preceding lap length)
% through to the end of the timed lap, with no gap at the join.
%
% Only Ground_Speed and Distance channels are stitched — these are the
% only ones needed by smp_simulate_coasting_segment.
%
% Inputs:
%   preceding_lap  - lap struct from smp_load_preceding_lap
%   timed_lap      - qualifying lap struct
%
% Output:
%   lap_stitched   - combined lap struct with .channels.Distance and
%                    .channels.Ground_Speed spanning negative → positive dist.
%                    Returns timed_lap unchanged if stitching is not possible.

    lap_stitched = timed_lap;   % safe default

    if isempty(preceding_lap) || ~isfield(preceding_lap, 'channels')
        return;
    end

    % ------------------------------------------------------------------
    %  Timed lap: distance and speed
    % ------------------------------------------------------------------
    t_dist = timed_lap.channels.Distance.dist(:);
    if isempty(t_dist)
        t_dist = timed_lap.channels.Distance.data(:);
    end
    t_spd_raw  = timed_lap.channels.Ground_Speed.data(:);
    t_spd_dist = timed_lap.channels.Ground_Speed.dist(:);
    t_spd = interp1(t_spd_dist, t_spd_raw, t_dist, 'linear', 'extrap');

    % ------------------------------------------------------------------
    %  Preceding lap: distance and speed, offset to negative values
    % ------------------------------------------------------------------
    dist_candidates = {'Distance', 'Odometer', 'Lap_Distance'};
    p_dist_raw = [];
    for k = 1:numel(dist_candidates)
        nm = dist_candidates{k};
        if isfield(preceding_lap.channels, nm)
            p_dist_raw = preceding_lap.channels.(nm).dist(:);
            if isempty(p_dist_raw)
                p_dist_raw = preceding_lap.channels.(nm).data(:);
            end
            break;
        end
    end

    if isempty(p_dist_raw)
        fprintf('[smp_stitch_preceding_lap] No distance channel in preceding lap — not stitching.\n');
        return;
    end

    % Offset so last point = 0 (= start/finish line)
    p_dist = p_dist_raw - p_dist_raw(end);   % all values <= 0

    % Speed
    p_spd_raw  = preceding_lap.channels.Ground_Speed.data(:);
    p_spd_dist = preceding_lap.channels.Ground_Speed.dist(:);
    % Ground_Speed.dist in preceding lap is in raw (0..lap_length) space
    p_spd = interp1(p_spd_dist, p_spd_raw, p_dist_raw, 'linear', 'extrap');
    p_spd = max(0, p_spd);

    % ------------------------------------------------------------------
    %  Remove any preceding-lap samples that overlap with timed lap
    %  (i.e. dist >= 0 already covered by timed lap)
    % ------------------------------------------------------------------
    keep = p_dist < 0;
    p_dist = p_dist(keep);
    p_spd  = p_spd(keep);

    if isempty(p_dist)
        fprintf('[smp_stitch_preceding_lap] Preceding lap distance all >= 0 — not stitching.\n');
        return;
    end

    % ------------------------------------------------------------------
    %  Concatenate: preceding (negative) then timed (non-negative)
    % ------------------------------------------------------------------
    dist_combined = [p_dist; t_dist];
    spd_combined  = [p_spd;  t_spd];

    % Ensure monotonically increasing distance (handle any tiny overlaps)
    [dist_combined, ui] = unique(dist_combined, 'sorted');
    spd_combined = spd_combined(ui);

    % ------------------------------------------------------------------
    %  Build output struct — mirror timed lap structure
    % ------------------------------------------------------------------
    lap_stitched = timed_lap;

    lap_stitched.channels.Distance.dist = dist_combined;
    lap_stitched.channels.Distance.data = dist_combined;

    lap_stitched.channels.Ground_Speed.dist = dist_combined;
    lap_stitched.channels.Ground_Speed.data = spd_combined;

    fprintf('[smp_stitch_preceding_lap] Stitched: %.1f m to %.1f m  (%d samples)\n', ...
        dist_combined(1), dist_combined(end), numel(dist_combined));
end
