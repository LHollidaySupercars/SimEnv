%% CHECK_SCALING  Verify channel scaling and time axis are correct.
%
% Run this after loading a session:
  session = SMP2.XMP.channels{end};
%   check_scaling

% =========================================================
%  CONFIG — edit these
% =========================================================
SPEED_CHANNEL    = 'Trip_Distance';     % channel to plot
LAP_TIME_CHANNEL = 'Running_Lap_Time'; % used to measure true lap duration
EXPECTED_LAP_S   = 90;                 % expected lap time in seconds

% =========================================================
%  1. TIME AXIS SANITY
% =========================================================
fprintf('\n=== TIME AXIS CHECK ===\n');

ch = session.(SPEED_CHANNEL);
t  = ch.time ;
dt = median(diff(t));
implied_hz = 1 / dt;

fprintf('Channel          : %s\n',   ch.raw_name);
fprintf('Stored sample_rate field : %.4g Hz\n', ch.sample_rate);
fprintf('Implied Hz from time vec : %.4g Hz  (1 / median dt)\n', implied_hz);
fprintf('Time axis range  : %.4f s  →  %.4f s\n', t(1), t(end));
fprintf('Total duration   : %.2f s  (%.2f min)\n', t(end)-t(1), (t(end)-t(1))/60);
fprintf('Num samples      : %d\n', numel(t));

if abs(implied_hz - ch.sample_rate) / max(ch.sample_rate, 1) > 0.01
    fprintf('[WARN] Implied Hz differs from stored sample_rate by >1%%\n');
    fprintf('       Likely cause: time vector built with wrong sample_rate\n');
else
    fprintf('[OK]   sample_rate matches time vector spacing\n');
end

% =========================================================
%  2. RUNNING LAP TIME — units check
% =========================================================
fprintf('\n=== RUNNING LAP TIME CHECK ===\n');

if isfield(session, LAP_TIME_CHANNEL)
    rlt = session.(LAP_TIME_CHANNEL);
else
    % case-insensitive search
    fn = fieldnames(session);
    match = fn(strcmpi(fn, LAP_TIME_CHANNEL));
    if isempty(match)
        fprintf('[SKIP] Channel "%s" not found.\n', LAP_TIME_CHANNEL);
        rlt = [];
    else
        rlt = session.(match{1});
    end
end

if ~isempty(rlt)
    fprintf('Channel          : %s\n',   rlt.raw_name);
    fprintf('Units field      : "%s"\n', rlt.units);
    fprintf('Min value        : %.4g\n', min(rlt.data));
    fprintf('Max value        : %.4g\n', max(rlt.data));
    fprintf('Median non-zero  : %.4g\n', median(rlt.data(rlt.data > 0)));

    % Find first reset (drop > 5 in raw units)
    drlt     = diff(rlt.data);
    resets   = find(drlt < -5);
    if ~isempty(resets)
        raw_lap_duration = rlt.data(resets(1));
        fprintf('\nFirst lap reset at sample %d\n', resets(1));
        fprintf('Raw value at reset       : %.4g  (units: %s)\n', raw_lap_duration, rlt.units);
        fprintf('If units are seconds     : %.2f s\n', raw_lap_duration);
        fprintf('If units are ms          : %.2f s\n', raw_lap_duration / 1000);
        fprintf('Expected lap time        : %.0f s\n', EXPECTED_LAP_S);

        err_s  = abs(raw_lap_duration        - EXPECTED_LAP_S);
        err_ms = abs(raw_lap_duration / 1000 - EXPECTED_LAP_S);
        if err_ms < err_s
            fprintf('[CONCLUSION] Units are likely MILLISECONDS (divide by 1000)\n');
        else
            fprintf('[CONCLUSION] Units are likely SECONDS (no conversion needed)\n');
        end
    else
        fprintf('[WARN] No resets detected in %s (threshold > 5 raw units)\n', LAP_TIME_CHANNEL);
        fprintf('       Try a larger reset_threshold or check channel name\n');
    end
end

% =========================================================
%  3. SPEED SANITY
% =========================================================
fprintf('\n=== SPEED CHANNEL CHECK ===\n');
fprintf('Channel          : %s\n',   ch.raw_name);
fprintf('Units field      : "%s"\n', ch.units);
fprintf('Min value        : %.2f\n', min(ch.data));
fprintf('Max value        : %.2f\n', max(ch.data));
fprintf('Mean value       : %.2f\n', mean(ch.data));
fprintf('Median value     : %.2f\n', median(ch.data));

if max(ch.data) > 100 && max(ch.data) < 400
    fprintf('[OK]   Max speed %.0f looks like km/h\n', max(ch.data));
elseif max(ch.data) > 50 && max(ch.data) < 250
    fprintf('[OK]   Max speed %.0f could be km/h or mph\n', max(ch.data));
elseif max(ch.data) < 100
    fprintf('[CHECK] Max speed %.2f — could be m/s (x3.6 = %.0f km/h)\n', ...
        max(ch.data), max(ch.data)*3.6);
else
    fprintf('[WARN] Unexpected max speed: %.2f %s\n', max(ch.data), ch.units);
end

% =========================================================
%  4. PLOT — speed vs time with lap markers
% =========================================================
fprintf('\n=== PLOTTING ===\n');

figure('Color','white','Position',[100 100 1000 400]);
ax = axes; hold(ax,'on');

plot(ax, t, ch.data, 'Color',[0.0 0.27 0.68], 'LineWidth', 1.2);

% Overlay lap reset markers using Running Lap Time
if ~isempty(rlt) && ~isempty(resets)
    % Map reset sample indices to the speed channel time axis
    reset_times = rlt.time(resets);
    for r = 1:numel(reset_times)
        xline(ax, reset_times(r), '--r', 'Alpha', 0.6, 'LineWidth', 1);
    end
    fprintf('Plotted %d lap boundary markers (red dashed)\n', numel(resets));

    % Print detected lap durations
    fprintf('\nDetected lap durations from Running Lap Time:\n');
    lap_starts = [rlt.time(1); rlt.time(resets+1)];
    lap_ends   = [rlt.time(resets); rlt.time(end)];
    for r = 1:numel(lap_starts)
        dur_s = lap_ends(r) - lap_starts(r);
        fprintf('  Lap %2d : %.2f s  (%.0f:%04.1f)\n', r, dur_s, floor(dur_s/60), mod(dur_s,60));
    end
end

xlabel(ax, 'Session Time (s)');
ylabel(ax, sprintf('%s [%s]', ch.raw_name, ch.units));
title(ax, sprintf('Speed vs Session Time — %s', SPEED_CHANNEL), 'FontWeight','bold');
grid(ax,'on');
box(ax,'off');

fprintf('\nDone. Check the plot and the lap durations above.\n');
fprintf('If lap durations look wrong, adjust EXPECTED_LAP_S or check units.\n\n');