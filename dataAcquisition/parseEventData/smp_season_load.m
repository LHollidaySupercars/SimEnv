function season = smp_season_load(filepath)
% SMP_SEASON_LOAD  Load the season overview table from Excel.
%
% Reads the seasonOverview.xlsx file which maps track acronyms to valid
% lap time windows. These replace all hardcoded min/max lap time values.
%
% Expected Excel columns (any order, case-insensitive headers):
%   Track    - three-letter acronym, e.g. 'SMP', 'BAT', 'ADE'
%   MinLT    - minimum valid lap time in seconds
%   MaxLT    - maximum valid lap time in seconds
%
% Usage:
%   season = smp_season_load('C:\SimEnv\trackDB\seasonOverview.xlsx')
%
%   % Look up limits for a specific track:
%   [min_lt, max_lt] = smp_season_get(season, 'SMP')
%
% Output:
%   season  - struct with fields:
%     .table    - full MATLAB table as read from Excel
%     .tracks   - cell array of track acronyms (upper case)
%     .min_lt   - map: track acronym -> MinLT (double)
%     .max_lt   - map: track acronym -> MaxLT (double)

    if ~exist(filepath, 'file')
        error('smp_season_load: File not found: %s', filepath);
    end

    fprintf('Loading season overview: %s\n', filepath);
    T = readtable(filepath);
    fprintf('  %d track(s) found.\n', height(T));

    % ------------------------------------------------------------------
    %  Detect column names (case-insensitive)
    % ------------------------------------------------------------------
    cols = T.Properties.VariableNames;
    track_col = find_col(cols, {'Track','track','TRACK'});
    minlt_col = find_col(cols, {'MinLT','minlt','MinLapTime','min_lt'});
    maxlt_col = find_col(cols, {'MaxLT','maxlt','MaxLapTime','max_lt'});

    if isempty(track_col)
        error('smp_season_load: Cannot find "Track" column. Found: %s', ...
            strjoin(cols, ', '));
    end
    if isempty(minlt_col)
        error('smp_season_load: Cannot find "MinLT" column. Found: %s', ...
            strjoin(cols, ', '));
    end
    if isempty(maxlt_col)
        error('smp_season_load: Cannot find "MaxLT" column. Found: %s', ...
            strjoin(cols, ', '));
    end

    % ------------------------------------------------------------------
    %  Build lookup structs
    % ------------------------------------------------------------------
    season.table  = T;
    season.tracks = {};
    season.min_lt = struct();
    season.max_lt = struct();

    for i = 1:height(T)
        raw_track = strtrim(char(string(T.(track_col){i})));
        track_key = upper(raw_track);
        safe_key  = matlab.lang.makeValidName(track_key);

        min_val = T.(minlt_col)(i);
        max_val = T.(maxlt_col)(i);

        if isempty(track_key) || isnan(min_val) || isnan(max_val)
            fprintf('  [WARN] Skipping row %d — missing track or lap time values.\n', i);
            continue;
        end

        season.tracks{end+1}   = track_key;
        season.min_lt.(safe_key) = min_val;
        season.max_lt.(safe_key) = max_val;

        fprintf('  %-6s  MinLT=%.1fs  MaxLT=%.1fs\n', track_key, min_val, max_val);
    end

    fprintf('\n');
end


% ======================================================================= %

% ======================================================================= %
function col = find_col(all_cols, candidates)
    col = '';
    for i = 1:numel(candidates)
        if ismember(candidates{i}, all_cols)
            col = candidates{i};
            return;
        end
    end
end
