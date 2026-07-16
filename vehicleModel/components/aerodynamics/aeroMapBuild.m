% aeroMapBuild  Build a 3-axis aero map from wind tunnel data (Excel).
%
%   MAP = aeroMapBuild(EXCEL_FILE)
%   MAP = aeroMapBuild(EXCEL_FILE, SHEET)
%   MAP = aeroMapBuild(EXCEL_FILE, SHEET, ROAD_SPD)
%   MAP = aeroMapBuild(EXCEL_FILE, SHEET, ROAD_SPD, MANUFACTURER)
%
%   MANUFACTURER (optional) sets the output filename to aeroMap_<MANUFACTURER>.mat
%   so that aeroMapChannels can locate it. E.g. 'FORD', 'CHEVROLET', 'TOYOTA'.
%   If omitted, the sheet name is used as fallback.
%       FRH_mm, RRH_mm, roll_deg  (inputs)
%       CDa_SCx, CLa_SCz, CLf_SCzF, CLr_SCzR, AB_FRT, EFF,
%       CSa_Scy, CSf_SCyF, CSr_SCyR  (outputs)
%
%   If road_spd / yaw_deg columns are present the table is filtered to a
%   single road speed and yaw==0 before building the grid.
%   ROAD_SPD defaults to the unique value if only one exists, otherwise
%   the highest value (typical nominal tunnel speed).
%
%   Returns MAP struct with:
%       .FRH_mm, .RRH_mm, .Roll_deg   - sorted grid vectors
%       .CDa_SCx, .CLa_SCz, ...       - [nFRH x nRRH x nRoll] arrays
%       .interp.CDa_SCx, ...          - griddedInterpolant objects

function map = aeroMapBuild(excel_file, sheet, road_spd_filter, manufacturer)

    if nargin < 2, sheet = 1; end
    if nargin < 4, manufacturer = ''; end

    % --- Load raw data -----------------------------------------------------------
    tbl = readtable(excel_file, 'Sheet', sheet);

    cols = tbl.Properties.VariableNames;

    % --- Filter road_spd if column present ---------------------------------------
    % Default: accept runs within 1 m/s of 55.5 m/s (nominal tunnel speed).
    % Pass ROAD_SPD as a [centre, tolerance] pair or scalar to override.
    default_spd     = 55.5;
    default_spd_tol = 1.0;

    if ismember('road_spd', cols)
        if nargin < 3 || isempty(road_spd_filter)
            spd_centre = default_spd;
            spd_tol    = default_spd_tol;
        elseif numel(road_spd_filter) == 2
            spd_centre = road_spd_filter(1);
            spd_tol    = road_spd_filter(2);
        else
            spd_centre = road_spd_filter(1);
            spd_tol    = default_spd_tol;
        end

        n_before = height(tbl);
        mask = abs(tbl.road_spd - spd_centre) <= spd_tol;
        tbl  = tbl(mask, :);
        fprintf('aeroMapBuild: filtered road_spd=%.1f+/-%.1f  (%d -> %d rows)\n', ...
            spd_centre, spd_tol, n_before, height(tbl));

        if height(tbl) == 0
            error('aeroMapBuild: no rows remain after road_spd filter (%.1f+/-%.1f). Available: [%s]', ...
                spd_centre, spd_tol, num2str(unique(tbl.road_spd(:)'', '%.1f ')));
        end
    end

    % --- Grid axes ---------------------------------------------------------------
    FRH_vec  = sort(unique(tbl.FRH_mm),  'ascend');
    RRH_vec  = sort(unique(tbl.RRH_mm),  'ascend');
    Roll_vec = sort(unique(tbl.roll_deg), 'ascend');

    nF = numel(FRH_vec);
    nR = numel(RRH_vec);
    nW = numel(Roll_vec);

    fprintf('aeroMapBuild: grid is %d FRH x %d RRH x %d Roll  (%d runs expected, %d found)\n', ...
        nF, nR, nW, nF*nR*nW, height(tbl));
    fprintf('  FRH_mm  : %s\n', num2str(FRH_vec(:)'',  '%.1f '));
    fprintf('  RRH_mm  : %s\n', num2str(RRH_vec(:)'',  '%.1f '));
    fprintf('  Roll_deg: %s\n', num2str(Roll_vec(:)'', '%.2f '));

    if height(tbl) ~= nF*nR*nW
        warning('aeroMapBuild: row count (%d) != expected grid size (%d). Grid may be incomplete or have duplicates.', ...
            height(tbl), nF*nR*nW);
    end

    % --- Output channel names ----------------------------------------------------
    out_channels = {'CDa_SCx','CLa_SCz','CLf_SCzF','CLr_SCzR', ...
                    'AB_FRT','EFF','CSa_Scy','CSf_SCyF','CSr_SCyR'};

    for k = 1:numel(out_channels)
        if ~ismember(out_channels{k}, cols)
            error('aeroMapBuild: column ''%s'' not found in table.', out_channels{k});
        end
    end

    % --- Build index lookup for each row -----------------------------------------
    % Tolerance-based matching to avoid floating point equality failures
    if nF > 1, tol_FRH  = min(diff(FRH_vec))  * 0.01; else, tol_FRH  = 1; end
    if nR > 1, tol_RRH  = min(diff(RRH_vec))  * 0.01; else, tol_RRH  = 1; end
    if nW > 1, tol_Roll = min(diff(Roll_vec)) * 0.01; else, tol_Roll = 1; end

    iFRH  = arrayfun(@(v) find(abs(FRH_vec  - v) < tol_FRH,  1), tbl.FRH_mm);
    % --- Store raw table + build interpolant -------------------------------------
    map.FRH_mm   = FRH_vec;
    map.RRH_mm   = RRH_vec;
    map.Roll_deg = Roll_vec;
    map.raw      = tbl;   % kept for plotting in aeroMapValidate

    iRRH  = arrayfun(@(v) find(abs(RRH_vec  - v) < tol_RRH,  1), tbl.RRH_mm);
    iRoll = arrayfun(@(v) find(abs(Roll_vec - v) < tol_Roll, 1), tbl.roll_deg);

    linIdx = sub2ind([nF, nR, nW], iFRH, iRRH, iRoll);

    [G_FRH, G_RRH, G_Roll] = ndgrid(FRH_vec, RRH_vec, Roll_vec);

    grid_complete = true;
    for k = 1:numel(out_channels)
        ch  = out_channels{k};
        arr = accumarray(linIdx, tbl.(ch), [nF*nR*nW, 1], @mean, NaN);
        arr = reshape(arr, [nF, nR, nW]);
        map.(ch) = arr;
        if any(isnan(arr(:))), grid_complete = false; end
    end

    if grid_complete
        map.interp_type = 'gridded';
        for k = 1:numel(out_channels)
            ch = out_channels{k};
            map.interp.(ch) = griddedInterpolant(G_FRH, G_RRH, G_Roll, map.(ch), 'linear', 'linear');
        end
        fprintf('aeroMapBuild: grid complete — using griddedInterpolant\n');
    else
        map.interp_type = 'scattered';
        for k = 1:numel(out_channels)
            ch = out_channels{k};
            map.interp.(ch) = scatteredInterpolant(tbl.FRH_mm, tbl.RRH_mm, tbl.roll_deg, tbl.(ch), 'linear', 'linear');
        end
        fprintf('aeroMapBuild: sparse grid — using scatteredInterpolant\n');
    end

    % --- Save + validate ---------------------------------------------------------
    save_dir = fileparts(mfilename('fullpath'));   % always the aerodynamics folder
    if ~isempty(manufacturer)
        out_name = sprintf('aeroMap_%s.mat', upper(strtrim(manufacturer)));
    elseif ischar(sheet) || isstring(sheet)
        safe_sheet = regexprep(char(sheet), '[^A-Za-z0-9_]', '_');
        out_name = sprintf('aeroMap_%s.mat', safe_sheet);
    else
        out_name = sprintf('aeroMap_sheet%d.mat', sheet);
    end
    out_path = fullfile(save_dir, out_name);
    save(out_path, 'map');
    fprintf('aeroMapBuild: saved to %s\n', out_path);

    aeroMapValidate(map);

end
