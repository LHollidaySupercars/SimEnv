function stops = smp_pitstop_detect(SMP)
% SMP_PITSTOP_DETECT  Detect pit stops and tyre changes across all cars.
%
% Usage:
%   stops = smp_pitstop_detect(SMP_filtered)
%
% Inputs:
%   SMP      - filtered SMP struct from smp_filter()
%
% Output:
%   stops - struct keyed by team, one cell per run:
%     stops.(team){r}.pit_lap
%     stops.(team){r}.out_lap
%     stops.(team){r}.stop_duration
%     stops.(team){r}.tyres_changed
%     stops.(team){r}.tyre_change_FL/FR/RL/RR
%     stops.(team){r}.tyre_id_before/after

    % ================================================================
    %  CHANNEL NAME PLACEHOLDERS
    % ================================================================
    CH_AIR_JACK = 'Air_Jack_Switch_Timer';
    CH_TYRE_FL  = 'TPM1S_FL_WS_ID';
    CH_TYRE_FR  = 'TPM1S_FR_WS_ID';
    CH_TYRE_RL  = 'TPM1S_RL_WS_ID';
    CH_TYRE_RR  = 'TPM1S_RR_WS_ID';
    % ================================================================

    MIN_LAP_TIME = 60;
    corners      = {'FL', 'FR', 'RL', 'RR'};
    tyre_chs     = {CH_TYRE_FL, CH_TYRE_FR, CH_TYRE_RL, CH_TYRE_RR};

    stops  = struct();
    teams  = fieldnames(SMP);

    for t = 1:numel(teams)
        tm   = teams{t};
        meta = SMP.(tm).meta;
        n_runs = height(meta);

        stops.(tm) = cell(n_runs, 1);

        for r = 1:n_runs
            fpath = meta.Path{r};
            driver = strtrim(char(string(meta.Driver{r})));
            [~, fname] = fileparts(fpath);

            fprintf('\n[%s] Run %d  —  %s  (%s)\n', tm, r, driver, fname);

            % Read .ld file on demand — don't rely on cached channels
            try
                session = motec_ld_reader(fpath);
            catch ME
                fprintf('  [ERROR] Could not read file: %s\n', ME.message);
                stops.(tm){r} = [];
                continue;
            end

            % Slice laps
            laps = lap_slicer(session, struct());

            if isempty(laps)
                fprintf('  No laps found — skipping\n');
                stops.(tm){r} = [];
                continue;
            end

            % Detect stops
            run_stops = detect_stops(laps, session, ...
                CH_AIR_JACK, corners, tyre_chs, MIN_LAP_TIME, tm);

            stops.(tm){r} = run_stops;
        end
    end
end


% ======================================================================
%  DETECTION LOGIC
% ======================================================================
function stops = detect_stops(laps, channels, CH_AIR_JACK, corners, tyre_chs, MIN_LAP_TIME, tm)

    stops = struct( ...
        'pit_lap',        {}, ...
        'out_lap',        {}, ...
        'stop_duration',  {}, ...
        'tyres_changed',  {}, ...
        'tyre_change_FL', {}, ...
        'tyre_change_FR', {}, ...
        'tyre_change_RL', {}, ...
        'tyre_change_RR', {}, ...
        'team',           {}, ...
        'tyre_id_before', {}, ...
        'tyre_id_after',  {} );
    
    lastStopTime = 0;
    if ~isfield(channels, CH_AIR_JACK)
        fprintf('  [!] %s not found — cannot detect pit stops\n', CH_AIR_JACK);
        return;
    end

    n_laps = numel(laps);
    id_before = struct();
    id_after  = struct();
    changed   = struct();
    n_changed = 0;
    for i = 1:n_laps

        if laps(i).lap_time < MIN_LAP_TIME, continue; end

        jack_vals = vertcat(get_lap_channel(channels.(CH_AIR_JACK), laps(i)));
      
        
        if isempty(jack_vals) || max(jack_vals) <= lastStopTime || (n_laps < (i + 1))
            entry.pit_lap        = i;
            % skip this line due to no beacon being in pit lane
    %         entry.out_lap        = min(i + 1, n_laps);
           
            entry.out_lap        = entry.pit_lap;
            entry.stop_duration  = 0;
            entry.tyres_changed  = 0;
            entry.tyre_change_FL = 0;
            entry.tyre_change_FR = 0;
            entry.tyre_change_RL = 0;
            entry.tyre_change_RR = 0;
            id_before.(corners{1}) = get_lap_scalar(channels.(tyre_chs{1}), laps(i));
            id_before.(corners{2}) = get_lap_scalar(channels.(tyre_chs{2}), laps(i));
            id_before.(corners{3}) = get_lap_scalar(channels.(tyre_chs{3}), laps(i));
            id_before.(corners{4}) = get_lap_scalar(channels.(tyre_chs{4}), laps(i));
            entry.team           = tm;
            entry.tyre_id_before = id_before;
            entry.tyre_id_after  = id_before;
            stops(end+1) = entry; %#ok
            continue
        end
        jack_vals = vertcat(get_lap_channel(channels.(CH_AIR_JACK), laps(i)),...
            get_lap_channel(channels.(CH_AIR_JACK), laps(i+1)));
        stop_duration = max(jack_vals);
        
%         id_before = struct();
%         id_after  = struct();
%         changed   = struct();
%         n_changed = 0;

        for c = 1:4
            corner = corners{c};
            ch     = tyre_chs{c};

            if isfield(channels, ch) && i < n_laps
                id_before.(corner) = get_lap_scalar(channels.(ch), laps(i));
                id_after.(corner)  = get_lap_scalar(channels.(ch), laps(i+1));
                changed.(corner)   = ~isequal(id_before.(corner), id_after.(corner));
                n_changed          = n_changed + changed.(corner);
            else
                id_before.(corner) = NaN;
                id_after.(corner)  = NaN;
                changed.(corner)   = false;
            end
        end

        entry.pit_lap        = i;
        % skip this line due to no beacon being in pit lane
%         entry.out_lap        = min(i + 1, n_laps);
        warning('Check back here to remove the pit no beacon')
        entry.out_lap        = entry.pit_lap;
        entry.stop_duration  = stop_duration;
        entry.tyres_changed  = n_changed;
        entry.tyre_change_FL = changed.FL;
        entry.tyre_change_FR = changed.FR;
        entry.tyre_change_RL = changed.RL;
        entry.tyre_change_RR = changed.RR;
        entry.tyre_id_before = id_before;
        entry.tyre_id_after  = id_after;
        entry.team           = tm;
        stops(end+1)         = entry; %#ok
        lastStopTime         = max([stops.stop_duration]);
    end

    if isempty(stops)
        fprintf('  Pit stops detected: 0\n');
    else
        fprintf('  Pit stops detected: %d  (tyre changes: %d)\n', ...
            numel(stops), sum([stops.tyres_changed] > 0));
        for s = 1:numel(stops)
            fprintf('    Lap %d → %d  |  %.1fs  |  %d tyre(s) changed\n', ...
                stops(s).pit_lap, stops(s).out_lap, ...
                stops(s).stop_duration, stops(s).tyres_changed);
        end
    end
end


% ======================================================================
%  LOCAL HELPERS
% ======================================================================
function vals = get_lap_channel(ch, lap)
    mask = ch.time >= lap.t_start & ch.time <= lap.t_end;
    vals = ch.data(mask);
end

function val = get_lap_scalar(ch, lap)
    vals = get_lap_channel(ch, lap);
    if isempty(vals)
        val = NaN;
        return;
    end
    if isnumeric(vals)
        val = mode(vals);
    else
        val = mode(string(vals));
    end
end