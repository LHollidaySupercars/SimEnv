function driver_map = smp_driver_alias_load(filepath, sheet)
% SMP_DRIVER_ALIAS_LOAD  Load driver alias table with colour definitions.
%
% Reads the driverAlias.xlsx file with the following known column headers:
%
%   Number            row number (ignored)
%   Unique Drivers IDs  ignored
%   NUM               car number (ignored)
%   CLR               colour string  [R, G, B]  — 0-255 or 0-1
%   DRV               canonical driver full name  ← used as the key
%   DRV_TLA           3-letter driver acronym     ← priority alias
%   SPN_TM            sponsor/team (ignored)
%   TM                team name (ignored)
%   TM_TLA            team TLA (ignored)
%   MAN               manufacturer (ignored)
%   MAN_TLA           manufacturer TLA (ignored)
%   Alias1..Alias20   additional name aliases
%
% Usage:
%   driver_map = smp_driver_alias_load('C:\SMP\config\driverAlias.xlsx')
%   driver_map = smp_driver_alias_load('C:\SMP\config\driverAlias.xlsx', 'Sheet1')
%
% Returns:
%   driver_map  - struct, one field per driver (sanitised DRV name).
%     .canonical   char       full driver name (DRV column)
%     .tla         char       3-letter acronym (DRV_TLA column)
%     .colour      [R G B]    normalised 0-1 RGB from CLR column
%     .aliases     cell       all searchable names (lowercase):
%                             canonical, tla, Alias1..Alias20
%
% Colour lookup helper (defined at bottom of this file):
%   col = smp_driver_colour(driver_map, 'T. Mostert')
%   col = smp_driver_colour(driver_map, 'MST')   % TLA also works

    if nargin < 2 || isempty(sheet)
        sheet = 1;
    end

    driver_map = struct();

    if isempty(filepath) || ~exist(filepath, 'file')
        fprintf('[smp_driver_alias_load] No file found: %s\n', filepath);
        fprintf('[smp_driver_alias_load] Driver colours unavailable.\n');
        return;
    end

    fprintf('Loading driver alias table: %s\n', filepath);
    T = readtable(filepath, 'Sheet', sheet, ...
                  'ReadVariableNames',  true);

    n_rows    = height(T);
    var_names = T.Properties.VariableNames;

    % ------------------------------------------------------------------ %
    %  Locate known columns by exact header name
    % ------------------------------------------------------------------ %
    col_drv     = find_col_exact(var_names, 'DRV');
    col_tla     = find_col_exact(var_names, 'DRV_TLA');
    col_clr     = find_col_exact(var_names, 'CLR');
    col_num     = find_col_exact(var_names, 'NUM');
    col_man     = find_col_exact(var_names, 'MAN');
    col_man_tla = find_col_exact(var_names, 'MAN_TLA');
    col_tm_tla  = find_col_exact(var_names, 'TM_TLA');

    % Alias columns — Alias1 through Alias20
    alias_col_indices = [];
    for a = 1:20
        idx = find_col_exact(var_names, sprintf('Alias%d', a));
        if ~isempty(idx)
            alias_col_indices(end+1) = idx; %#ok
        end
    end

    % Validate required columns
    if isempty(col_drv)
        error('smp_driver_alias_load: Cannot find "DRV" column in %s', filepath);
    end
    if isempty(col_clr)
        warning('smp_driver_alias_load: Cannot find "CLR" column — all drivers will use fallback colour.');
    end
    if isempty(col_tla)
        warning('smp_driver_alias_load: Cannot find "DRV_TLA" column — TLA matching unavailable.');
    end

    fprintf('  Columns found: DRV=%d  DRV_TLA=%d  CLR=%d  NUM=%d  Alias cols=%d\n', ...
        col_drv, iif(isempty(col_tla),0,col_tla), ...
        iif(isempty(col_clr),0,col_clr), ...
        iif(isempty(col_num),0,col_num), ...
        numel(alias_col_indices));

    % ------------------------------------------------------------------ %
    %  Read each row
    % ------------------------------------------------------------------ %
    loaded = 0;
    for r = 1:n_rows
        % Canonical name from DRV column
        canonical = strtrim(char(string(T{r, col_drv})));
        if isempty(canonical) || strcmpi(canonical, 'NaN') || strcmpi(canonical, 'missing')
            continue;
        end

        % Colour from CLR column
        if ~isempty(col_clr)
            col_str = strtrim(char(string(T{r, col_clr})));
            colour  = parse_rgb(col_str);
        else
            colour = [0.55 0.55 0.55];
        end

        % TLA
        tla = '';
        if ~isempty(col_tla)
            tla = strtrim(char(string(T{r, col_tla})));
            if strcmpi(tla, 'NaN') || strcmpi(tla, 'missing'), tla = ''; end
        end

        % ---- Build alias list ----
        % Order: canonical → TLA → Alias1..N
        % All stored lowercase for case-insensitive matching
        aliases = {lower(canonical)};

        if ~isempty(tla)
            aliases{end+1} = lower(tla); %#ok
        end

        for ci = alias_col_indices
            a = strtrim(char(string(T{r, ci})));
            if ~isempty(a) && ~strcmpi(a,'NaN') && ~strcmpi(a,'missing')
                aliases{end+1} = lower(a); %#ok
            end
        end

        % Manufacturer — prefer full MAN name, fall back to MAN_TLA
        man_str = '';
        for col_m = [col_man, col_man_tla]
            if ~isempty(col_m)
                man_raw = strtrim(char(string(T{r, col_m})));
                if ~isempty(man_raw) && ~strcmpi(man_raw, 'NaN') && ~strcmpi(man_raw, 'missing')
                    man_str = man_raw;
                    break;   % stop at first valid value
                end
            end
        end

        % Team TLA from TM_TLA column
        tm_tla_str = '';
        if ~isempty(col_tm_tla)
            tm_raw = strtrim(char(string(T{r, col_tm_tla})));
            if ~isempty(tm_raw) && ~strcmpi(tm_raw, 'NaN') && ~strcmpi(tm_raw, 'missing')
                tm_tla_str = tm_raw;
            end
        end

        % Car number from NUM column
        num_str = '';
        if ~isempty(col_num)
            num_raw = T{r, col_num};
            if iscell(num_raw), num_raw = num_raw{1}; end
            if isnumeric(num_raw)
                if ~isnan(num_raw)
                    num_str = num2str(round(num_raw));
                end
            else
                num_str = strtrim(char(string(num_raw)));
                if strcmpi(num_str,'NaN') || strcmpi(num_str,'missing')
                    num_str = '';
                end
            end
        end

        % ---- Store under sanitised DRV name ----
        key = make_key(canonical);
        driver_map.(key).canonical    = canonical;
        driver_map.(key).tla          = tla;
        driver_map.(key).num          = num_str;
        driver_map.(key).manufacturer = man_str;
        driver_map.(key).team_tla     = tm_tla_str;
        driver_map.(key).colour       = colour;
        driver_map.(key).aliases      = aliases;

        loaded = loaded + 1;
        fprintf('  %-30s  TLA=%-4s  NUM=%-4s  colour=[%.2f %.2f %.2f]  aliases=%d\n', ...
            canonical, tla, num_str, colour(1), colour(2), colour(3), numel(aliases)-1);
    end

    fprintf('smp_driver_alias_load: %d driver(s) loaded.\n\n', loaded);
end


% ======================================================================= %
function col = smp_driver_colour(driver_map, name, fallback)
% SMP_DRIVER_COLOUR  Look up a driver's colour from the driver_map.
%
% Accepts full name, TLA, or any alias — case-insensitive.
%
% Usage:
%   col = smp_driver_colour(driver_map, 'T. Mostert')
%   col = smp_driver_colour(driver_map, 'MST')
%   col = smp_driver_colour(driver_map, 'MST', [0.5 0.5 0.5])

    if nargin < 3
        fallback = [0.55 0.55 0.55];
    end

    col = fallback;
    if isempty(driver_map) || ~isstruct(driver_map)
        return;
    end

    name_lower = lower(strtrim(name));
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        if any(strcmp(entry.aliases, name_lower))
            col = entry.colour;
            return;
        end
    end
    % Not found — silent fallback, caller gets grey
end


% ======================================================================= %
%  UTILITIES
% ======================================================================= %
function idx = find_col_exact(var_names, target)
% Find a column index by exact case-insensitive header match.
    idx = find(strcmpi(var_names, target), 1);
    if isempty(idx), idx = []; end
end

function col = parse_rgb(str)
% Parse "[R, G, B]" or "R, G, B" string into [R G B] double.
% Auto-detects 0-255 vs 0-1 range.
    str  = regexprep(str, '[\[\]\(\)]', '');
    parts = strsplit(str, {',',' '}, 'CollapseDelimiters', true);
    parts = parts(~cellfun(@isempty, parts));

    if numel(parts) ~= 3
        col = [0.55 0.55 0.55];
        return;
    end

    vals = cellfun(@str2double, parts);
    if any(isnan(vals))
        col = [0.55 0.55 0.55];
        return;
    end

    if any(vals > 1)
        vals = vals / 255;
    end
    col = min(max(vals(:)', 0), 1);
end

function key = make_key(name)
    key = regexprep(name, '[^a-zA-Z0-9]', '_');
    if ~isempty(key) && isstrprop(key(1), 'digit')
        key = ['d_', key];
    end
end

function out = iif(cond, a, b)
    if cond, out = a; else, out = b; end
end