function tla = resolve_driver_tla(raw_driver, driver_map)
% Resolve a raw driver string to its canonical TLA via the alias map.
% Returns '' if no match found.
    tla = '';
    if isempty(driver_map) || isempty(raw_driver), return; end
    raw_lower = lower(raw_driver);
    keys = fieldnames(driver_map);
    for ki = 1:numel(keys)
        entry = driver_map.(keys{ki});
        if any(strcmp(raw_lower, entry.aliases))
            if ~isempty(entry.tla)
                tla = entry.tla;
            elseif ~isempty(entry.canonical)
                tla = entry.canonical;
            end
            return;
        end
    end
end

