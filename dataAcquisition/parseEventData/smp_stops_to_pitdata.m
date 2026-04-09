function pitData = smp_stops_to_pitdata(stops, SMP, driver_map)
% SMP_STOPS_TO_PITDATA  Convert smp_pitstop_detect output to plotPitStops format.
%
% Usage:
%   stops   = smp_pitstop_detect(SMP_filtered);
%   pitData = smp_stops_to_pitdata(stops, SMP_filtered, driver_map);
%   figs    = plotPitStops(pitData, 'Manufacturer', mfgMap);
%
% Inputs:
%   stops      - struct from smp_pitstop_detect()
%   SMP        - same SMP_filtered passed to smp_pitstop_detect()
%   driver_map - struct from smp_driver_alias_load() — pass [] if not available
%
% Output:
%   pitData - struct array compatible with plotPitStops(), one element per
%             unique driver. Fields:
%               .driver       DRV_TLA string
%               .manufacturer string (Ford / Chev / Toyota)
%               .stops        table with columns:
%                               LapNumber, StopTime_s, FL, FR, RL, RR,
%                               ChangeType, TyreCategory

pitData = struct(...
    'driver',{},       ...
    'manufacturer',{}, ... 
    'stops',{},        ...
    'team',{});
teams   = fieldnames(stops);

for t = 1:numel(teams)
    tm = teams{t};

    for r = 1:numel(stops.(tm))
        run_stops = stops.(tm){r};
        if isempty(run_stops), continue; end

       % ── Resolve driver & manufacturer from SMP metadata ──────────────
        drv = tm;   % fallback to team acronym
        mfr = '';
        try
            drv = strtrim(char(string(SMP.(tm).meta.Driver{r})));
            mfr = strtrim(char(string(SMP.(tm).meta.Manufacturer{r})));
        catch
        end

        % ── Resolve TLA via driver_map if available ───────────────────────
        tla = resolve_tla(drv, driver_map);
        if isempty(tla), tla = drv; end

        % ── Resolve team display name via driver_map.X.team_tla ──────────
        team_display = tm;   % fallback to folder acronym
        if ~isempty(driver_map) && isstruct(driver_map)
            keys = fieldnames(driver_map);
            for k = 1:numel(keys)
                dm_entry = driver_map.(keys{k});
                if (isfield(dm_entry, 'tla') && strcmpi(dm_entry.tla, tla)) || ...
                   strcmpi(keys{k}, strrep(drv, ' ', '_'))
                    if isfield(dm_entry, 'team_tla') && ~isempty(dm_entry.team_tla)
                        team_display = dm_entry.team_tla;
                    end
                    break;
                end
            end
        end

        % ── Build stops table ─────────────────────────────────────────────
        n          = numel(run_stops);
        LapNumber  = zeros(n,1);
        StopTime_s = zeros(n,1);
        FL         = false(n,1);
        FR         = false(n,1);
        RL         = false(n,1);
        RR         = false(n,1);
        ChangeType = strings(n,1);
        TyreCat    = strings(n,1);

        for s = 1:n
            st            = run_stops(s);
            LapNumber(s)  = st.pit_lap;
            StopTime_s(s) = st.stop_duration;
            FL(s)         = st.tyre_change_FL;
            FR(s)         = st.tyre_change_FR;
            RL(s)         = st.tyre_change_RL;
            RR(s)         = st.tyre_change_RR;
            ChangeType(s) = build_change_type(FL(s), FR(s), RL(s), RR(s));
            TyreCat(s)    = classify_tyre_cat(FL(s) + FR(s) + RL(s) + RR(s));
        end

        T = table(LapNumber, StopTime_s, FL, FR, RL, RR, ChangeType, TyreCat, ...
                  'VariableNames', {'LapNumber','StopTime_s','FL','FR','RL','RR', ...
                                    'ChangeType','TyreCategory'});

        % ── Merge into existing driver entry or append new ────────────────
        idx = find(strcmp({pitData.driver}, tla), 1);
        if isempty(idx)
            entry.driver       = tla;
            entry.team         = team_display;
            entry.manufacturer = mfr;
            entry.stops        = T;
            pitData(end+1)     = entry; %#ok
        else
            pitData(idx).stops = [pitData(idx).stops; T];
        end
    end
end

end


% ── Local helpers ─────────────────────────────────────────────────────────

function ct = build_change_type(fl, fr, rl, rr)
    corners = {};
    if fl, corners{end+1} = 'FL'; end
    if fr, corners{end+1} = 'FR'; end
    if rl, corners{end+1} = 'RL'; end
    if rr, corners{end+1} = 'RR'; end
    n = numel(corners);
    if     n == 0, ct = "No Change";
    elseif n == 4, ct = "4 Tyre";
    else,          ct = string(strjoin(corners, '+'));
    end
end

function cat = classify_tyre_cat(n_changed)
    if     n_changed >= 4, cat = "4 Tyre";
    elseif n_changed >  0, cat = "2 Tyre";
    else,                  cat = "No Change";
    end
end

function tla = resolve_tla(driver_str, driver_map)
    tla = '';
    if isempty(driver_map) || ~isstruct(driver_map), return; end
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        if isfield(entry, 'aliases')
            for a = 1:numel(entry.aliases)
                if strcmpi(entry.aliases{a}, driver_str)
                    tla = entry.tla;
                    return;
                end
            end
        end
        if isfield(entry, 'tla') && strcmpi(entry.tla, driver_str)
            tla = entry.tla;
            return;
        end
    end
end