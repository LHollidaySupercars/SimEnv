function run_main_report(isReduced, TOP_LEVEL_DIR, CHANNELS_FILE, EVENT_ALIAS_FILE, ...
        DRIVER_ALIAS_FILE, PLOT_CONFIG_FILES, SEASON_FILE, PPTX_TEMPLATE, OUTPUT_DIR, ...
        EVENT, TRACK, EVENT_NAME, TEAM_FILTER, SESSION_FILTER, ...
        CREATE_PITSTOP_REPORT, workshop, SAVE_CACHE, PLOTTING, ...
        MODE, N_WORKERS, TMP_DIR, POLL_INTERVAL_S, TIMEOUT_S, KEEP_WORKERS_OPEN, ...
        RUN_RECOMPUTE_VCH, RECOMPUTE_MODE, VCH_DEBUG_PLOT, VCH_DEBUG_TEAM, ...
        VCH_DEBUG_X, VCH_DEBUG_Y, TARGET, RUN_UPLOAD, BATCH_SIZE, OVERWRITE, ...
        compile_opts, plot_opts, WRITE_VCH_LD, VCH_LD_SUFFIX)
%RUN_MAIN_REPORT  Runner bridge for execute_main_report.m / execute_reduced_script.m
%
%  Selects the correct script based on isReduced, pushes all variables to
%  the base workspace, then delegates via run().

    thisDir = fileparts(fileparts(mfilename('fullpath')));
    execDir = fullfile(thisDir, 'dataAcquisition', 'parseEventData', 'executionScripts');

    if isReduced
        scriptPath = fullfile(execDir, 'execute_reduced_script.m');
    else
        scriptPath = fullfile(execDir, 'execute_main_report.m');
    end

    if ~isfile(scriptPath)
        error('run_main_report: cannot find script at:\n  %s', scriptPath);
    end

    % Push all variables
    assignin('base', 'TOP_LEVEL_DIR',        TOP_LEVEL_DIR);
    assignin('base', 'CHANNELS_FILE',        CHANNELS_FILE);
    assignin('base', 'EVENT_ALIAS_FILE',     EVENT_ALIAS_FILE);
    assignin('base', 'DRIVER_ALIAS_FILE',    DRIVER_ALIAS_FILE);
    assignin('base', 'PLOT_CONFIG_FILES',    PLOT_CONFIG_FILES);
    assignin('base', 'SEASON_FILE',          SEASON_FILE);
    assignin('base', 'PPTX_TEMPLATE',        PPTX_TEMPLATE);
    assignin('base', 'OUTPUT_DIR',           OUTPUT_DIR);
    assignin('base', 'EVENT',               EVENT);
    assignin('base', 'TRACK',               TRACK);
    assignin('base', 'EVENT_NAME',           EVENT_NAME);
    assignin('base', 'TEAM_FILTER',          TEAM_FILTER);
    assignin('base', 'SESSION_FILTER',       SESSION_FILTER);
    assignin('base', 'CREATE_PITSTOP_REPORT',CREATE_PITSTOP_REPORT);
    assignin('base', 'workshop',             workshop);
    assignin('base', 'SAVE_CACHE',           SAVE_CACHE);
    assignin('base', 'PLOTTING',             PLOTTING);
    assignin('base', 'MODE',                MODE);
    assignin('base', 'N_WORKERS',            N_WORKERS);
    assignin('base', 'TMP_DIR',             TMP_DIR);
    assignin('base', 'POLL_INTERVAL_S',      POLL_INTERVAL_S);
    assignin('base', 'TIMEOUT_S',            TIMEOUT_S);
    assignin('base', 'KEEP_WORKERS_OPEN',    KEEP_WORKERS_OPEN);
    assignin('base', 'RUN_RECOMPUTE_VCH',    RUN_RECOMPUTE_VCH);
    assignin('base', 'RECOMPUTE_MODE',       RECOMPUTE_MODE);
    assignin('base', 'VCH_DEBUG_PLOT',       VCH_DEBUG_PLOT);
    assignin('base', 'VCH_DEBUG_TEAM',       VCH_DEBUG_TEAM);
    assignin('base', 'VCH_DEBUG_X',          VCH_DEBUG_X);
    assignin('base', 'VCH_DEBUG_Y',          VCH_DEBUG_Y);
    assignin('base', 'TARGET',              TARGET);
    assignin('base', 'RUN_UPLOAD',           RUN_UPLOAD);
    assignin('base', 'BATCH_SIZE',           BATCH_SIZE);
    assignin('base', 'OVERWRITE',            OVERWRITE);
    assignin('base', 'compile_opts',         compile_opts);
    assignin('base', 'plot_opts',            plot_opts);
    if isReduced
        assignin('base', 'WRITE_VCH_LD',  WRITE_VCH_LD);
        assignin('base', 'VCH_LD_SUFFIX', VCH_LD_SUFFIX);
    end

    run(scriptPath);
end
