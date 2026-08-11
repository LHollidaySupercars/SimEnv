function T_rh = smp_load_rh_patch(rh_patch_file, driver_map)
% SMP_LOAD_RH_PATCH  Load the ride-height patch table from Excel and
%   resolve Driver + manufacturer per row via the driver alias map.
%
%   Expected columns in rh_patch_file (case-insensitive header match):
%     Car | FrontRH | RearRH | Session
%
%   USAGE:
%     T_rh = smp_load_rh_patch(cfg.rh_patch_file, driver_map);
%     cfg.PatchRH = T_rh;
%
%   Returns a table with columns:
%     Car, Driver, MAN, FrontRH, RearRH, Session
%   matching the VariableNames used by the original hand-built table.

    if ~isfile(rh_patch_file)
        error('smp_load_rh_patch: file not found: %s', rh_patch_file);
    end

    Traw = readtable(rh_patch_file, 'TextType', 'char', 'ReadVariableNames', true);
    req_cols = {'Car', 'FrontRH', 'RearRH', 'Session'};
    actual_names = Traw.Properties.VariableNames;
    col_map = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for c = req_cols
        hit = actual_names(strcmpi(actual_names, c{1}));
        if isempty(hit)
            error('smp_load_rh_patch: missing required column "%s" (columns found: %s).', ...
                c{1}, strjoin(actual_names, ', '));
        end
        col_map(c{1}) = hit{1};
    end

    Car     = double(Traw.(col_map('Car')));
    FrontRH = double(Traw.(col_map('FrontRH')));
    RearRH  = double(Traw.(col_map('RearRH')));
    SessionRaw = Traw.(col_map('Session'));
    if isnumeric(SessionRaw)
        Session = arrayfun(@num2str, SessionRaw, 'UniformOutput', false);
    else
        Session = cellstr(string(SessionRaw));
    end
    Session = strtrim(Session);

    n = numel(Car);
    Driver = cell(n, 1);
    MAN    = cell(n, 1);
    for i = 1:n
        Driver{i} = resolve_tla_by_car_number(Car(i), driver_map);
        if isempty(Driver{i})
            fprintf('  [WARN] No alias NUM match for car #%d\n', Car(i));
        end
        MAN{i} = local_resolve_manufacturer_by_tla(Driver{i}, driver_map);
    end

    T_rh = table(Car, Driver, MAN, FrontRH, RearRH, Session, ...
        'VariableNames', {'Car', 'Driver', 'MAN', 'FrontRH', 'RearRH', 'Session'});
end


function tla = resolve_tla_by_car_number(car_num, driver_map)
% RESOLVE_TLA_BY_CAR_NUMBER  Resolve a car number to its canonical driver TLA
%   via the alias map's 'num' field. Returns '' if no match found.
    tla = '';
    if isempty(driver_map) || ~isstruct(driver_map) || isempty(car_num)
        return;
    end
    car_key = strtrim(char(string(car_num)));
    keys = fieldnames(driver_map);
    for ki = 1:numel(keys)
        entry = driver_map.(keys{ki});
        if ~isfield(entry, 'num') || isempty(entry.num)
            continue;
        end
        entry_key = strtrim(char(string(entry.num)));
        if strcmp(entry_key, car_key)
            if isfield(entry, 'tla') && ~isempty(entry.tla)
                tla = entry.tla;
            elseif isfield(entry, 'canonical') && ~isempty(entry.canonical)
                tla = entry.canonical;
            end
            return;
        end
    end
end


function mfr = local_resolve_manufacturer_by_tla(tla, driver_map)
% LOCAL_RESOLVE_MANUFACTURER_BY_TLA  Resolve manufacturer for a driver
%   given their already-resolved TLA.
    mfr = '';
    if isempty(driver_map) || isempty(tla), return; end
    keys = fieldnames(driver_map);
    for ki = 1:numel(keys)
        entry = driver_map.(keys{ki});
        if isfield(entry, 'tla') && strcmp(entry.tla, tla)
            if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
                mfr = entry.manufacturer;
            end
            return;
        end
    end
end