%% SMP_TYRE_CHANGES_FROM_CACHE
% Infer tyre changes from cache by comparing tyre wheel-sensor ID lap-to-lap.
% Only considers laps > 5. Outputs a pit_summary-style table.
%
% Usage:
%   Run after loading cache (e.g. cache = smp_cache_load(top_level_dir))

TYRE_CHS = {'TPM1S_FL_WS_ID', 'TPM1S_FR_WS_ID', ...
             'TPM1S_RL_WS_ID', 'TPM1S_RR_WS_ID'};
corners  = {'FL', 'FR', 'RL', 'RR'};
MIN_LAP  = 5;

% ── Accumulators ──────────────────────────────────────────────────────────
rows = {};   % {driver, lap, FL, FR, RL, RR, n_tyres}

group_keys = fieldnames(cache.stats);

for g = 1:numel(group_keys)
    gk   = group_keys{g};
    stat = cache.stats.(gk);

    if ~isfield(stat, 'lap_numbers'), continue; end

    lap_nums = stat.lap_numbers(:);   % [N x 1]
    n_laps   = numel(lap_nums);
    if n_laps < 2, continue; end

    % Resolve driver label from manifest
    drv = gk;   % fallback
    if isfield(cache, 'manifest') && ismember('Driver', cache.manifest.Properties.VariableNames)
        mask = strcmp(cache.manifest.GroupKey, gk);
        if any(mask)
            drv = strtrim(char(string(cache.manifest.Driver(find(mask,1)))));
        end
    end

    % Pull per-lap mean value for each tyre ID channel (mean = constant within lap)
    id = struct();
    for c = 1:4
        ch_field = matlab.lang.makeValidName(TYRE_CHS{c});
        if isfield(stat, ch_field) && isfield(stat.(ch_field), 'max')
            id.(corners{c}) = stat.(ch_field).max(:);   % [N x 1]
        else
            id.(corners{c}) = nan(n_laps, 1);
        end
    end

    % Compare lap i to lap i+1; only flag laps where lap_number > MIN_LAP
    for i = 1:(n_laps - 1)
        lap_i    = lap_nums(i);
        lap_next = lap_nums(i+1);

        % Must be consecutive laps and both > MIN_LAP
        if lap_next ~= lap_i + 1, continue; end
        if lap_i <= MIN_LAP,      continue; end

        changed = false(1, 4);
        n_ch    = 0;
        for c = 1:4
            v_before = id.(corners{c})(i);
            v_after  = id.(corners{c})(i+1);
            if ~isnan(v_before) && ~isnan(v_after) && v_before ~= v_after
                changed(c) = true;
                n_ch = n_ch + 1;
            end
        end

        if n_ch == 0, continue; end   % no change — skip

        rows{end+1} = {drv, lap_next, changed(1), changed(2), changed(3), changed(4), n_ch}; %#ok
    end
end

% ── Build output table ────────────────────────────────────────────────────
if isempty(rows)
    fprintf('No tyre changes detected.\n');
    pit_summary = table();
else
    rows      = vertcat(rows{:});
    Driver    = string(rows(:,1));
    Lap       = cell2mat(rows(:,2));
    FL        = logical(cell2mat(rows(:,3)));
    FR        = logical(cell2mat(rows(:,4)));
    RL        = logical(cell2mat(rows(:,5)));
    RR        = logical(cell2mat(rows(:,6)));
    NumTyres  = cell2mat(rows(:,7));

    pit_summary = table(Driver, Lap, NumTyres, FL, FR, RL, RR);
    pit_summary = sortrows(pit_summary, {'Driver','Lap'});

    % Add sequential stop number per driver
    StopNumber = zeros(height(pit_summary), 1);
    prev = ''; cnt = 0;
    for i = 1:height(pit_summary)
        if ~strcmp(char(pit_summary.Driver(i)), prev)
            cnt = 1; prev = char(pit_summary.Driver(i));
        else
            cnt = cnt + 1;
        end
        StopNumber(i) = cnt;
    end
    pit_summary.StopNumber = StopNumber;

    disp(pit_summary);
end