function laps = smp_data_filter(laps, channel_rules)
% SMP_DATA_FILTER  Set out-of-range and sentinel samples to NaN before lap_stats.
%
% Called AFTER lap_slicer and BEFORE lap_stats inside smp_compile_event.
% Bad samples are set to NaN in laps(k).channels.(field).data so that all
% downstream statistics ignore them — lap_stats already strips NaN/Inf via
% d = d(isfinite(d)) before every aggregation.
%
% Usage:
%   laps = smp_data_filter(laps, channel_rules)
%
% Inputs:
%   laps           Struct array from lap_slicer().
%   channel_rules  Struct array from smp_channel_config_load() second output.
%                  Fields per rule:
%                    .channel       char     exact channel name (MoTeC field name)
%                    .min_valid     double   lower bound  (-Inf = no lower check)
%                    .max_valid     double   upper bound  (+Inf = no upper check)
%                    .sentinels     double   row vector of sentinel values ([] = none)
%                    .sentinel_tol  double   tolerance for float comparison (default 1e-4)
%
% A sample is set to NaN if ANY of the following are true:
%   - value < min_valid
%   - value > max_valid
%   - abs(value - any_sentinel) < sentinel_tol
%
% Output:
%   laps   Same struct array with bad samples replaced by NaN in .data fields.

    if isempty(laps) || isempty(channel_rules)
        return;
    end

    % Build a lookup: sanitised field name → index into channel_rules
    rule_index = build_rule_index(channel_rules);

    n_laps    = numel(laps);
    ch_fields = fieldnames(laps(1).channels);
    n_cleaned = 0;

    for ci = 1:numel(ch_fields)
        fn = ch_fields{ci};

        rule = find_rule(fn, laps(1).channels.(fn), rule_index, channel_rules);
        if isempty(rule), continue; end

        mn  = rule.min_valid;
        mx  = rule.max_valid;
        snt = rule.sentinels;
        tol = get_tol(rule);
        n_laps_affected = 0;

        for k = 1:n_laps
            d   = laps(k).channels.(fn).data(:);
            bad = false(size(d));

            % Range checks
            if isfinite(mn), bad = bad | (d < mn); end
            if isfinite(mx), bad = bad | (d > mx); end

            % Sentinel checks
            for s = 1:numel(snt)
                bad = bad | (abs(d - snt(s)) < tol);
            end

            % Only count samples that are currently finite (don't double-count
            % values that were already NaN before this filter ran)
            n_bad = sum(bad & isfinite(d));
            if n_bad > 0
                d(bad) = NaN;
                laps(k).channels.(fn).data = d;
                n_laps_affected = n_laps_affected + 1;
            end
        end

        if n_laps_affected > 0
            fprintf('  [smp_data_filter] %-35s : cleaned %d / %d laps\n', ...
                fn, n_laps_affected, n_laps);
            n_cleaned = n_cleaned + 1;
        end
    end

    if n_cleaned == 0
        fprintf('  [smp_data_filter] No channels required filtering.\n');
    else
        fprintf('  [smp_data_filter] %d channel(s) cleaned.\n', n_cleaned);
    end
end


% ======================================================================= %
%  BUILD RULE LOOKUP
% ======================================================================= %
function idx_map = build_rule_index(channel_rules)
% Map both the raw channel name and its sanitised MATLAB fieldname to the
% rule index so we can match regardless of which form laps uses.
    idx_map = containers.Map('KeyType','char','ValueType','int32');
    for i = 1:numel(channel_rules)
        raw = channel_rules(i).channel;
        idx_map(raw) = int32(i);
        san = sanitise_fn(raw);
        if ~strcmp(san, raw) && ~isKey(idx_map, san)
            idx_map(san) = int32(i);
        end
    end
end


% ======================================================================= %
%  FIND RULE FOR A CHANNEL FIELD
% ======================================================================= %
function rule = find_rule(fn, ch_struct, idx_map, channel_rules)
    rule = [];

    % 1. Direct fieldname match (most common — already sanitised)
    if isKey(idx_map, fn)
        rule = channel_rules(idx_map(fn));
        return;
    end

    % 2. Fall back to raw_name stored in the channel struct
    if isfield(ch_struct, 'raw_name') && ~isempty(ch_struct.raw_name)
        rn = ch_struct.raw_name;
        if isKey(idx_map, rn)
            rule = channel_rules(idx_map(rn));
            return;
        end
        san = sanitise_fn(rn);
        if isKey(idx_map, san)
            rule = channel_rules(idx_map(san));
        end
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %
function name = sanitise_fn(ch)
    name = regexprep(strtrim(ch), '[^a-zA-Z0-9]', '_');
    if ~isempty(name) && isstrprop(name(1), 'digit')
        name = ['ch_', name];
    end
end

function tol = get_tol(rule)
    if isfield(rule, 'sentinel_tol') && ~isempty(rule.sentinel_tol)
        tol = rule.sentinel_tol;
    else
        tol = 1e-4;
    end
end