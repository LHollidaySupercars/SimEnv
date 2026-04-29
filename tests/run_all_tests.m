%% RUN_ALL_TESTS  Run the full SMP test suite (unit + integration).

clear; clc;

fprintf('=========================================\n');
fprintf('  SMP Full Test Suite\n');
fprintf('  %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('=========================================\n\n');

base_dir        = fileparts(mfilename('fullpath'));
unit_dir        = fullfile(base_dir, 'unit');
integration_dir = fullfile(base_dir, 'integration');

r_unit        = runtests(unit_dir);
r_integration = runtests(integration_dir);
results       = [r_unit(:); r_integration(:)];

n_pass = sum([results.Passed]);
n_fail = sum([results.Failed]);
n_skip = sum([results.Incomplete]);

fprintf('\n=========================================\n');
fprintf('  TOTAL: %d passed  |  %d failed  |  %d skipped\n', ...
    n_pass, n_fail, n_skip);
fprintf('=========================================\n\n');

if n_fail > 0
    disp(table(results));
    exit(1)
end
exit(0)