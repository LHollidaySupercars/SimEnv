function [preceding_lap, success] = smp_load_preceding_lap(cache, group_key, lap_idx)
% SMP_LOAD_PRECEDING_LAP  Load the lap immediately before the qualifying lap.
%
% Finds the .ld file(s) associated with the group in cache.manifest, re-opens
% them with motec_ld_reader, and slices all laps.  Returns the lap whose
% lap_number == qualifying_lap_number - 1.
%
% Inputs:
%   cache      - cache struct (must have .manifest and .traces fields)
%   group_key  - group key string, e.g. 't8r_broc_feeney_q13_185'
%   lap_idx    - index into cache.traces.(group_key).lap_times for the
%                qualifying (fastest) lap
%
% Outputs:
%   preceding_lap - lap struct from lap_slicer (includes .channels with
%                   .data and .dist fields, .lap_number, .lap_time)
%   success       - true if preceding lap was found

    success       = false;
    preceding_lap = [];

    % ------------------------------------------------------------------
    %  Guard: group must exist in traces
    % ------------------------------------------------------------------
    if ~isfield(cache, 'traces') || ~isfield(cache.traces, group_key)
        fprintf('[smp_load_preceding_lap] Group ''%s'' not found in traces.\n', group_key);
        return;
    end

    % ------------------------------------------------------------------
    %  Qualifying lap number in the raw .ld file
    % ------------------------------------------------------------------
    qual_lap_num   = cache.traces.(group_key).lap_numbers(lap_idx);
    target_lap_num = qual_lap_num - 1;

    fprintf('[smp_load_preceding_lap] Qualifying lap number in cache: %d  →  looking for preceding lap number: %d\n', ...
        qual_lap_num, target_lap_num);

    if target_lap_num < 1
        fprintf('[smp_load_preceding_lap] Qualifying lap is lap 1 — no preceding lap.\n');
        return;
    end

    fprintf('[smp_load_preceding_lap] Looking for lap %d (preceding lap %d)...\n', ...
        target_lap_num, qual_lap_num);

    % ------------------------------------------------------------------
    %  Find .ld files for this group from manifest
    % ------------------------------------------------------------------
    if ~isfield(cache, 'manifest') || isempty(cache.manifest)
        fprintf('[smp_load_preceding_lap] Cache has no manifest.\n');
        return;
    end

    row_mask = strcmp(cache.manifest.GroupKey, group_key);
    if ~any(row_mask)
        fprintf('[smp_load_preceding_lap] Group ''%s'' not found in manifest.\n', group_key);
        return;
    end

    ld_paths = cache.manifest.Path(row_mask);

    % ------------------------------------------------------------------
    %  Channels to extract (keep minimal for speed)
    % ------------------------------------------------------------------
    channels_needed = {'Throttle_Pedal', 'Ground_Speed', 'Brake_Pressure_Front', ...
                       'Odometer', 'Lap_Number', 'Lap_Distance'};

    % Wide time limits — we want outlaps/inlaps too, not just flying laps
    lap_opts.min_lap_time = 5;
    lap_opts.max_lap_time = 3600;
    lap_opts.verbose      = false;

    % ------------------------------------------------------------------
    %  Try each .ld file — preceding lap may be in a different stint file
    % ------------------------------------------------------------------
    for f = 1:numel(ld_paths)
        fpath = ld_paths{f};

        if ~exist(fpath, 'file')
            fprintf('[smp_load_preceding_lap] File not found: %s\n', fpath);
            continue;
        end

        fprintf('[smp_load_preceding_lap] Loading: %s\n', fpath);

        try
            session = motec_ld_reader(fpath, channels_needed);
        catch ME
            fprintf('[smp_load_preceding_lap] motec_ld_reader failed: %s\n', ME.message);
            continue;
        end

        try
            laps = lap_slicer(session, lap_opts);
        catch ME
            fprintf('[smp_load_preceding_lap] lap_slicer failed: %s\n', ME.message);
            continue;
        end

        if isempty(laps)
            continue;
        end

        lap_numbers = [laps.lap_number];
        lap_times   = [laps.lap_time];
        fprintf('[smp_load_preceding_lap] File %d: laps found = [%s]\n', ...
            f, strjoin(arrayfun(@num2str, lap_numbers, 'UniformOutput', false), ' '));

        % Strategy 1: lap number arithmetic (qual_lap_num - 1)
        idx = find(lap_numbers == target_lap_num, 1);

        % Strategy 2: find qualifying lap in this file by lap number, take the one before
        if isempty(idx)
            qual_idx = find(lap_numbers == qual_lap_num, 1);
            if ~isempty(qual_idx) && qual_idx > 1
                idx = qual_idx - 1;
                fprintf('[smp_load_preceding_lap] Strategy 2: using lap at position %d (lap# %d) before qualifying (position %d, lap# %d)\n', ...
                    idx, lap_numbers(idx), qual_idx, lap_numbers(qual_idx));
            end
        end

        % Strategy 3: find qualifying lap by lap TIME (most robust — handles lap# schema mismatches)
        if isempty(idx)
            qual_time = cache.traces.(group_key).lap_times(lap_idx);
            [~, time_match] = min(abs(lap_times - qual_time));
            if abs(lap_times(time_match) - qual_time) < 2.0 && time_match > 1
                idx = time_match - 1;
                fprintf('[smp_load_preceding_lap] Strategy 3: matched by lap time %.2fs → preceding lap at position %d (%.2fs)\n', ...
                    qual_time, idx, lap_times(idx));
            end
        end

        if isempty(idx)
            fprintf('[smp_load_preceding_lap] Preceding lap not in file %d/%d.\n', f, numel(ld_paths));
            continue;
        end

        preceding_lap = laps(idx);
        success       = true;

        fprintf('[smp_load_preceding_lap] Found preceding lap %d  (%.2f s).\n', ...
            preceding_lap.lap_number, preceding_lap.lap_time);
        return;
    end

    fprintf('[smp_load_preceding_lap] Preceding lap not found in any .ld file.\n');
end
