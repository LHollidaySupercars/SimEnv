%% RUN_ALL_TESTS  Run the full SMP test suite (unit + integration).
%
% Usage:
%   run_all_tests

clear; clc;

fprintf('=========================================\n');
fprintf('  SMP Full Test Suite\n');
fprintf('  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('=========================================\n\n');

base_dir = fileparts(mfilename('fullpath'));

unit_dir        = fullfile(base_dir, 'unit');
integration_dir = fullfile(base_dir, 'integration');

suite = [testsuite(unit_dir); testsuite(integration_dir)];

runner  = testrunner('textoutput');
results = runner.run(suite);

n_pass = sum([results.Passed]);
n_fail = sum([results.Failed]);
n_skip = sum([results.Incomplete]);

fprintf('\n=========================================\n');
fprintf('  TOTAL: %d passed  |  %d failed  |  %d skipped\n', ...
    n_pass, n_fail, n_skip);
fprintf('=========================================\n\n');

if n_fail > 0
    fprintf('FAILED TESTS:\n');
    failed = results([results.Failed]);
    for i = 1:numel(failed)
        fprintf('  ✗ %s\n', failed(i).Name);
        if ~isempty(failed(i).Details) && ~isempty(failed(i).Details.DiagnosticRecord)
            fprintf('    %s\n', failed(i).Details.DiagnosticRecord.Report);
        end
    end
    fprintf('\n');
end
