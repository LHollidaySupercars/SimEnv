function filtered = smp_apply_plot_filter(run_list, groups)
% SMP_APPLY_PLOT_FILTER  Filter a run_list using parsed filter groups.
%
% Groups are OR'd — a run is included if it matches ANY group.
% Within a group all conditions are AND'd.
% n= selects the top N runs within that group by best lap time.
%
% Usage:
%   groups   = smp_parse_plot_filter('mfr=Ford,n=1;mfr=Toyota');
%   filtered = smp_apply_plot_filter(run_list, groups);
%
% Inputs:
%   run_list  - struct array from smp_plot_from_config internals
%               Each entry has: .driver .team .manufacturer .session .laps
%   groups    - struct array from smp_parse_plot_filter()
%
% Output:
%   filtered  - subset of run_list matching any group, with n= applied.
%               Duplicates (run matching multiple groups) are deduplicated.

    if isempty(groups)
        filtered = run_list;   % no filter = pass everything through
        return;
    end

    n_runs   = numel(run_list);
    included = false(1, n_runs);   % tracks which runs make the final cut

    for g = 1:numel(groups)
        grp = groups(g);

        % ---- Find runs matching this group (AND logic) ----
        grp_mask = true(1, n_runs);

        if ~isempty(grp.mfr)
            mfr_hit = false(1, n_runs);
            for r = 1:n_runs
                mfr_hit(r) = any(cellfun(@(v) ...
                    contains(lower(run_list(r).manufacturer), lower(v)), grp.mfr));
            end
            grp_mask = grp_mask & mfr_hit;
        end

        if ~isempty(grp.drv)
            drv_hit = false(1, n_runs);
            for r = 1:n_runs
                drv_hit(r) = any(cellfun(@(v) ...
                    contains(lower(run_list(r).driver), lower(v)), grp.drv));
            end
            grp_mask = grp_mask & drv_hit;
        end

        if ~isempty(grp.team)
            team_hit = false(1, n_runs);
            for r = 1:n_runs
                team_hit(r) = any(cellfun(@(v) ...
                    strcmpi(run_list(r).team, v), grp.team));
            end
            grp_mask = grp_mask & team_hit;
        end

        if ~isempty(grp.session)
            ses_hit = false(1, n_runs);
            for r = 1:n_runs
                ses_hit(r) = any(cellfun(@(v) ...
                    contains(lower(run_list(r).session), lower(v)), grp.session));
            end
            grp_mask = grp_mask & ses_hit;
        end

        grp_idx = find(grp_mask);

        % ---- Apply n= : keep top N by best lap time ----
        if grp.n > 0 && numel(grp_idx) > grp.n
            best_times = arrayfun(@(r) best_lap_time(run_list(r)), grp_idx);
            [~, sort_ord] = sort(best_times, 'ascend');
            grp_idx = grp_idx(sort_ord(1:grp.n));
        end

        included(grp_idx) = true;

        fprintf('  Filter group %d: %d run(s) matched', g, numel(grp_idx));
        if grp.n > 0
            fprintf(' (top %d by lap time)', grp.n);
        end
        fprintf('\n');
    end

    filtered = run_list(included);
    fprintf('  Total after filter: %d / %d runs\n', numel(filtered), n_runs);
end


% ======================================================================= %
function t = best_lap_time(entry)
% Return the minimum lap time for a run.
% Stream mode stores times in entry.traces.lap_times.
% Bulk mode stores them in entry.laps.
    t = Inf;

    % Stream mode — traces.lap_times is sorted fastest first
    if isfield(entry, 'traces') && isstruct(entry.traces) && ...
       isfield(entry.traces, 'lap_times') && ~isempty(entry.traces.lap_times)
        times = entry.traces.lap_times;
        times = times(isfinite(times));
        if ~isempty(times)
            t = min(times);
            return;
        end
    end

    % Bulk mode — read from entry.laps
    if isfield(entry, 'laps') && ~isempty(entry.laps)
        lap_times = [entry.laps.lap_time];
        lap_times = lap_times(isfinite(lap_times));
        if ~isempty(lap_times)
            t = min(lap_times);
        end
    end
end
