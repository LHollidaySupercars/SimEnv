% aeroMapQuery  Query a 3-axis aero map at given ride height and roll conditions.
%
%   OUT = aeroMapQuery(MAP, FRH_mm, RRH_mm, Roll_deg)
%
%   Inputs:
%       MAP      - struct produced by aeroMapBuild
%       FRH_mm   - front ride height (mm), scalar or [N x 1]
%       RRH_mm   - rear ride height (mm), scalar or [N x 1]
%       Roll_deg - roll angle (deg), scalar or [N x 1]
%
%   Output:
%       OUT - struct with fields:
%               CDa_SCx, CLa_SCz, CLf_SCzF, CLr_SCzR,
%               AB_FRT, EFF, CSa_Scy, CSf_SCyF, CSr_SCyR

function out = aeroMapQuery(map, FRH_mm, RRH_mm, Roll_deg)

    out_channels = {'CDa_SCx','CLa_SCz','CLf_SCzF','CLr_SCzR', ...
                    'AB_FRT','EFF','CSa_Scy','CSf_SCyF','CSr_SCyR'};

    for k = 1:numel(out_channels)
        ch = out_channels{k};
        out.(ch) = map.interp.(ch)(FRH_mm, RRH_mm, Roll_deg);
    end

end