function smp_save_worker(sess_safe, tmp_dir)
% SMP_SAVE_WORKER  Parallel cache save worker.
%
% Loads a pre-sliced single-session cache chunk from tmp_dir and saves
% it to disk via smp_cache_save. Called by the main parallel script.
%
% Usage (via cmd /c):
%   matlab -batch "smp_save_worker('RA4', 'C:\...\smp_parallel')"

    fprintf('\n============================================\n');
    fprintf('  SMP Save Worker: %s\n', sess_safe);
    fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('  TMP  : %s\n', tmp_dir);
    fprintf('============================================\n\n');

    % ---- Load chunk ----
    chunk_file = fullfile(tmp_dir, sprintf('save_chunk_%s.mat', sess_safe));
    if ~exist(chunk_file, 'file')
        error('smp_save_worker: chunk file not found: %s', chunk_file);
    end

    loaded        = load(chunk_file);
    slice_cache   = loaded.slice_cache;
    top_level_dir = loaded.top_level_dir;
    save_mode     = loaded.save_mode_str;
    alias         = loaded.alias;

    % ---- Save ----
    fprintf('Saving session: %s\n', sess_safe);
    tic;
    smp_cache_save(top_level_dir, slice_cache, save_mode, alias);
    fprintf('Saved in %.1fs.\n', toc);

    % ---- Write done flag ----
    flag_file = fullfile(tmp_dir, sprintf('done_save_%s.flag', sess_safe));
    fid = fopen(flag_file, 'w');
    fprintf(fid, 'done at %s', datestr(now));
    fclose(fid);
    fprintf('Done flag written: %s\n', flag_file);

    fprintf('\n============================================\n');
    fprintf('  Save Worker %s COMPLETE  [%s]\n', sess_safe, datestr(now,'HH:MM:SS'));
    fprintf('============================================\n');
end