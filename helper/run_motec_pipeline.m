function run_motec_pipeline(cfg, SESSION, DRIVERS, OVERWRITE, ...
        RUN_TEAMDATA_CONCAT, RUN_ECU_CONCAT, RUN_SPLIT, RUN_PAIR, RUN_MERGE)
%RUN_MOTEC_PIPELINE  Runner bridge: sets workspace variables then runs smp_pipeline.m
%
%  Called by SimEnv_Launcher. All arguments are set into the base workspace
%  before delegating to smp_pipeline via run().

    scriptPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'dataAcquisition', 'Motec_MP', 'smp_pipeline.m');

    if ~isfile(scriptPath)
        error('run_motec_pipeline: cannot find smp_pipeline.m at:\n  %s', scriptPath);
    end

    % Push all variables into base workspace so smp_pipeline.m can see them
    assignin('base', 'SESSION',              SESSION);
    assignin('base', 'DRIVERS',              DRIVERS);
    assignin('base', 'OVERWRITE',            OVERWRITE);
    assignin('base', 'RUN_TEAMDATA_CONCAT',  RUN_TEAMDATA_CONCAT);
    assignin('base', 'RUN_ECU_CONCAT',       RUN_ECU_CONCAT);
    assignin('base', 'RUN_SPLIT',            RUN_SPLIT);
    assignin('base', 'RUN_PAIR',             RUN_PAIR);
    assignin('base', 'RUN_MERGE',            RUN_MERGE);
    assignin('base', 'cfg',                  cfg);

    run(scriptPath);
end
