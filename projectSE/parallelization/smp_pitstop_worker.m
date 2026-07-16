function smp_pitstop_worker(worker_id, tmp_dir)
% SMP_PITSTOP_WORKER  Parallel pitstop detection worker.
%
% Loads a team chunk from chunk_pit_N.mat, runs smp_pitstop_detect on
% the SMP subset, saves partial_pit_N.mat with the stops struct.
%
% Called via:
%   start "PIT Worker N" cmd /k "<matlab.exe>" -batch "smp_pitstop_worker(N, tmp_dir)"

    fprintf('\n============================================\n');
    fprintf('  Pitstop Worker %d starting\n', worker_id);
    fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('  TMP  : %s\n', tmp_dir);
    fprintf('============================================\n\n');

    % ---- Load team chunk ----
    chunk_file = fullfile(tmp_dir, sprintf('chunk_pit_%d.mat', worker_id));
    if ~exist(chunk_file, 'file')
        error('Pitstop Worker %d: chunk file not found: %s', worker_id, chunk_file);
    end
    loaded     = load(chunk_file, 'SMP_chunk');
    SMP_chunk  = loaded.SMP_chunk;

    teams = fieldnames(SMP_chunk);
    fprintf('Worker %d: %d team(s) to process\n\n', worker_id, numel(teams));

    if isempty(teams)
        fprintf('Worker %d: nothing to do.\n', worker_id);
        partial_stops = struct(); %#ok<NASGU>
        save(fullfile(tmp_dir, sprintf('partial_pit_%d.mat', worker_id)), 'partial_stops');
        write_done_flag(worker_id, tmp_dir);
        return;
    end

    % ---- Run pitstop detection on this team subset ----
    try
        partial_stops = smp_pitstop_detect(SMP_chunk);
    catch ME
        fprintf('  [W%d] [ERROR] smp_pitstop_detect failed: %s\n', worker_id, ME.message);
        fprintf('  [W%d] %s\n', worker_id, ME.getReport('basic'));
        partial_stops = struct();
    end

    % ---- Save partial result ----
    partial_file = fullfile(tmp_dir, sprintf('partial_pit_%d.mat', worker_id));
    fprintf('Worker %d: saving partial stops to:\n  %s\n', worker_id, partial_file);
    save(partial_file, 'partial_stops', '-v7.3');

    write_done_flag(worker_id, tmp_dir);

    fprintf('\n============================================\n');
    fprintf('  Pitstop Worker %d COMPLETE  [%s]\n', worker_id, datestr(now, 'HH:MM:SS'));
    fprintf('============================================\n');
end


% ======================================================================= %
function write_done_flag(worker_id, tmp_dir)
    flag_file = fullfile(tmp_dir, sprintf('done_pit_%d.flag', worker_id));
    fid = fopen(flag_file, 'w');
    fprintf(fid, 'done at %s', datestr(now));
    fclose(fid);
    fprintf('Worker %d: done flag written.\n', worker_id);
end