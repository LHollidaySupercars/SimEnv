% function pit_summary = smp_tyre_changes_from_cache(cache, driver_map)
% % SMP_TYRE_CHANGES_FROM_CACHE  Determine tyre changes at confirmed pit laps.
% %
% %   Gated entirely on cache.laps.(gk).lap_type == 'pitlap' — no ID-drift
% %   inference. For each pit lap, compares tyre wheel-sensor ID mean on the
% %   surrounding 'inlap' vs 'outlap' to decide which corners changed.
% %
% % Usage:
% %   pit_summary = smp_tyre_changes_from_cache(cache, driver_map);
% 
%     TYRE_CHS = {'TPM1S_FL_WS_ID', 'TPM1S_FR_WS_ID', ...
%                 'TPM1S_RL_WS_ID', 'TPM1S_RR_WS_ID'};
%     corners  = {'FL', 'FR', 'RL', 'RR'};
%     ID_TOL   = 0.5;
% 
%     rows = {};   % {driver, car, lap, FL, FR, RL, RR, n_tyres}
%     group_keys = fieldnames(cache.stats);
% 
%     for g = 1:numel(group_keys)
%         gk   = group_keys{g};
%         stat = cache.stats.(gk);
% 
%         if ~isfield(stat, 'Beacon') || ~isfield(stat.Beacon, 'lap_numbers'), continue; end
%         lap_nums = stat.Beacon.lap_numbers(:);
%         n_laps   = numel(lap_nums);
%         if n_laps < 2, continue; end
% 
%         drv = gk;
%         if isfield(cache, 'manifest') && ismember('Driver', cache.manifest.Properties.VariableNames)
%             mask = strcmp(cache.manifest.GroupKey, gk);
%             if any(mask)
%                 drv = strtrim(char(string(cache.manifest.Driver(find(mask,1)))));
%             end
%         end
%         car = resolve_car_number(drv, driver_map);
% 
%         % ── Locate lap_type for this group ──────────────────────────────
%         if ~isfield(cache, 'laps') || ~isfield(cache.laps, gk) || ...
%            ~isfield(cache.laps.(gk), 'lap_type')
%             warning('smp_tyre_changes_from_cache:noLapType', ...
%                 '[%s / car %s] No cache.laps.%s.lap_type found — skipping pit detection for this driver.', ...
%                 drv, car, gk);
%             continue;
%         end
%         lap_type = cache.laps.(gk).lap_type(:);
% 
%         if numel(lap_type) ~= n_laps
%             warning('smp_tyre_changes_from_cache:lapTypeMismatch', ...
%                 '[%s / car %s] lap_type length (%d) does not match Beacon lap_numbers length (%d) — skipping. Group keys may be misaligned between cache.stats and cache.laps.', ...
%                 drv, car, numel(lap_type), n_laps);
%             continue;
%         end
% 
%         pit_idx = find(strcmpi(lap_type, 'pitlap'));
% 
%         % ── Protective warning: no pit lap beyond lap 1 ─────────────────
%         real_pit_idx = pit_idx(lap_nums(pit_idx) > 1);
%         if isempty(real_pit_idx)
%             warning('smp_tyre_changes_from_cache:noPitStop', ...
%                 '*** [%s / car %s] NO PIT LAP DETECTED (excluding lap 1) — driver may not have a compiled pit stop, or lap_type data is incomplete/wrong for this run. Check manually. ***', ...
%                 drv, car);
%             continue;
%         end
% 
%         % ── Pull per-corner ID mean channels, rounded up front ──────────
%         id_mean = struct();
%         for c = 1:4
%             ch_field = matlab.lang.makeValidName(TYRE_CHS{c});
%             if isfield(stat, ch_field)
%                 id_mean.(corners{c}) = round(stat.(ch_field).mean(:));
%             else
%                 id_mean.(corners{c}) = nan(n_laps, 1);
%             end
%         end
%         if all(structfun(@(v) all(isnan(v)), id_mean))
%             warning('smp_tyre_changes_from_cache:noTyreIDChannels', ...
%                 '[%s / car %s] No TPM1S_*_WS_ID channels found — cannot determine which corners changed. Stop laps below will have NumTyres = 0.', ...
%                 drv, car);
%         end
% 
%         for pi = 1:numel(real_pit_idx)
%             i = real_pit_idx(pi);
%             pit_lap = lap_nums(i);
% 
%             % ── Find nearest inlap before, outlap after ─────────────────
%             in_idx  = find(strcmpi(lap_type(1:i), 'inlap'), 1, 'last');
%             out_idx = i + find(strcmpi(lap_type(i+1:end), 'outlap'), 1, 'first');
% 
%             if isempty(in_idx) || isempty(out_idx)
%                 warning('smp_tyre_changes_from_cache:missingInOutLap', ...
%                     '[%s / car %s] pit lap %d has no adjacent inlap/outlap in lap_type — skipping corner classification for this stop.', ...
%                     drv, car, pit_lap);
%                 continue;
%             end
% 
%             changed = false(1, 4);
%             n_ch    = 0;
%             for c = 1:4
%                 m_before = id_mean.(corners{c})(in_idx);
%                 m_after  = id_mean.(corners{c})(out_idx);
%                 if ~isnan(m_before) && ~isnan(m_after) && abs(m_after - m_before) > ID_TOL
%                     changed(c) = true;
%                     n_ch = n_ch + 1;
%                 end
%             end
% 
%             % ── Protective warning: pit lap confirmed but 0 tyres changed ─
%             if n_ch == 0
%                 warning('smp_tyre_changes_from_cache:pitLapNoTyreChange', ...
%                     '[%s / car %s] pit lap %d confirmed by lap_type but 0 corners show an ID change — check TPM1S channels for this stop (splash-and-dash, or sensor data missing).', ...
%                     drv, car, pit_lap);
%             end
% 
%             rows{end+1} = {drv, car, pit_lap, changed(1), changed(2), changed(3), changed(4), n_ch}; %#ok<AGROW>
%         end
%     end
% 
%     if isempty(rows)
%         fprintf('No tyre changes detected.\n');
%         pit_summary = table();
%         return;
%     end
% 
%     rows     = vertcat(rows{:});
%     Driver   = string(rows(:,1));
%     Car      = string(rows(:,2));
%     Lap      = cell2mat(rows(:,3));
%     FL       = logical(cell2mat(rows(:,4)));
%     FR       = logical(cell2mat(rows(:,5)));
%     RL       = logical(cell2mat(rows(:,6)));
%     RR       = logical(cell2mat(rows(:,7)));
%     NumTyres = cell2mat(rows(:,8));
% 
%     pit_summary = table(Car, Driver, Lap, NumTyres, FL, FR, RL, RR);
% 
%     CarNum = double(Car);   % numeric sort key, e.g. "10" -> 10
%     pit_summary = sortrows(addvars(pit_summary, CarNum), {'CarNum','Lap'});
%     pit_summary = removevars(pit_summary, 'CarNum');
%     % pit_summary = sortrows(pit_summary, {'Car','Lap'});
% 
%     StopNumber = zeros(height(pit_summary), 1);
%     prev = ''; cnt = 0;
%     for i = 1:height(pit_summary)
%         if ~strcmp(char(pit_summary.Car(i)), prev)
%             cnt = 1; prev = char(pit_summary.Car(i));
%         else
%             cnt = cnt + 1;
%         end
%         StopNumber(i) = cnt;
%     end
%     pit_summary.StopNumber = StopNumber;
% end
% 
% 
% % ── Local helpers ───────────────────────────────────────────────────────
% function num = resolve_car_number(driver_str, driver_map)
%     num = driver_str;
%     if isempty(driver_map) || ~isstruct(driver_map)
%         return;
%     end
%     name_lower = lower(strtrim(strrep(driver_str, '_', ' ')));
%     keys = fieldnames(driver_map);
%     for k = 1:numel(keys)
%         entry = driver_map.(keys{k});
%         if isfield(entry, 'aliases') && any(strcmp(entry.aliases, name_lower))
%             if isfield(entry, 'num') && ~isempty(entry.num)
%                 num = entry.num;
%             end
%             return;
%         end
%     end
% end

function pit_summary = smp_tyre_changes_from_cache(cache, driver_map)
% SMP_TYRE_CHANGES_FROM_CACHE  Determine tyre changes at confirmed pit laps.
%
%   Primary method: gated on cache.laps.(gk).lap_type == 'pitlap'.
%   For each pit lap, compares tyre wheel-sensor ID mean on the
%   surrounding 'inlap' vs 'outlap' to decide which corners changed.
%
%   Fallback: if a driver has NO confirmed 'pitlap' beyond lap 1, the
%   function scans for any 'inlap' immediately followed by an 'outlap'
%   (no marked pitlap required) and treats that adjacency as an inferred
%   stop. To avoid false negatives from ~20s tyre-ID sensor wake-up time
%   (some corners settle slower than others), the comparison window is
%   widened: the lap BEFORE the inlap (settled, old tyre) vs TWO laps
%   AFTER the outlap (settled, new tyre — falls back to one lap after if
%   two laps isn't available). The reported pit_lap still reflects the
%   original inlap/outlap pair. Rows produced this way are flagged
%   IsFallback = true.
%
%   Guards (fallback only):
%     - 'before' comparison lap rejected if inlap/outlap/pitlap.
%     - 'after' comparison lap rejected only if inlap/pitlap (a genuine
%       second stop starting). A spurious extra 'outlap' label ~2 laps
%       after pit exit is a known mislabeling artifact in this dataset
%       and does NOT block the comparison.
%     - Any corner flagged as "changed" is cross-checked one lap further
%       out from the 'after' lap. If that confirmation lap disagrees
%       (reading reverts back towards the 'before' value), the change is
%       treated as a single-lap sensor blip and NOT counted — this
%       matters most when two fallback stops are closely spaced, since
%       the approach to the next stop can produce a transient ID bounce.
%       If no confirmation lap is available (e.g. end of session), the
%       single reading is trusted as before.
%
% Usage:
%   pit_summary = smp_tyre_changes_from_cache(cache, driver_map);

    TYRE_CHS = {'TPM1S_FL_WS_ID', 'TPM1S_FR_WS_ID', ...
                'TPM1S_RL_WS_ID', 'TPM1S_RR_WS_ID'};
    corners  = {'FL', 'FR', 'RL', 'RR'};
    ID_TOL   = 0.5;
    UNSETTLED_TYPES_BEFORE = {'inlap', 'outlap', 'pitlap'};
    UNSETTLED_TYPES_AFTER  = {'inlap', 'pitlap'};  % 'outlap' excluded — see note above

    rows = {};   % {driver, car, lap, FL, FR, RL, RR, n_tyres, is_fallback}
    group_keys = fieldnames(cache.stats);

    for g = 1:numel(group_keys)
        gk   = group_keys{g};
        stat = cache.stats.(gk);

        if ~isfield(stat, 'Beacon') || ~isfield(stat.Beacon, 'lap_numbers'), continue; end
        lap_nums = stat.Beacon.lap_numbers(:);
        n_laps   = numel(lap_nums);
        if n_laps < 2, continue; end

        drv = gk;
        if isfield(cache, 'manifest') && ismember('Driver', cache.manifest.Properties.VariableNames)
            mask = strcmp(cache.manifest.GroupKey, gk);
            if any(mask)
                drv = strtrim(char(string(cache.manifest.Driver(find(mask,1)))));
            end
        end
        car = resolve_car_number(drv, driver_map);

        % ── Locate lap_type for this group ──────────────────────────────
        if ~isfield(cache, 'laps') || ~isfield(cache.laps, gk) || ...
           ~isfield(cache.laps.(gk), 'lap_type')
            warning('smp_tyre_changes_from_cache:noLapType', ...
                '[%s / car %s] No cache.laps.%s.lap_type found — skipping pit detection for this driver.', ...
                drv, car, gk);
            continue;
        end
        lap_type = cache.laps.(gk).lap_type(:);

        if numel(lap_type) ~= n_laps
            warning('smp_tyre_changes_from_cache:lapTypeMismatch', ...
                '[%s / car %s] lap_type length (%d) does not match Beacon lap_numbers length (%d) — skipping. Group keys may be misaligned between cache.stats and cache.laps.', ...
                drv, car, numel(lap_type), n_laps);
            continue;
        end

        pit_idx = find(strcmpi(lap_type, 'pitlap'));

        % ── Protective check: no pit lap beyond lap 1 ───────────────────
        real_pit_idx = pit_idx(lap_nums(pit_idx) > 1);

        is_fallback     = false;
        confirm_events  = [];   % [confirm_before_idx, confirm_after_idx] per row, fallback only

        if isempty(real_pit_idx)
            % ── Fallback: infer stop(s) from inlap->outlap adjacency ────
            fallback_pairs = find_inlap_outlap_pairs(lap_type, lap_nums);

            if isempty(fallback_pairs)
                warning('smp_tyre_changes_from_cache:noPitStop', ...
                    '*** [%s / car %s] NO PIT LAP DETECTED (excluding lap 1) — no inlap->outlap pair found either. Check manually. ***', ...
                    drv, car);
                continue;
            end

            warning('smp_tyre_changes_from_cache:fallbackPitStop', ...
                '[%s / car %s] No marked pitlap — using widened inlap-1/outlap+2 fallback (%d stop(s) inferred).', ...
                drv, car, size(fallback_pairs,1));

            is_fallback = true;

            % Widen window: lap before inlap (settled, old tyre) vs
            % TWO laps after outlap (settled, new tyre — some corners'
            % ID sensors are slower to lock in than others past the
            % ~20s wake-up; +1 alone can still catch a corner mid-swap).
            n_fb = size(fallback_pairs, 1);
            events         = nan(n_fb, 3);
            confirm_events = nan(n_fb, 2);
            for fi = 1:n_fb
                in_idx0  = fallback_pairs(fi, 1);
                out_idx0 = fallback_pairs(fi, 2);

                before_idx = in_idx0 - 1;

                % Prefer +2 laps after outlap; fall back to +1 if +2 is OOB.
                if out_idx0 + 2 <= n_laps
                    after_idx = out_idx0 + 2;
                elseif out_idx0 + 1 <= n_laps
                    after_idx = out_idx0 + 1;
                    warning('smp_tyre_changes_from_cache:fallbackAfterWindowShort', ...
                        '[%s / car %s] pit lap %d — only 1 lap available after outlap (session/data ends), using +1 instead of +2. Slow-settling corners may still be missed.', ...
                        drv, car, lap_nums(out_idx0));
                else
                    after_idx = NaN;
                end

                if before_idx < 1 || isnan(after_idx)
                    warning('smp_tyre_changes_from_cache:fallbackWindowOOB', ...
                        '[%s / car %s] widened fallback window out of bounds for inlap idx %d / outlap idx %d — skipping this stop.', ...
                        drv, car, in_idx0, out_idx0);
                    continue;
                end

                % Guard: 'before' must be a fully settled racing lap.
                % 'after' is only rejected for inlap/pitlap (real second
                % stop) — a spurious 'outlap' relabel ~2 laps out is a
                % known mislabeling artifact in this dataset and is NOT
                % treated as blocking.
                if any(strcmpi(lap_type{before_idx}, UNSETTLED_TYPES_BEFORE)) || ...
                   any(strcmpi(lap_type{after_idx},  UNSETTLED_TYPES_AFTER))
                    warning('smp_tyre_changes_from_cache:fallbackWindowUnsettled', ...
                        '[%s / car %s] widened fallback window for pit lap %d lands on an unsettled lap (before=%s, after=%s) — likely a closely-spaced second stop. Skipping to avoid a bad comparison.', ...
                        drv, car, lap_nums(out_idx0), lap_type{before_idx}, lap_type{after_idx});
                    continue;
                end

                % ── Confirmation indices — one lap further out on each
                % side, used to reject single-lap sensor blips. ─────────
                confirm_before_idx = before_idx - 1;
                if confirm_before_idx < 1
                    confirm_before_idx = NaN;
                end

                confirm_after_idx = after_idx + 1;
                if confirm_after_idx > n_laps || ...
                   any(strcmpi(lap_type{min(confirm_after_idx, n_laps)}, UNSETTLED_TYPES_AFTER))
                    confirm_after_idx = NaN;
                end

                % pit_lap label reflects the actual inlap/outlap pair,
                % not the widened comparison laps
                events(fi, :)         = [before_idx, after_idx, lap_nums(out_idx0)];
                confirm_events(fi, :) = [confirm_before_idx, confirm_after_idx];
            end
            keep_mask      = ~any(isnan(events), 2);
            events         = events(keep_mask, :);
            confirm_events = confirm_events(keep_mask, :);

            if isempty(events)
                warning('smp_tyre_changes_from_cache:fallbackAllSkipped', ...
                    '[%s / car %s] all fallback stop candidates were skipped (OOB or unsettled window) — no rows produced.', ...
                    drv, car);
                continue;
            end
        else
            events = zeros(numel(real_pit_idx), 3);
            for pi = 1:numel(real_pit_idx)
                i = real_pit_idx(pi);
                in_idx  = find(strcmpi(lap_type(1:i), 'inlap'), 1, 'last');
                out_idx = i + find(strcmpi(lap_type(i+1:end), 'outlap'), 1, 'first');
                if isempty(in_idx),  in_idx  = NaN; end
                if isempty(out_idx), out_idx = NaN; end
                events(pi,:) = [in_idx, out_idx, lap_nums(i)];
            end
            confirm_events = nan(size(events, 1), 2);  % unused, not fallback
        end

        % ── Pull per-corner ID mean channels, rounded up front ──────────
        id_mean = struct();
        for c = 1:4
            ch_field = matlab.lang.makeValidName(TYRE_CHS{c});
            if isfield(stat, ch_field)
                id_mean.(corners{c}) = round(stat.(ch_field).mean(:));
            else
                id_mean.(corners{c}) = nan(n_laps, 1);
            end
        end
        if all(structfun(@(v) all(isnan(v)), id_mean))
            warning('smp_tyre_changes_from_cache:noTyreIDChannels', ...
                '[%s / car %s] No TPM1S_*_WS_ID channels found — cannot determine which corners changed. Stop laps below will have NumTyres = 0.', ...
                drv, car);
        end

        % ── Process each stop event ──────────────────────────────────
        for pi = 1:size(events, 1)
            in_idx  = events(pi, 1);
            out_idx = events(pi, 2);
            pit_lap = events(pi, 3);

            if isnan(in_idx) || isnan(out_idx)
                warning('smp_tyre_changes_from_cache:missingInOutLap', ...
                    '[%s / car %s] pit lap %d has no adjacent inlap/outlap in lap_type — skipping corner classification for this stop.', ...
                    drv, car, pit_lap);
                continue;
            end

            changed = false(1, 4);
            n_ch    = 0;
            for c = 1:4
                m_before = id_mean.(corners{c})(in_idx);
                m_after  = id_mean.(corners{c})(out_idx);
                is_diff  = ~isnan(m_before) && ~isnan(m_after) && abs(m_after - m_before) > ID_TOL;

                if is_diff && is_fallback && ~isnan(confirm_events(pi, 2))
                    % Require the 'after' reading to persist into the
                    % next available lap too — a single-lap difference
                    % with no confirmation is treated as a sensor blip.
                    m_confirm = id_mean.(corners{c})(confirm_events(pi, 2));
                    if ~isnan(m_confirm) && abs(m_confirm - m_after) > ID_TOL
                        warning('smp_tyre_changes_from_cache:fallbackUnconfirmedChange', ...
                            '[%s / car %s] pit lap %d corner %s flagged as changed but reading is not stable one lap further out (after=%g, confirm=%g) — treating as noise, not counted.', ...
                            drv, car, pit_lap, corners{c}, m_after, m_confirm);
                        is_diff = false;
                    end
                end

                if is_diff
                    changed(c) = true;
                    n_ch = n_ch + 1;
                end
            end

            % ── Protective warning: pit lap confirmed but 0 tyres changed ─
            if n_ch == 0
                warning('smp_tyre_changes_from_cache:pitLapNoTyreChange', ...
                    '[%s / car %s] pit lap %d confirmed by lap_type but 0 corners show an ID change — check TPM1S channels for this stop (splash-and-dash, or sensor data missing).', ...
                    drv, car, pit_lap);
            end

            rows{end+1} = {drv, car, pit_lap, changed(1), changed(2), changed(3), changed(4), n_ch, is_fallback}; %#ok<AGROW>
        end
    end

    if isempty(rows)
        fprintf('No tyre changes detected.\n');
        pit_summary = table();
        return;
    end

    rows       = vertcat(rows{:});
    Driver     = string(rows(:,1));
    Car        = string(rows(:,2));
    Lap        = cell2mat(rows(:,3));
    FL         = logical(cell2mat(rows(:,4)));
    FR         = logical(cell2mat(rows(:,5)));
    RL         = logical(cell2mat(rows(:,6)));
    RR         = logical(cell2mat(rows(:,7)));
    NumTyres   = cell2mat(rows(:,8));
    IsFallback = logical(cell2mat(rows(:,9)));

    pit_summary = table(Car, Driver, Lap, NumTyres, FL, FR, RL, RR, IsFallback);

    CarNum = double(Car);   % numeric sort key, e.g. "10" -> 10
    pit_summary = sortrows(addvars(pit_summary, CarNum), {'CarNum','Lap'});
    pit_summary = removevars(pit_summary, 'CarNum');

    StopNumber = zeros(height(pit_summary), 1);
    prev = ''; cnt = 0;
    for i = 1:height(pit_summary)
        if ~strcmp(char(pit_summary.Car(i)), prev)
            cnt = 1; prev = char(pit_summary.Car(i));
        else
            cnt = cnt + 1;
        end
        StopNumber(i) = cnt;
    end
    pit_summary.StopNumber = StopNumber;
end


% ── Local helpers ───────────────────────────────────────────────────────
function num = resolve_car_number(driver_str, driver_map)
    num = driver_str;
    if isempty(driver_map) || ~isstruct(driver_map)
        return;
    end
    name_lower = lower(strtrim(strrep(driver_str, '_', ' ')));
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        if isfield(entry, 'aliases') && any(strcmp(entry.aliases, name_lower))
            if isfield(entry, 'num') && ~isempty(entry.num)
                num = entry.num;
            end
            return;
        end
    end
end

function pairs = find_inlap_outlap_pairs(lap_type, lap_nums)
% Find every index i where lap_type(i) == 'inlap' and lap_type(i+1) ==
% 'outlap' (direct adjacency — no marked 'pitlap' required in between).
% Excludes any pair where the outlap's lap number is <= 1.
    pairs = [];
    n = numel(lap_type);
    for i = 1:n-1
        if strcmpi(lap_type(i), 'inlap') && strcmpi(lap_type(i+1), 'outlap') ...
                && lap_nums(i+1) > 1
            pairs(end+1, :) = [i, i+1]; %#ok<AGROW>
        end
    end
end