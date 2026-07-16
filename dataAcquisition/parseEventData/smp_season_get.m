function [min_lt, max_lt] = smp_season_get(season, track_acronym)
% SMP_SEASON_GET  Retrieve MinLT and MaxLT for a given track acronym.
%
% Usage:
%   [min_lt, max_lt] = smp_season_get(season, 'SMP')
%
% Returns defaults (10s / 600s) with a warning if the track is not found.

    safe_key = matlab.lang.makeValidName(upper(strtrim(track_acronym)));

    if isfield(season.min_lt, safe_key) && isfield(season.max_lt, safe_key)
        min_lt = season.min_lt.(safe_key);
        max_lt = season.max_lt.(safe_key);
    else
        warning('smp_season_get: Track "%s" not found in season overview. Using defaults (10/600s).', ...
            track_acronym);
        min_lt = 10;
        max_lt = 600;
    end
end