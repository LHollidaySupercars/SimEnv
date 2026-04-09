function T = smp_flatten_stats(cache, event_name)
% SMP_FLATTEN_STATS  Flatten a compiled SMP cache into a per-lap table.
%
% One row per lap. Columns = identity fields + every channel stat.
% The output table is ready to pass directly to smp_upload_supabase.
%
% Column naming: <channel_lower>_<op>
%   e.g. ground_speed_max, brake_pressure_front_mean_nz
%
% Ops extracted: max, min, mean, mean_non_zero (stored as mean_nz)
%
% Usage:
%   T = smp_flatten_stats(cache, 'AGP')
%
% Inputs:
%   cache       - compiled cache struct from smp_cache_load / smp_compile_event
%   event_name  - string label for this event, stored in every row
%
% Output:
%   T   - MATLAB table, one row per lap

    if nargin < 2, event_name = ''; end

    % ------------------------------------------------------------------ %
    %  Validate cache
    % ------------------------------------------------------------------ %
    if ~isfield(cache, 'stats') || ~isfield(cache, 'manifest')
        error('smp_flatten_stats: cache must have .stats and .manifest fields.');
    end

    all_gk = fieldnames(cache.stats);
    if isempty(all_gk)
        warning('smp_flatten_stats: cache.stats is empty — nothing to flatten.');
        T = table();
        return;
    end

    if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
        error('smp_flatten_stats: cache.manifest does not have a GroupKey column. Re-compile the cache.');
    end

    % ------------------------------------------------------------------ %
    %  Ops to extract and their SQL suffix
    %  stats field name  →  SQL column suffix
    % ------------------------------------------------------------------ %
    OPS = {
        'max',           'max';
        'min',           'min';
        'mean',          'mean';
        'mean_non_zero', 'mean_nz';
    };
    n_ops = size(OPS, 1);

    % ------------------------------------------------------------------ %
    %  Discover all channel names across all group keys
    %  (union — some cars may have channels others don't)
    % ------------------------------------------------------------------ %
    ch_set = {};
    for gi = 1:numel(all_gk)
        chs = fieldnames(cache.stats.(all_gk{gi}));
        ch_set = union(ch_set, chs, 'stable');
    end

    fprintf('smp_flatten_stats: %d group key(s), %d channel(s) discovered.\n', ...
        numel(all_gk), numel(ch_set));

    % ------------------------------------------------------------------ %
    %  Pre-build the SQL column names so they match supabase_setup.sql
    % ------------------------------------------------------------------ %
    % col_info(i) = struct with .sql_col, .ch_field, .op_field
    col_info = struct('sql_col', {}, 'ch_field', {}, 'op_field', {});
    for ci = 1:numel(ch_set)
        ch = ch_set{ci};
        for oi = 1:n_ops
            col_info(end+1).sql_col  = to_sql_name([ch '_' OPS{oi,2}]); %#ok
            col_info(end).ch_field   = ch;
            col_info(end).op_field   = OPS{oi,1};
        end
    end
    n_stat_cols = numel(col_info);

    % ------------------------------------------------------------------ %
    %  Loop group keys — build one row per lap
    % ------------------------------------------------------------------ %
    row_list = {};

    for gi = 1:numel(all_gk)
        gk      = all_gk{gi};
        stats_s = cache.stats.(gk);

        % ---- Find manifest rows for this group key ----
        m_mask = strcmp(cache.manifest.GroupKey, gk);
        if ~any(m_mask)
            fprintf('  [WARN] No manifest rows for GroupKey "%s" — skipping.\n', gk);
            continue;
        end
        m_rows = cache.manifest(m_mask, :);
        mr     = m_rows(1, :);   % all rows share identity; use first

        % ---- Get lap arrays from first available channel ----
        ch_fields = fieldnames(stats_s);
        if isempty(ch_fields)
            fprintf('  [WARN] No channels in stats for "%s" — skipping.\n', gk);
            continue;
        end

        ref_ch      = ch_fields{1};
        lap_numbers = stats_s.(ref_ch).lap_numbers;
        lap_times   = stats_s.(ref_ch).lap_times;
        n_laps      = numel(lap_numbers);

        fprintf('  %-45s  %d laps\n', gk, n_laps);

        % ---- Identity fields from manifest ----
        id.event        = event_name;
        id.venue        = get_manifest_str(mr, 'Venue');
        id.session      = get_manifest_str(mr, 'Session');
        id.year         = get_manifest_str(mr, 'Year');
        id.team         = get_manifest_str(mr, 'TeamAcronym');
        id.team_name    = get_manifest_str(mr, 'TeamName');
        id.driver       = get_manifest_str(mr, 'Driver');
        id.car_number   = get_manifest_str(mr, 'CarNumber');
        id.manufacturer = get_manifest_str(mr, 'Manufacturer');
        id.vehicle      = get_manifest_str(mr, 'Vehicle');
        id.group_key    = gk;
        id.source_file  = get_manifest_str(mr, 'Path');

        % ---- Build one row per lap ----
        for li = 1:n_laps
            r = struct();

            % Identity
            r.event        = id.event;
            r.venue        = id.venue;
            r.session      = id.session;
            r.year         = id.year;
            r.team         = id.team;
            r.team_name    = id.team_name;
            r.driver       = id.driver;
            r.car_number   = id.car_number;
            r.manufacturer = id.manufacturer;
            r.vehicle      = id.vehicle;
            r.group_key    = id.group_key;
            r.source_file  = id.source_file;
            r.lap_number   = lap_numbers(li);
            r.lap_time     = lap_times(li);

            % Channel stats
            for ci = 1:n_stat_cols
                cdef = col_info(ci);
                val  = NaN;
                if isfield(stats_s, cdef.ch_field)
                    ch_st = stats_s.(cdef.ch_field);
                    if isfield(ch_st, cdef.op_field)
                        v = ch_st.(cdef.op_field);
                        if isnumeric(v) && numel(v) >= li
                            val = v(li);
                            if ~isfinite(val), val = NaN; end
                        end
                    end
                end
                r.(cdef.sql_col) = val;
            end

            row_list{end+1} = r; %#ok
        end
    end

    if isempty(row_list)
        warning('smp_flatten_stats: no rows produced — check cache content.');
        T = table();
        return;
    end

    % ------------------------------------------------------------------ %
    %  Convert struct array to table
    % ------------------------------------------------------------------ %
    T = struct2table([row_list{:}]);

    fprintf('\nsmp_flatten_stats complete: %d rows, %d columns.\n', height(T), width(T));
    fprintf('  Event    : %s\n', event_name);
    u_sess = unique(T.session);
    u_team = unique(T.team);
    fprintf('  Sessions : %s\n', strjoin(u_sess(~cellfun(@isempty,u_sess))', ', '));
    fprintf('  Teams    : %s\n', strjoin(u_team(~cellfun(@isempty,u_team))', ', '));
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function name = to_sql_name(raw)
% Convert a string to a lowercase SQL-safe identifier.
% Matches the naming used in supabase_setup.sql.
    name = lower(raw);
    name = regexprep(name, '[^a-z0-9_]', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name) || ~isletter(name(1))
        name = ['ch_' name];
    end
    name = name(1:min(end, 63));
end

function s = get_manifest_str(row, col_name)
% Safely extract a string value from a single manifest table row.
    if ~ismember(col_name, row.Properties.VariableNames)
        s = '';
        return;
    end
    val = row.(col_name);
    if iscell(val),    val = val{1}; end
    if isstring(val),  val = char(val); end
    if isnumeric(val), val = num2str(val); end
    s = strtrim(char(val));
end
