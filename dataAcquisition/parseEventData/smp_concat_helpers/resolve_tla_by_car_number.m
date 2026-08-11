function tla = resolve_tla_by_car_number(car_num, driver_map)
% RESOLVE_TLA_BY_CAR_NUMBER  Resolve a car number to its canonical driver TLA
%   via the alias map's 'num' field. Returns '' if no match found.
%   car_num may be numeric or char/string; entry.num is stored as char.
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

