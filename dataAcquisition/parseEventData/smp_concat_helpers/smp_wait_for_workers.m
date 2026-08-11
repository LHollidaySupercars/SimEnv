function smp_wait_for_workers(tmp_dir, n_workers, poll_interval_s, timeout_s)
% SMP_WAIT_FOR_WORKERS  Block until n_workers done_N.flag files exist in tmp_dir.
if nargin < 3, poll_interval_s = 2; end
if nargin < 4, timeout_s = 3600; end

fprintf('Waiting for %d worker(s) to finish...\n', n_workers);
t0 = tic;
while true
    done_files = dir(fullfile(tmp_dir, 'done_*.flag'));
    n_done = numel(done_files);
    if n_done >= n_workers
        fprintf('All %d worker(s) complete (%.1fs elapsed).\n', n_workers, toc(t0));
        return;
    end
    if toc(t0) > timeout_s
        error('smp_wait_for_workers:timeout', ...
            'Timed out after %.0fs waiting for workers (%d/%d done).', ...
            timeout_s, n_done, n_workers);
    end
    pause(poll_interval_s);
end
end
