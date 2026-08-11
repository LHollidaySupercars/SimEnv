function smp_save_parallel(top_level_dir, cache, save_mode, alias, cfg)
% SMP_SAVE_PARALLEL  Bin-pack each session by TeamName size (same 2GB
%   logic as smp_cache_save), flatten sessions x parts into one job list,
%   and dispatch jobs across up to cfg.n_workers concurrent MATLAB
%   processes. A 4-part session fills 4 workers instead of 1 — jobs are
%   the unit of parallelism, not sessions.

    if nargin < 5, cfg = struct(); end

    if isfield(cfg, 'tmp_dir') && ~isempty(cfg.tmp_dir)
        TMP_DIR = fullfile(cfg.tmp_dir, 'save');
    else
        TMP_DIR = fullfile(top_level_dir, 'smp_parallel_save');
    end
    if ~exist(TMP_DIR, 'dir'), mkdir(TMP_DIR); end
    delete(fullfile(TMP_DIR, 'save_chunk_*.mat'));
    delete(fullfile(TMP_DIR, 'done_save_*.flag'));

    if isfield(cfg, 'matlab_exe') && ~isempty(cfg.matlab_exe)
        matlab_exe = cfg.matlab_exe;
    else
        matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    end

    MAX_BYTES = 1.5 * 1024^3;   % keep in sync with smp_cache_save threshold
    TEAM_FIELD = 'TeamName';
    KEY_FIELD  = 'GroupKey';

    T = cache.manifest;
    if height(T) == 0
        fprintf('smp_save_parallel: manifest is empty — nothing to save.\n');
        return;
    end

    raw_sessions = unique(string(T.Session));
    raw_sessions = raw_sessions(strtrim(raw_sessions) ~= "");
    if isempty(raw_sessions)
        fprintf('smp_save_parallel: no Session column — falling back to serial save.\n');
        smp_cache_save(top_level_dir, cache, save_mode, alias);
        return;
    end

    if isfield(cfg, 'n_workers') && ~isempty(cfg.n_workers)
        N_WORKERS = cfg.n_workers;
    else
        N_WORKERS = 6;
    end

    has_laps_field = isfield(cache, 'laps') && isstruct(cache.laps);

    % ------------------------------------------------------------------
    %  Build flat job list: {job_id, manifest_slice, stats, traces, laps, path}
    % ------------------------------------------------------------------
    jobs = struct('id', {}, 'manifest', {}, 'stats', {}, 'traces', {}, 'laps', {}, 'channels', {}, 'path', {});

    for s = 1:numel(raw_sessions)
        raw_sess  = char(raw_sessions(s));
        sess_safe = matlab.lang.makeValidName(raw_sess);

        row_mask   = strcmp(string(T.Session), raw_sess);
        sess_manifest = T(row_mask, :);

        sess_stats  = struct();
        sess_traces = struct();
        sess_laps   = struct();
        if ismember(KEY_FIELD, sess_manifest.Properties.VariableNames)
            gkeys = unique(string(sess_manifest.(KEY_FIELD)));
            gkeys = gkeys(strtrim(gkeys) ~= "");
            for k = 1:numel(gkeys)
                gk_vld = matlab.lang.makeValidName(char(gkeys(k)));
                if isfield(cache.stats, gk_vld),  sess_stats.(gk_vld)  = cache.stats.(gk_vld);  end
                if isfield(cache.traces, gk_vld), sess_traces.(gk_vld) = cache.traces.(gk_vld); end
                if has_laps_field && isfield(cache.laps, gk_vld)
                    sess_laps.(gk_vld) = cache.laps.(gk_vld);
                end
            end
        end

        % ---- Bin-pack by TeamName (mirrors smp_cache_save) ----
        has_team = ismember(TEAM_FIELD, sess_manifest.Properties.VariableNames) && ...
                   ismember(KEY_FIELD,  sess_manifest.Properties.VariableNames);
        if has_team
            tnames = unique(string(sess_manifest.(TEAM_FIELD)));
            tnames = tnames(strtrim(tnames) ~= "");
        else
            tnames = "ALL";
        end

        bins = {}; cur_bin = {}; cur_size = 0;
        for k = 1:numel(tnames)
            tname = char(tnames(k));
            if has_team
                gkeys_t = unique(string(sess_manifest.(KEY_FIELD)(strcmp(string(sess_manifest.(TEAM_FIELD)), tname))));
                gkeys_t = gkeys_t(strtrim(gkeys_t) ~= "");
            else
                gkeys_t = string(fieldnames(sess_stats));
            end
            sz = 0;
            for g = 1:numel(gkeys_t)
                gk_vld = matlab.lang.makeValidName(char(gkeys_t(g)));
                if isfield(sess_stats, gk_vld),  sz = sz + whos_size(sess_stats.(gk_vld));  end
                if isfield(sess_traces, gk_vld), sz = sz + whos_size(sess_traces.(gk_vld)); end
                if isfield(sess_laps, gk_vld),   sz = sz + whos_size(sess_laps.(gk_vld));   end
            end
            if cur_size + sz > MAX_BYTES && ~isempty(cur_bin)
                bins{end+1} = cur_bin; %#ok<AGROW>
                cur_bin = {}; cur_size = 0;
            end
            cur_bin{end+1} = tname; %#ok<AGROW>
            cur_size = cur_size + sz;
        end
        if ~isempty(cur_bin), bins{end+1} = cur_bin; end
        if isempty(bins), bins = {cellstr(tnames)}; end

        n_parts = numel(bins);

        for p = 1:n_parts
            keep_teams = bins{p};
            if has_team
                row_keep   = ismember(string(sess_manifest.(TEAM_FIELD)), string(keep_teams));
                manifest_p = sess_manifest(row_keep, :);
                gkeys_p    = unique(string(manifest_p.(KEY_FIELD)));
                gkeys_p    = gkeys_p(strtrim(gkeys_p) ~= "");
            else
                manifest_p = sess_manifest;
                gkeys_p    = string(fieldnames(sess_stats));
            end

            stats_p  = struct(); traces_p = struct(); laps_p = struct();
            for g = 1:numel(gkeys_p)
                gk_vld = matlab.lang.makeValidName(char(gkeys_p(g)));
                if isfield(sess_stats, gk_vld),  stats_p.(gk_vld)  = sess_stats.(gk_vld);  end
                if isfield(sess_traces, gk_vld), traces_p.(gk_vld) = sess_traces.(gk_vld); end
                if isfield(sess_laps, gk_vld),   laps_p.(gk_vld)   = sess_laps.(gk_vld);   end
            end

            channels_p = containers.Map('KeyType','char','ValueType','any');
            if isfield(cache, 'channels') && isa(cache.channels, 'containers.Map')
                paths = manifest_p.Path;
                for pp = 1:numel(paths)
                    pk = char(paths(pp));
                    if isKey(cache.channels, pk), channels_p(pk) = cache.channels(pk); end
                end
            end
            if ~exist(fullfile(top_level_dir, raw_sess), 'dir')
                mkdir(fullfile(top_level_dir, raw_sess));
            end
            if n_parts == 1
                job_id   = sess_safe;
                out_path = fullfile(top_level_dir, raw_sess, sprintf('smp_cache_%s.mat', sess_safe));
            else
                job_id   = sprintf('%s_Part%d', sess_safe, p);
                out_path = fullfile(top_level_dir, raw_sess, sprintf('smp_cache_%s_Part%d.mat', sess_safe, p));
            end

            j = numel(jobs) + 1;
            jobs(j).id       = job_id;
            jobs(j).manifest = manifest_p;
            jobs(j).stats    = stats_p;
            jobs(j).traces   = traces_p;
            jobs(j).laps     = laps_p;
            jobs(j).channels = channels_p;
            jobs(j).path     = out_path;
        end
    end

    n_jobs = numel(jobs);
    N_WORKERS = min(N_WORKERS, n_jobs);

    fprintf('============================================\n');
    fprintf('  Parallel Cache Save\n');
    fprintf('  Sessions : %d\n', numel(raw_sessions));
    fprintf('  Jobs     : %d (sessions split into size-bounded parts)\n', n_jobs);
    fprintf('  Workers  : %d (max concurrent)\n', N_WORKERS);
    fprintf('  TMP      : %s\n', TMP_DIR);
    fprintf('============================================\n\n');

    % ---- Write job chunk files ----
    for j = 1:n_jobs
        sess_cache = struct('manifest', jobs(j).manifest, 'stats', jobs(j).stats, ...
            'traces', jobs(j).traces, 'laps', jobs(j).laps, 'channels', jobs(j).channels, ...
            'mode', cache.mode, 'save_mode', save_mode); %#ok<NASGU>
        cache_path = jobs(j).path; %#ok<NASGU>
        chunk_file = fullfile(TMP_DIR, sprintf('save_chunk_%s.mat', jobs(j).id));
        save(chunk_file, 'sess_cache', 'cache_path');
        fprintf('  Prepared job: %s  (%d rows)\n', jobs(j).id, height(jobs(j).manifest));
    end
    fprintf('\n');

    % ------------------------------------------------------------------
    %  Launch jobs, throttled to N_WORKERS concurrent
    % ------------------------------------------------------------------
    launched = false(n_jobs, 1);
    active   = 0;
    idx      = 1;

    while idx <= n_jobs || active > 0
        while idx <= n_jobs && active < N_WORKERS
            job_id = jobs(idx).id;
            sys_cmd = sprintf('start "SMP Save Worker %s" cmd /k ""%s" -batch "smp_save_worker(''%s'', ''%s'')"', ...
                job_id, matlab_exe, job_id, strrep(TMP_DIR, '\', '\\'));
            system(sys_cmd);
            fprintf('  Save worker launched: %s\n', job_id);
            launched(idx) = true;
            active = active + 1;
            idx    = idx + 1;
            pause(1.5);
        end

        done_flags = dir(fullfile(TMP_DIR, 'done_save_*.flag'));
        n_done     = numel(done_flags);
        active     = sum(launched) - n_done;

        if idx > n_jobs && n_done >= n_jobs
            break;
        end
        pause(2);
    end

    fprintf('\nAll save jobs finished (%d/%d).\n\n', ...
        numel(dir(fullfile(TMP_DIR, 'done_save_*.flag'))), n_jobs);
    fprintf('============================================\n');
    fprintf('  Parallel Cache Save COMPLETE  [%s]\n', datestr(now,'HH:MM:SS'));
    fprintf('============================================\n');
end


function b = whos_size(s)
    w = whos('s');
    if isempty(w), b = 0; else, b = w.bytes; end
end