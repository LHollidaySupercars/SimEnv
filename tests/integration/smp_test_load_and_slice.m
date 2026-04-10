function [laps, session, info] = smp_test_load_and_slice(team_folder, opts)
% SMP_TEST_LOAD_AND_SLICE  Load a single .ld file from a test team folder
% and return sliced laps ready for assertions.
%
% Used by integration tests — not part of production pipeline.
%
% Usage:
%   [laps, session, info] = smp_test_load_and_slice('C:\...\01_FRD')
%   [laps, session, info] = smp_test_load_and_slice('C:\...\01_FRD', opts)
%
% Options (struct):
%   opts.min_lap_time   default: 80
%   opts.max_lap_time   default: 200
%   opts.verbose        default: false

    if nargin < 2, opts = struct(); end
    min_lt  = get_field(opts, 'min_lap_time', 80);
    max_lt  = get_field(opts, 'max_lap_time', 200);
    verbose = get_field(opts, 'verbose',      false);

    % Find the first .ld file in the folder (recursive)
    files = dir(fullfile(team_folder, '**', '*.ld'));
    if isempty(files)
        error('smp_test_load_and_slice: no .ld files found in %s', team_folder);
    end

    ld_path = fullfile(files(1).folder, files(1).name);
    fprintf('[test] Loading: %s\n', ld_path);

    % Load via motec_ld_reader
    [session, info] = motec_ld_reader(ld_path);

    % Slice laps
    slice_opts.min_lap_time = min_lt;
    slice_opts.max_lap_time = max_lt;
    slice_opts.verbose      = verbose;
    laps = lap_slicer(session, slice_opts);
end


function val = get_field(s, name, default)
    if isfield(s, name)
        val = s.(name);
    else
        val = default;
    end
end
