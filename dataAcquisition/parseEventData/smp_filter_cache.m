function SMP_out = smp_filter_cache(cache, alias, varargin)
% SMP_FILTER_CACHE  Filter a compiled cache down to specific runs.
%
% Replaces smp_filter() for the new stream-mode cache architecture.
% Works against cache.manifest, cache.stats, and cache.traces.
% Returns a filtered SMP struct that smp_plot_from_config can consume.
%
% The output struct matches the shape expected by smp_plot_from_config:
%   SMP_out.(team_acronym).meta       - table of matching runs
%   SMP_out.(team_acronym).stats      - cell array of stats structs
%   SMP_out.(team_acronym).traces     - cell array of traces structs
%   SMP_out.(team_acronym).channels   - cell array (empty in stream mode,
%                                       populated in bulk mode for compatibility)
%
% Usage — same as smp_filter():
%   SMP = smp_filter_cache(cache, alias, 'Session', 'RA1')
%   SMP = smp_filter_cache(cache, alias, 'Session', 'RA1', 'Team', {'T8R'})
%   SMP = smp_filter_cache(cache, alias, 'Manufacturer', 'Ford')
%
% Parameters (all optional):
%   'Event'        char or cell
%   'Session'      char or cell
%   'Venue'        char or cell
%   'Year'         char or cell
%   'Driver'       char or cell
%   'Team'         char or cell  exact match on TeamAcronym
%   'Car'          char or cell
%   'Manufacturer' char or cell
%   'LoadOK'       logical       (default: true)

    p = inputParser();
    p.FunctionName = 'smp_filter_cache';
    addParameter(p, 'Event',        {});
    addParameter(p, 'Session',      {});
    addParameter(p, 'Venue',        {});
    addParameter(p, 'Year',         {});
    addParameter(p, 'Driver',       {});
    addParameter(p, 'Team',         {});
    addParameter(p, 'Car',          {});
    addParameter(p, 'Manufacturer', {});
    addParameter(p, 'LoadOK',       true);
    parse(p, varargin{:});
    opts = p.Results;

    if isempty(alias)
        alias = smp_alias_load([]);
    end

    T           = cache.manifest;
    n           = height(T);
    mask        = true(n, 1);
    team_filter = to_cellstr(opts.Team);

    % ------------------------------------------------------------------
    %  Apply LoadOK filter
    % ------------------------------------------------------------------
    if opts.LoadOK && ismember('LoadOK', T.Properties.VariableNames)
        mask = mask & logical(T.LoadOK);
    end

    % ------------------------------------------------------------------
    %  Keyword filters (same logic as smp_filter)
    % ------------------------------------------------------------------
    defs = {
        opts.Event,        'event',   'Venue',        'partial';
        opts.Session,      'session', 'Session',      'partial';
        opts.Venue,        'venue',   'Venue',        'partial';
        opts.Year,         [],        'Year',         'partial';
        opts.Driver,       [],        'Driver',       'partial';
        opts.Car,          [],        'CarNumber',    'partial';
        opts.Manufacturer, [],        'Manufacturer', 'partial';
    };

    for f = 1:size(defs, 1)
        keywords   = defs{f, 1};
        cat        = defs{f, 2};
        col_name   = defs{f, 3};
        match_mode = defs{f, 4};

        if isempty(keywords), continue; end
        keywords = to_cellstr(keywords);

        if ~isempty(cat) && isfield(alias, cat)
            terms = aliases_for_keywords(keywords, alias.(cat).lookup);
        else
            terms = keywords;
        end

        if ~ismember(col_name, T.Properties.VariableNames)
            fprintf('  [WARN] Column "%s" not in manifest — skipping.\n', col_name);
            continue;
        end

        col_vals = col_to_cellstr(T, col_name);
        col_mask = false(n, 1);

        for k = 1:numel(terms)
            term = lower(strtrim(terms{k}));
            if isempty(term), continue; end
            switch match_mode
                case 'partial'
                    col_mask = col_mask | contains(lower(col_vals), term);
                case 'exact'
                    col_mask = col_mask | strcmpi(col_vals, term);
            end
        end

        mask = mask & col_mask;
    end

    % ------------------------------------------------------------------
    %  Build output struct grouped by team
    % ------------------------------------------------------------------
    SMP_out   = struct();
    T_filtered = T(mask, :);
    total_out  = height(T_filtered);

    fprintf('=== smp_filter_cache: %d/%d runs match ===\n', total_out, n);

    if total_out == 0
        fprintf('  No matching runs found.\n\n');
        return;
    end

    team_keys = unique(T_filtered.TeamAcronym);

    for t = 1:numel(team_keys)
        tk = char(team_keys(t));

        % Skip if team pre-filter excludes this team
        if ~isempty(team_filter) && ~any(strcmpi(team_filter, tk))
            continue;
        end

        team_mask = strcmp(T_filtered.TeamAcronym, tk);
        team_rows = T_filtered(team_mask, :);
        [~, unique_idx] = unique(team_rows.GroupKey, 'stable');
        team_rows = team_rows(unique_idx, :);
        n_runs    = height(team_rows);

        stats_cells  = cell(n_runs, 1);
        traces_cells = cell(n_runs, 1);
        ch_cells     = cell(n_runs, 1);   % bulk compatibility

        for r = 1:n_runs
            fpath = team_rows.Path{r};

            % Derive group key from file path (same logic as smp_compile_event)
            % The group key was stored under cache.stats/traces
            gk = find_group_key_for_path(cache, fpath);

            if ~isempty(gk)
                if isfield(cache.stats, gk)
                    stats_cells{r} = cache.stats.(gk);
                end
                if isfield(cache.traces, gk)
                    traces_cells{r} = cache.traces.(gk);
                end
            end

            % Bulk mode backwards compatibility
            if strcmp(cache.mode, 'bulk') && isKey(cache.channels, fpath)
                ch_cells{r} = cache.channels(fpath);
            end
        end

        SMP_out.(matlab.lang.makeValidName(tk)).meta     = team_rows;
        SMP_out.(matlab.lang.makeValidName(tk)).stats    = stats_cells;
        SMP_out.(matlab.lang.makeValidName(tk)).traces   = traces_cells;
        SMP_out.(matlab.lang.makeValidName(tk)).channels = ch_cells;

        fprintf('  %-8s  %d run(s)\n', tk, n_runs);
    end

    fprintf('\n');
end


% ======================================================================= %
function gk = find_group_key_for_path(cache, fpath)
% Find which group key in cache.stats corresponds to a given file path.
% The manifest row for this file was added with the group_key, but we
% didn't store the key explicitly in the manifest table.
% Derive it: group_key = makeValidName of the key field from smp_append_stints
% which was built as: makeValidName(team|driver|session|car)
%
% Simpler approach: iterate stats fields and match by trying to find
% a stats entry whose lap_numbers match what we'd expect.
%
% Actually simplest: store group_key in the manifest. We'll do that here
% by checking if manifest has a GroupKey column (added by smp_compile_event
% if we upgrade it), else fall back to path-derived key.

    gk = '';

    % Check if manifest has GroupKey column (future-proofed)
    if ismember('GroupKey', cache.manifest.Properties.VariableNames)
        row_mask = strcmp(cache.manifest.Path, fpath);
        if any(row_mask)
            gk = char(cache.manifest.GroupKey(row_mask));
            gk = matlab.lang.makeValidName(gk);
            return;
        end
    end

    % Fallback: try path-derived key (single-file groups)
    [~, fname] = fileparts(fpath);
    candidate  = matlab.lang.makeValidName(fname);
    if isfield(cache.stats, candidate)
        gk = candidate;
        return;
    end

    % Last resort: search all keys — find the one containing this file's
    % driver name from the manifest
    row_mask = strcmp(cache.manifest.Path, fpath);
    if ~any(row_mask), return; end
    driver_raw = lower(strtrim(char(string(cache.manifest.Driver(row_mask)))));
    driver_key = matlab.lang.makeValidName(driver_raw);

    stat_keys = fieldnames(cache.stats);
    for k = 1:numel(stat_keys)
        if contains(lower(stat_keys{k}), driver_key)
            gk = stat_keys{k};
            return;
        end
    end
end


% ======================================================================= %
%  ALIAS AND STRING HELPERS  (duplicated from smp_filter for self-containment)
% ======================================================================= %
function terms = aliases_for_keywords(keywords, lut)
    terms = {};
    if isempty(lut) || lut.Count == 0
        terms = keywords;
        return;
    end
    all_keys   = keys(lut);
    all_values = values(lut);
    for i = 1:numel(keywords)
        kw = lower(strtrim(keywords{i}));
        if ~isKey(lut, kw)
            terms{end+1} = kw; %#ok
            continue;
        end
        target = lut(kw);
        for j = 1:numel(all_keys)
            if strcmp(all_values{j}, target) && ~ismember(all_keys{j}, terms)
                terms{end+1} = all_keys{j}; %#ok
            end
        end
    end
    if isempty(terms), terms = keywords; end
    terms = unique(terms);
end

function out = to_cellstr(input)
    if isempty(input), out = {}; return; end
    if ischar(input) || isstring(input)
        out = {char(input)};
    elseif iscell(input)
        out = cellfun(@(x) char(string(x)), input(:)', 'UniformOutput', false);
    else
        out = {char(string(input))};
    end
    out = out(~cellfun(@(x) isempty(strtrim(x)), out));
end

function strs = col_to_cellstr(T, col_name)
    raw = T.(col_name);
    if isnumeric(raw)
        strs = arrayfun(@(x) char(string(x)), raw, 'UniformOutput', false);
    elseif isstring(raw)
        strs = cellstr(raw);
    elseif iscell(raw)
        strs = cellfun(@(x) char(string(x)), raw, 'UniformOutput', false);
    else
        strs = cellstr(string(raw));
    end
    strs = strs(:);
end
