function alias = smp_alias_load(alias_file)
% SMP_ALIAS_LOAD  Load keyword alias tables from eventAlias.xlsx.
%
% Excel file has three sheets: EVENT, VENUE, SESSION  (names are case-sensitive)
%
% Sheet layout — same structure on all three sheets:
%   Column A  =  Canonical name  (what YOU want to filter by, e.g. 'Bathurst 1000')
%   Column B+ =  Aliases         (what the MoTeC files might actually say — up to 20)
%
% Example sheet "EVENT":
%   Canonical        | V8SC_Name              | Alias2    | Alias3 | ...
%   Bathurst 1000    | REPCO Bathurst 1000    | BAT       | B1000  |
%   Adelaide 500     | Penrite Adelaide 500   | ADE       |        |
%   Sandown          | Penrite Sandown 500    | SAN       |        |
%
% Example sheet "SESSION":
%   Canonical   | V8SC_Name          | Alias2
%   Race 1      | Race_1             | R1
%   Race 2      | Race_2             | R2
%   Qualifying  | Qualifying_1       | Q
%   Practice 1  | Practice_1         | P1
%
% How lookups work (bidirectional):
%   - Passing 'BAT' as a filter keyword → resolves to 'Bathurst 1000'
%     → then matches every row whose Event field contains ANY of:
%       'BAT', 'Bathurst 1000', 'REPCO Bathurst 1000', 'B1000', etc.
%   - So it doesn't matter which naming convention a team used in their log —
%     as long as their name is in the alias list, it will match.
%
% Returns:
%   alias.event.lookup    containers.Map  key=any_alias_lower → canonical
%   alias.venue.lookup    containers.Map  key=any_alias_lower → canonical
%   alias.session.lookup  containers.Map  key=any_alias_lower → canonical
%   alias.year.lookup     containers.Map  (empty — no sheet, raw match only)
%   alias.driver.lookup   containers.Map  (empty — no sheet, raw match only)
%
% Usage:
%   alias = smp_alias_load('C:\SMP\config\eventAlias.xlsx');
%   alias = smp_alias_load([]);   % no file — returns empty maps, raw matching

    % Sheets that exist in the Excel file
    SHEETS = {'EVENT', 'VENUE', 'SESSION'};

    % All filter categories (including those without alias sheets)
    ALL_CATS = {'event', 'venue', 'session', 'year', 'driver'};

    % Initialise empty lookup maps for every category
    alias = struct();
    for i = 1:numel(ALL_CATS)
        alias.(ALL_CATS{i}).lookup = containers.Map('KeyType','char','ValueType','char');
    end

    % --- Validate file ---
    if nargin < 1 || isempty(alias_file)
        fprintf('[smp_alias_load] No alias file specified — raw string matching only.\n\n');
        return;
    end
    if ~exist(alias_file, 'file')
        fprintf('[smp_alias_load] File not found: %s\n', alias_file);
        fprintf('[smp_alias_load] Running without aliases — raw string matching only.\n\n');
        return;
    end

    fprintf('Loading alias tables: %s\n', alias_file);

    for i = 1:numel(SHEETS)
        sheet_name = SHEETS{i};          % e.g. 'EVENT'
        cat_key    = lower(sheet_name);  % e.g. 'event'
        lut        = alias.(cat_key).lookup;

        try
            T = readtable(alias_file, ...
                'Sheet',              sheet_name, ...
                'TextType',           'char');

            if height(T) == 0 || width(T) == 0
                fprintf('  [%-8s] Empty sheet — skipping.\n', sheet_name);
                continue;
            end

            var_names   = T.Properties.VariableNames;
            n_canonical = 0;
            n_aliases   = 0;

            for row = 1:height(T)

                % Column A — canonical name
                canonical = clean_str(T.(var_names{1}){row});
                if isempty(canonical), continue; end

                % The canonical maps to itself
                lut(lower(canonical)) = canonical;
                n_canonical = n_canonical + 1;

                % Columns B onwards — all aliases for this canonical
                for col = 2:numel(var_names)
                    alias_str = clean_str(T.(var_names{col}){row});
                    if isempty(alias_str), continue; end
                    lut(lower(alias_str)) = canonical;
                    n_aliases = n_aliases + 1;
                end
            end

            alias.(cat_key).lookup = lut;
            fprintf('  [%-8s] %d canonical entries  +  %d aliases  =  %d total keys\n', ...
                sheet_name, n_canonical, n_aliases, lut.Count);

        catch ME
            fprintf('  [%-8s] Could not load sheet: %s\n', sheet_name, ME.message);
        end
    end

    fprintf('\n');
end


% -----------------------------------------------------------------------
function str = clean_str(raw)
% Convert a table cell value to a trimmed char string. Returns '' for NaN/empty.
    if isnumeric(raw)
        if isempty(raw) || (isscalar(raw) && isnan(raw))
            str = '';
        else
            str = strtrim(num2str(raw));
        end
    else
        str = strtrim(char(raw));
        if strcmpi(str, 'NaN'), str = ''; end
    end
end
