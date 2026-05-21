% aeroMapChannels  Load manufacturer aero map and query all 9 aero
%                  channels at a given Roll for every time sample.
%
%   AERO = aeroMapChannels(FRH_ch, RRH_ch, manufacturer, map_dir)
%   AERO = aeroMapChannels(FRH_ch, RRH_ch, manufacturer, map_dir, roll_deg)
%
%   Inputs:
%       FRH_ch       - channel struct (.data in mm, .time in s)
%       RRH_ch       - channel struct (.data in mm, .time in s)
%       manufacturer - 'Ford' | 'Chev' | 'Toyota'
%       map_dir      - folder containing aeroMap_FORD.mat etc.
%       roll_deg     - scalar roll to query at (default 0 deg)
%
%   Output:
%       AERO - struct with all 9 channel column vectors (same length as
%              FRH_ch.data): CDa_SCx CLa_SCz CLf_SCzF CLr_SCzR
%              AB_FRT EFF CSa_Scy CSf_SCyF CSr_SCyR
%              Empty [] on failure.

function aero = aeroMapChannels(FRH_ch, RRH_ch, manufacturer, map_dir, roll_deg)

    if nargin < 5 || isempty(roll_deg)
        roll_deg = 0;
    end

    aero = [];

    mfr_map        = struct();
    mfr_map.Ford   = 'aeroMap_FORD.mat';
    mfr_map.Chevrolet   = 'aeroMap_CHEVROLET.mat';
    mfr_map.Toyota = 'aeroMap_TOYOTA.mat';

    % Normalise to Title case
    mfr = strtrim(manufacturer);
    if ~isempty(mfr)
        mfr(1)     = upper(mfr(1));
        mfr(2:end) = lower(mfr(2:end));
    end

    if ~isfield(mfr_map, mfr)
        fprintf('aeroMapChannels: unknown manufacturer ''%s''\n', manufacturer);
        return;
    end

    mat_path = fullfile(map_dir, mfr_map.(mfr));
    if ~isfile(mat_path)
        fprintf('aeroMapChannels: map file not found: %s\n', mat_path);
        return;
    end

    s   = load(mat_path, 'map');
    map = s.map;

    FRH  = FRH_ch.data(:);
    RRH  = interp1(RRH_ch.time, RRH_ch.data, FRH_ch.time, 'linear', 'extrap');
    RRH  = RRH(:);
    Roll = repmat(roll_deg, size(FRH));

    aero = aeroMapQuery(map, FRH, RRH, Roll);

end
