%% RUN_INTEGRATION_TESTS  Run all SMP integration tests.
%
% Requires testData folder populated with .ld files:
%   C:\SimEnv\tests\testData\01_FRD\
%   C:\SimEnv\tests\testData\02_GM\
%   C:\SimEnv\tests\testData\03_TOY\
%
% Tests that cannot find their data folder will be skipped (not failed).
%
% Usage:
%   run_integration_tests

clear; clc;

fprintf('=========================================\n');
fprintf('  SMP Integration Tests\n');
fprintf('  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('=========================================\n\n');

test_dir = fullfile(fileparts(mfilename('fullpath')), 'integration');

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
