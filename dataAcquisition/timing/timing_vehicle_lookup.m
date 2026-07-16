function T = timing_vehicle_lookup(T, alias_path)
% TIMING_VEHICLE_LOOKUP  Add a 'vehicle' column to T using driverAlias.xlsx.
%
% Matches each row by car number first (NUM column in alias file), then by
% driver name (DRV + Alias1..N columns) as fallback.
%
% Usage:
%   T = timing_vehicle_lookup(T)
%   T = timing_vehicle_lookup(T, alias_path)
%
% Inputs:
%   T           - table with at least 'car' and 'driver' columns
%   alias_path  - (optional) full path to driverAlias.xlsx
%                 Default: relative to this file → Motec_MP/alias/driverAlias.xlsx
%
% Output:
%   T  - same table with 'vehicle' column added (string; '' if unmatched)
%        vehicle value = MAN column; falls back to MAN_TLA if MAN is empty

    if nargin < 2 || isempty(alias_path)
        this_dir   = fileparts(mfilename('fullpath'));
        alias_path = fullfile(this_dir, '..', 'Motec_MP', 'alias', 'driverAlias.xlsx');
    end

    n         = height(T);
    T.vehicle = repmat("", n, 1);

    if ~isfile(alias_path)
        fprintf('[WARN] timing_vehicle_lookup: driverAlias.xlsx not found:\n  %s\n', alias_path);
        return;
    end

    % ── Load driver map via shared loader ─────────────────────────────────────
    try
        driver_map = smp_driver_alias_load(alias_path);
    catch ME
        fprintf('[WARN] timing_vehicle_lookup: failed to load alias file:\n  %s\n', ME.message);
        return;
    end

    fields = fieldnames(driver_map);

    % ── Build car number → manufacturer map (primary) ─────────────────────────
    car_mfr = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for i = 1:numel(fields)
        d = driver_map.(fields{i});
        if isfield(d, 'num') && isfield(d, 'manufacturer') && ...
                ~isempty(d.num) && ~isempty(d.manufacturer)
            car_mfr(strtrim(d.num)) = d.manufacturer;
        end
    end

    % ── Build driver alias → manufacturer map (fallback) ─────────────────────
    % d.aliases is a cell of lowercase strings: canonical, TLA, Alias1..N
    drv_mfr = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for i = 1:numel(fields)
        d = driver_map.(fields{i});
        if ~isfield(d, 'manufacturer') || isempty(d.manufacturer), continue; end
        mfr = d.manufacturer;
        if isfield(d, 'aliases')
            for k = 1:numel(d.aliases)
                key = strtrim(d.aliases{k});   % already lowercase
                if ~isempty(key)
                    drv_mfr(key) = mfr;
                end
            end
        end
    end

    % ── Populate vehicle column row by row ────────────────────────────────────
    n_car = 0;
    n_drv = 0;
    n_miss = 0;

    for i = 1:n
        car_key = strtrim(char(T.car(i)));
        drv_key = lower(strtrim(char(T.driver(i))));

        if isKey(car_mfr, car_key)
            T.vehicle(i) = string(car_mfr(car_key));
            n_car = n_car + 1;
        elseif isKey(drv_mfr, drv_key)
            T.vehicle(i) = string(drv_mfr(drv_key));
            n_drv = n_drv + 1;
        else
            n_miss = n_miss + 1;
        end
    end

    fprintf('[vehicle] matched %d by car#, %d by driver name', n_car, n_drv);
    if n_miss > 0
        fprintf(', %d unmatched', n_miss);
        unmatched_cars = unique(string(T.car(T.vehicle == "")));
        fprintf(' (cars: %s)', strjoin(unmatched_cars, ', '));
    end
    fprintf('\n');

end
