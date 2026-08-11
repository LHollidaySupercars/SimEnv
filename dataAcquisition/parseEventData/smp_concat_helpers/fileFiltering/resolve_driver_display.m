function [canonical, car_num, team_tla, drv_tla, status] = resolve_driver_display(raw_drv, driver_map)
% Same lookup convention as resolve_driver_info in smp_split_ecu_by_uptime.m
% and smp_sort_l180_to_hol.m — matches raw header driver string against
% driver_map.<key>.aliases (case-insensitive) to get canonical name,
% car number, and team TLA. Renamed _display to avoid any name clash if
% both files are on path simultaneously.
canonical = raw_drv;
car_num   = '';
team_tla  = '';
drv_tla   = '';
status    = 'NOT_IN_ALIAS';
if isempty(raw_drv) || isempty(driver_map)
    return;
end
raw_lower = lower(strtrim(raw_drv));
keys = fieldnames(driver_map);
for ki = 1 : numel(keys)
    entry = driver_map.(keys{ki});
    if isfield(entry, 'aliases') && any(strcmp(raw_lower, entry.aliases))
        canonical = entry.canonical;
        car_num   = entry.num;
        team_tla  = entry.team_tla;
        drv_tla   = entry.tla;
        status    = 'OK';
        return;
    end
end
end