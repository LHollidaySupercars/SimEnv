function mfr = local_resolve_manufacturer_by_tla(tla, driver_map)
% Resolve manufacturer for a driver given their already-resolved TLA.
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

