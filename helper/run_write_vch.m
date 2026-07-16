function run_write_vch(SOURCE_FILES, OUTPUT_SUFFIX, OVERWRITE)
%RUN_WRITE_VCH  Runner bridge for execute_write_vch.m
%
%  Pushes all variables to the base workspace, then delegates via run().

    scriptPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'dataAcquisition', 'parseEventData', 'executionScripts', ...
        'execute_write_vch.m');

    if ~isfile(scriptPath)
        error('run_write_vch: cannot find execute_write_vch.m at:\n  %s', scriptPath);
    end

    assignin('base', 'SOURCE_FILES',   SOURCE_FILES);
    assignin('base', 'OUTPUT_SUFFIX',  OUTPUT_SUFFIX);
    assignin('base', 'OVERWRITE',      OVERWRITE);

    run(scriptPath);
end
