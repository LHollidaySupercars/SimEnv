function run_quali_fuel(TOP_LEVEL_DIR, CHANNELS_FILE, EVENT_ALIAS_FILE, ...
        DRIVER_ALIAS_FILE, SEASON_FILE, TRACK, EVENT_CODE, YEAR, ...
        TEAM_FILTER, SESSION_FILTER, BR2_PROTOCOL, SHOW_REPORT, ...
        compile_opts, lap_slicer_opts)
%RUN_QUALI_FUEL  Runner bridge for execute_quali_fuel_analysis.m
%
%  Pushes all variables to the base workspace, then delegates via run().

    scriptPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'dataAcquisition', 'parseEventData', 'executionScripts', ...
        'execute_quali_fuel_analysis.m');

    if ~isfile(scriptPath)
        error('run_quali_fuel: cannot find execute_quali_fuel_analysis.m at:\n  %s', scriptPath);
    end

    assignin('base', 'TOP_LEVEL_DIR',     TOP_LEVEL_DIR);
    assignin('base', 'CHANNELS_FILE',     CHANNELS_FILE);
    assignin('base', 'EVENT_ALIAS_FILE',  EVENT_ALIAS_FILE);
    assignin('base', 'DRIVER_ALIAS_FILE', DRIVER_ALIAS_FILE);
    assignin('base', 'SEASON_FILE',       SEASON_FILE);
    assignin('base', 'TRACK',            TRACK);
    assignin('base', 'EVENT_CODE',        EVENT_CODE);
    assignin('base', 'YEAR',             YEAR);
    assignin('base', 'TEAM_FILTER',       TEAM_FILTER);
    assignin('base', 'SESSION_FILTER',    SESSION_FILTER);
    assignin('base', 'BR2_PROTOCOL',      BR2_PROTOCOL);
    assignin('base', 'SHOW_REPORT',       SHOW_REPORT);
    assignin('base', 'compile_opts',      compile_opts);
    assignin('base', 'lap_slicer_opts',   lap_slicer_opts);

    run(scriptPath);
end
