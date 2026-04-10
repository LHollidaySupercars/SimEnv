%% RUN_UNIT_TESTS  Run all SMP unit tests.
%
% No data files required — all tests use synthetic in-memory data.
%
% Usage (from MATLAB command window):
%   run_unit_tests
%
% Returns a summary table and sets exit code if called from -batch mode.

clear; clc;

fprintf('=========================================\n');
fprintf('  SMP Unit Tests\n');
fprintf('  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('=========================================\n\n');

test_dir = fullfile(fileparts(mfilename('fullpath')), 'unit');

suite   = testsuite(test_dir);
runner  = testrunner('textoutput');
results = runner.run(suite);

fprintf('\n=========================================\n');
fprintf('  Results: %d passed, %d failed, %d incomplete\n', ...
    sum([results.Passed]), ...
    sum([results.Failed]), ...
    sum([results.Incomplete]));
fprintf('=========================================\n\n');

if sum([results.Failed]) > 0
    disp(table(results));
end

if sum([results.Failed]) > 0
    exit(1)
end
exit(0)