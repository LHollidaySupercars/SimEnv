function SMP_out = smp_filter(SMP, alias, varargin)
% SMP_FILTER  Filter an SMP struct down to only the runs you want.
%
% Works against SMP.(team).{meta, channels, info}.
% Returns a new SMP struct — same shape, only matching runs.
% Teams with zero remaining runs are dropped from the output.
%
% Matching rules:
%   - Multiple keywords within one category are OR'd
%   - Multiple categories are AND'd
%   - Event/Session/Venue keywords resolve through alias tables so
%     shorthand ('BAT') matches whatever alias the team used in their log
%   - Year/Driver/Team/Car/Manufacturer use raw string matching
%
% -------------------------------------------------------------------------
% Usage:
%   alias  = smp_alias_load('C:\SMP\config\eventAlias.xlsx');
%   SMP2   = smp_filter(SMP, alias, 'Event',   'BAT');
%   SMP2   = smp_filter(SMP, alias, 'Event',   'BAT',       'Session', 'R1');
%   SMP2   = smp_filter(SMP, alias, 'Event',   'BAT',       'Session', {'R1','R2'});
%   SMP2   = smp_filter(SMP, alias, 'Year',    '2025',      'Venue',   'SAN');
%   SMP2   = smp_filter(SMP, alias, 'Team',    {'T8R','WAU'});
%   SMP2   = smp_filter(SMP, alias, 'Manufacturer', 'Ford', 'Session', 'R1');
%   SMP2   = smp_filter(SMP, [],   'Session',  'Race 1');   % no alias file
%
% -------------------------------------------------------------------------
% Parameters (all optional):
%   'Event'        char or cell  Resolved via EVENT alias sheet → matches Venue column
%   'Session'      char or cell  Resolved via SESSION alias sheet
%   'Venue'        char or cell  Resolved via VENUE alias sheet
%   'Year'         char or cell  Raw partial match
%   'Driver'       char or cell  Raw partial match
%   'Team'         char or cell  Exact match on TeamAcronym — pre-filters which
%                                team nodes are even examined
%   'Car'          char or cell  Raw partial match on CarNumber
%   'Manufacturer' char or cell  Raw partial match
%   'LoadOK'       logical       Only include successfully loaded runs (default: true)

    p = inputParser();
    p.FunctionName = 'smp_filter';
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

    % Normalise Team filter for fast pre-check
    team_filter = to_cellstr(opts.Team);

    SMP_out   = struct();
    total_in  = 0;
    total_out = 0;

    fprintf('=== smp_filter ===\n');

    team_keys = fieldnames(SMP);

    for t = 1:numel(team_keys)
        tk   = team_keys{t};
        node = SMP.(tk);
        T    = node.meta;
        n    = height(T);
        total_in = total_in + n;

        % Team pre-filter — skip the whole node if it doesn't match
        if ~isempty(team_filter) && ~any(strcmpi(team_filter, tk))
            continue;
        end

        mask = true(n, 1);

        % LoadOK
        if opts.LoadOK && ismember('LoadOK', T.Properties.VariableNames)
            mask = mask & logical(T.LoadOK);
        end

        % ------------------------------------------------------------------
        %  Keyword filters
        %  {opts_value,  alias_category,  meta_column,   match_mode}
        %
        %  NOTE: 'Event' matches against the Venue column because MoTeC logs
        %  store the event name in the venue field (info.event is always empty).
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

            % Resolve to full set of alias strings to search for
            if ~isempty(cat) && isfield(alias, cat)
                terms = aliases_for_keywords(keywords, alias.(cat).lookup);
            else
                terms = keywords;
            end

            if ~ismember(col_name, T.Properties.VariableNames)
                fprintf('  [WARN] Column "%s" not in meta — skipping.\n', col_name);
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

        n_kept    = sum(mask);
        total_out = total_out + n_kept;

        if n_kept == 0, continue; end   % drop teams with no matching runs

        rows = find(mask);
        SMP_out.(tk).meta     = T(rows, :);
        SMP_out.(tk).channels = node.channels(rows);
        SMP_out.(tk).info     = node.info(rows);

        fprintf('  %-8s  %d/%d runs kept\n', tk, n_kept, n);
    end

    fprintf('Result: %d/%d runs across %d team(s).\n\n', ...
        total_out, total_in, numel(fieldnames(SMP_out)));
end


% =======================================================================
%  ALIAS RESOLUTION
% =======================================================================
function terms = aliases_for_keywords(keywords, lut)
% Resolve each keyword to its canonical then return all sibling alias strings.
% The canonical is NOT included — MoTeC files only contain alias values.
% If a keyword isn't in the table, it's kept as-is for raw matching.

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
            terms{end+1} = kw;  %#ok  raw fallback
            continue;
        end

        target = lut(kw);   % canonical

        for j = 1:numel(all_keys)
            if strcmp(all_values{j}, target) && ~ismember(all_keys{j}, terms)
                terms{end+1} = all_keys{j};  %#ok
            end
        end
    end

    if isempty(terms), terms = keywords; end
    terms = unique(terms);
end


% =======================================================================
%  HELPERS
% =======================================================================
function out = to_cellstr(input)
    if isempty(input)
        out = {};
        return;
    end
    if ischar(input) || isstring(input)
        out = {char(input)};
    elseif isnumeric(input) || islogical(input)
        out = arrayfun(@(x) char(string(x)), input(:)', 'UniformOutput', false);
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
