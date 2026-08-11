function mfr = local_resolve_manufacturer(driver_key, driver_map)
% Resolve manufacturer for a driver, accepting either a TLA or full name.
% Tries an exact TLA match first (cheap, unambiguous), then falls back
% to a case-insensitive full-name match against driver_map.
mfr = '';
if isempty(driver_map) || isempty(driver_key), return; end

driver_key = strtrim(driver_key);
keys = fieldnames(driver_map);

% ---- Pass 1: exact TLA match ----
for ki = 1:numel(keys)
    entry = driver_map.(keys{ki});
    if isfield(entry, 'tla') && strcmp(entry.tla, strrep(driver_key, ' ', '_'))
        if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
            mfr = entry.manufacturer;
        end
        return;
    end
end

% ---- Pass 2: case-insensitive full-name match ----
for ki = 1:numel(keys)
    entry = driver_map.(keys{ki});
    if isfield(entry, 'name') && strcmpi(strtrim(entry.name), driver_key)
        if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
            mfr = entry.manufacturer;
        end
        return;
    end
end
end

