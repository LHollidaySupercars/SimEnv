function smp_recompute_vch_worker(worker_id, tmp_dir)
% SMP_RECOMPUTE_VCH_WORKER  Parallel worker for VCH stat recompute.
%
% Loads its group chunk and worker config from tmp_dir, reruns
% smp_custom_channels + smp_gated_channels for each group, then writes
% a partial result containing only the updated custom channel stats.
%
% Called via:
%   start "VCH Worker N" cmd /k "<matlab.exe>" -batch "smp_recompute_vch_worker(N, 'tmp_dir')"

    fprintf('\n============================================\n');
    fprintf('  VCH Worker %d starting\n', worker_id);
    fprintf('  Time : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('  TMP  : %s\n', tmp_dir);
    fprintf('============================================\n\n');

    % ---- Load shared config ----
    cfg_file = fullfile(tmp_dir, 'vch_worker_cfg.mat');
    if ~exist(cfg_file, 'file')
        error('Worker %d: config file not found: %s', worker_id, cfg_file);
    end
    loaded = load(cfg_file, 'worker_cfg');
    cfg    = loaded.worker_cfg;

    % ---- Load this worker's group chunk ----
    chunk_file = fullfile(tmp_dir, sprintf('vch_chunk_%d.mat', worker_id));
    if ~exist(chunk_file, 'file')
        error('Worker %d: chunk file not found: %s', worker_id, chunk_file);
    end
    loaded2 = load(chunk_file, 'worker_groups');
    groups  = loaded2.worker_groups;

    n_groups = numel(groups);
    fprintf('Worker %d: %d group(s) to process\n\n', worker_id, n_groups);

    if n_groups == 0
        fprintf('Worker %d: nothing to do.\n', worker_id);
        write_done_flag(worker_id, tmp_dir);
        return;
    end

    channels_to_extract = cfg.channels_to_extract;
    min_lt              = cfg.min_lt;
    max_lt              = cfg.max_lt;
    T_gated             = cfg.T_gated;

    lap_opts.min_lap_time = min_lt;
    lap_opts.max_lap_time = max_lt;
    lap_opts.verbose      = false;

    stat_ops = {'max','min','mean','median','std','var','range','change', ...
                'max non zero','min non zero','mean non zero', ...
                'median non zero','std non zero','sample_rate'};

    % Partial result: group_key -> vch_stats struct
    partial.vch_stats = struct();

    for g = 1:n_groups
        grp = groups(g);
        fprintf('[W%d] [%d/%d] %s | %s | %s | %d file(s)\n', ...
            worker_id, g, n_groups, ...
            grp.team_acronym, grp.driver, grp.session, numel(grp.files));

        try
            fprintf('  [W%d] Loading .ld file(s)...\n', worker_id);
            session = load_and_concat(grp.files, channels_to_extract, true, T_gated);

            if isempty(session)
                fprintf('  [W%d] [WARN] No channel data — skipping.\n', worker_id);
                continue;
            end

            % ---- Detect custom fields ----
            all_session_fields = fieldnames(session);
            raw_fields_san     = cellfun(@(c) regexprep(c, '[^a-zA-Z0-9_]', '_'), ...
                                         channels_to_extract, 'UniformOutput', false);
            raw_fields_lower   = lower([channels_to_extract(:); raw_fields_san(:)]);
            custom_fields      = all_session_fields( ...
                ~ismember(lower(all_session_fields), raw_fields_lower));

            if isempty(custom_fields)
                fprintf('  [W%d] [WARN] No custom channels detected — skipping.\n', worker_id);
                clear session;
                continue;
            end

            fprintf('  [W%d] Custom channels (%d): %s\n', ...
                worker_id, numel(custom_fields), strjoin(custom_fields, ', '));

            % ---- Slice laps ----
            fprintf('  [W%d] Slicing laps...\n', worker_id);
            laps = lap_slicer(session, lap_opts);
            clear session;

            if isempty(laps)
                fprintf('  [W%d] [WARN] No valid laps — skipping.\n', worker_id);
                continue;
            end
            fprintf('  [W%d] %d valid lap(s).\n', worker_id, numel(laps));

            % ---- Compute stats for custom channels only ----
            vch_stats = lap_stats(laps, custom_fields, ...
                struct('operations', {stat_ops}));
            clear laps;

            group_key = matlab.lang.makeValidName(grp.key);
            partial.vch_stats.(group_key) = vch_stats;

            fprintf('  [W%d] Done — %d channel(s) computed.\n\n', ...
                worker_id, numel(fieldnames(vch_stats)));

        catch ME
            fprintf('  [W%d] [ERROR] %s\n', worker_id, ME.message);
            fprintf('  [W%d] %s\n\n', worker_id, ME.getReport('basic'));
        end
    end

    % ---- Save partial result ----
    partial_file = fullfile(tmp_dir, sprintf('vch_partial_%d.mat', worker_id));
    fprintf('Worker %d: saving partial result to:\n  %s\n', worker_id, partial_file);
    save(partial_file, 'partial', '-v7.3');

    write_done_flag(worker_id, tmp_dir);

    fprintf('\n============================================\n');
    fprintf('  VCH Worker %d COMPLETE  [%s]\n', worker_id, datestr(now,'HH:MM:SS'));
    fprintf('============================================\n');
end


% ======================================================================= %
%  LOAD AND CONCAT  (mirrors smp_compile_event exactly)
% ======================================================================= %
function session = load_and_concat(files, channels_to_extract, verbose, T_gated)
    EXCEL_FILTERING        = 'C:\SimEnv\dataAcquisition\Motec_MP\filterRequest\filterRequest.xlsx';
    CHANNELS_FOR_START_VAL = {'Acceleration_Z_Filt'};

    if numel(files) == 1
        session     = motec_ld_reader(files{1}, channels_to_extract);
        startingVal = startingValues(CHANNELS_FOR_START_VAL, EXCEL_FILTERING, session);
        session     = smp_custom_channels(session, 'startingValues', startingVal);
        [session, gated_names]  = smp_gated_channels(session, T_gated);
        channels_to_extract     = union(channels_to_extract, gated_names);
        session     = filter_channels(session, channels_to_extract);
        return;
    end

    all_sessions = cell(numel(files), 1);
    for f = 1:numel(files)
        if verbose
            [~, fname] = fileparts(files{f});
            fprintf('    Loading stint %d: %s\n', f, fname);
        end
        t0 = tic;
        s = motec_ld_reader(files{f}, channels_to_extract);
        fprintf('  motec_ld_reader: %.2fs\n', toc(t0));

        t0 = tic;
        startingVal = startingValues(CHANNELS_FOR_START_VAL, EXCEL_FILTERING, s);
        s = smp_custom_channels(s, 'startingValues', startingVal);
        fprintf('  smp_custom_channels: %.2fs\n', toc(t0));

        t0 = tic;
        [s, gated_names]    = smp_gated_channels(s, T_gated);
        channels_to_extract = union(channels_to_extract, gated_names);
        fprintf('  smp_gated_channels: %.2fs\n', toc(t0));

        s = filter_channels(s, channels_to_extract);
        all_sessions{f} = s;
    end

    session = concat_sessions(all_sessions);
end


% ======================================================================= %
function session = filter_channels(session, channels_to_extract)
    if isempty(channels_to_extract), return; end
    all_fields      = fieldnames(session);
    requested_san   = cellfun(@(c) regexprep(c,'[^a-zA-Z0-9_]','_'), ...
                              channels_to_extract, 'UniformOutput', false);
    fields_lower    = lower(all_fields);
    requested_lower = lower([channels_to_extract(:); requested_san(:)]);
    keep_mask       = ismember(fields_lower, requested_lower);
    drop            = all_fields(~keep_mask);
    if ~isempty(drop)
        session = rmfield(session, drop);
    end
end


% ======================================================================= %
function merged = concat_sessions(sessions)
    merged    = sessions{1};
    ch_fields = fieldnames(merged);

    for s = 2:numel(sessions)
        s2       = sessions{s};
        t_offset = 0;

        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
               ~isempty(merged.(fn).time)
                t_offset = merged.(fn).time(end);
                break;
            end
        end

        if isfield(merged, 'Lap_Number') && numel(merged.Lap_Number.time) > 1
            t_offset = t_offset + median(diff(merged.Lap_Number.time));
        else
            t_offset = t_offset + 0.02;
        end

        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if ~isfield(s2, fn), continue; end
            merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
            merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
        end
    end
end


% ======================================================================= %
function write_done_flag(worker_id, tmp_dir)
    flag_file = fullfile(tmp_dir, sprintf('vch_done_%d.flag', worker_id));
    fid = fopen(flag_file, 'w');
    fprintf(fid, 'done at %s', datestr(now));
    fclose(fid);
    fprintf('Worker %d: done flag written.\n', worker_id);
end
