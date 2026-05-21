function cache = smp_recompute_vch(top_level_dir, season, driver_map, alias, channels, opts, cache_in)
% SMP_RECOMPUTE_VCH  Recompute custom channel stats in cache without full recompile.
%
% Re-reads .ld files for every group in the cache, reruns smp_custom_channels
% and smp_gated_channels, reslices laps, then overwrites ONLY the custom
% channel stat fields in cache.stats. All other channel stats are untouched.
%
% Usage:
%   cache = smp_recompute_vch(top_level_dir, season, driver_map, alias, channels)
%   cache = smp_recompute_vch(top_level_dir, season, driver_map, alias, channels, opts)
%   cache = smp_recompute_vch(top_level_dir, season, driver_map, alias, channels, opts, cache)
%
% Inputs:
%   top_level_dir   path to team data folder (same as compile)
%   season          struct from smp_season_load()
%   driver_map      struct from smp_driver_alias_load()
%   alias           struct from smp_alias_load()
%   channels        cell array from smp_channel_config_load()
%   opts:
%     .track          track acronym for lap time limits (default: '')
%     .session_filter cell array of sessions to limit scope (default: {} = all)
%     .save_mode      'session' or 'legacy' (default: matches loaded cache)
%     .verbose        (default: true)
%     .T_gated        pre-loaded gatedChannels table (skips disk read if supplied)
%     .channels_file  path to channels.xlsx (default: resolved from top_level_dir)
%   cache_in        (optional) already-loaded cache struct — skips disk load

    if nargin < 6 || isempty(opts), opts     = struct(); end
    if nargin < 7,                  cache_in = [];       end

    track          = get_opt(opts, 'track',          '');
    session_filter = get_opt(opts, 'session_filter', {});
    verbose        = get_opt(opts, 'verbose',        true);
    load_all_ch    = get_opt(opts, 'load_all_channels', false);

    fprintf('\n============================================\n');
    fprintf('  SMP Recompute VCH  (serial)\n');
    fprintf('  Track  : %s\n', track);
    fprintf('  Time   : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('============================================\n\n');

    % ------------------------------------------------------------------
    %  Lap time limits
    % ------------------------------------------------------------------
    if ~isempty(track) && ~isempty(season)
        [min_lt, max_lt] = smp_season_get(season, track);
        fprintf('Lap time limits: %.1fs - %.1fs\n\n', min_lt, max_lt);
    else
        min_lt = 10;
        max_lt = 600;
        fprintf('[WARN] No track specified - using default lap time limits (10s / 600s).\n\n');
    end

    lap_opts.min_lap_time    = min_lt;
    lap_opts.max_lap_time    = max_lt;
    lap_opts.verbose         = false;
    lap_opts.detect_pitlane  = get_opt(opts, 'detect_pitlane', false);
    lap_opts.fcy_channel     = get_opt(opts, 'fcy_channel',    'Sw_State_SC');
    lap_opts.br2_channel     = get_opt(opts, 'br2_channel',    'BR2_Beacon_Number');
    lap_opts.br2_protocol    = get_opt(opts, 'br2_protocol',   'standard');
    lap_opts.beacon_check    = get_opt(opts, 'beacon_check',   false);

    stat_ops = {'max','min','mean','median','std','var','range','change', ...
                'max non zero','min non zero','mean non zero', ...
                'median non zero','std non zero','sample_rate'};

    % ------------------------------------------------------------------
    %  Load cache — skip if already provided by caller
    % ------------------------------------------------------------------
    if ~isempty(cache_in) && isstruct(cache_in) && isfield(cache_in, 'manifest')
        cache = cache_in;
        fprintf('Using supplied cache (%d manifest rows) — skipping disk load.\n\n', ...
            height(cache.manifest));
    else
        fprintf('Loading cache from disk...\n');
        cache = smp_cache_load(top_level_dir, session_filter);
        fprintf('Cache loaded (%d manifest rows).\n\n', height(cache.manifest));
    end
    save_mode = get_opt(opts, 'save_mode', cache.save_mode);

    if height(cache.manifest) == 0
        fprintf('Cache is empty - nothing to recompute.\n');
        return;
    end

    % ------------------------------------------------------------------
    %  Build unique group list from manifest
    % ------------------------------------------------------------------
    groups   = groups_from_manifest(cache.manifest, session_filter);
    n_groups = numel(groups);
    fprintf('%d group(s) to recompute.\n\n', n_groups);

    % ------------------------------------------------------------------
    %  Load gated channel definitions once
    %  Accept pre-loaded table from caller via opts.T_gated to avoid
    %  redundant disk reads when the caller already has this table.
    % ------------------------------------------------------------------
    if isfield(opts, 'T_gated') && ~isempty(opts.T_gated)
        T_gated = opts.T_gated;
        fprintf('Using supplied gated channel definitions: %d row(s)\n\n', height(T_gated));
    else
        if isfield(opts, 'channels_file') && ~isempty(opts.channels_file)
            GATED_EXCEL = opts.channels_file;
        else
            % Derive path relative to this function's location so it is
            % portable across machines.
            here        = fileparts(mfilename('fullpath'));
            GATED_EXCEL = fullfile(here, 'channels', 'channels.xlsx');
        end
        try
            T_gated = readtable(GATED_EXCEL, 'Sheet', 'gatedChannels', 'TextType', 'char');
            fprintf('Loaded gated channel definitions: %d row(s)\n\n', height(T_gated));
        catch ME
            warning('smp_recompute_vch: could not read gatedChannels - %s', ME.message);
            T_gated = table();
        end
    end

    % ------------------------------------------------------------------
    %  Process each group
    % ------------------------------------------------------------------
    for g = 1:n_groups
        grp = groups(g);
        fprintf('[%d/%d] %s | %s | %s | %d file(s)\n', ...
            g, n_groups, grp.team_acronym, grp.driver, grp.session, numel(grp.files));

        group_key = matlab.lang.makeValidName(grp.key);

        if ~isfield(cache.stats, group_key)
            fprintf('  [WARN] group_key "%s" not found in cache.stats - skipping.\n', group_key);
            continue;
        end

        try
            fprintf('  Loading .ld file(s)...\n');
            session = load_and_concat(grp.files, channels, verbose, T_gated, load_all_ch, driver_map);

            if isempty(session)
                fprintf('  [WARN] No channel data returned - skipping.\n');
                continue;
            end

            % ---- Detect which fields smp_custom_channels added ----
            all_session_fields = fieldnames(session);
            raw_fields_san     = cellfun(@(c) regexprep(c, '[^a-zA-Z0-9_]', '_'), ...
                                         channels, 'UniformOutput', false);
            raw_fields_lower   = lower([channels(:); raw_fields_san(:)]);
            custom_fields      = all_session_fields( ...
                ~ismember(lower(all_session_fields), raw_fields_lower));

            if isempty(custom_fields)
                fprintf('  [WARN] No custom channels detected - skipping.\n');
                clear session;
                continue;
            end

            if verbose
                fprintf('  Custom channels detected (%d): %s\n', ...
                    numel(custom_fields), strjoin(custom_fields, ', '));
            end

            % ---- Slice laps ----
            fprintf('  Slicing laps...\n');
            laps = lap_slicer(session, lap_opts);
            clear session;

            if isempty(laps)
                fprintf('  [WARN] No valid laps - skipping.\n');
                continue;
            end
            fprintf('  %d valid lap(s).\n', numel(laps));
            fieldsToKeep = [T_gated.CHANNEL_NAME; custom_fields];
            % ---- Compute stats for custom channels only ----
%             vch_stats = lap_stats(laps, custom_fields, ...
%                 struct('operations', {stat_ops}));
            vch_stats = lap_stats(laps, fieldsToKeep, ...
                struct('operations', {stat_ops}));
            clear laps;

            % ---- Merge into existing cache stats (overwrite custom fields only) ----
            vch_keys = fieldnames(vch_stats);
            for k = 1:numel(vch_keys)
                cache.stats.(group_key).(vch_keys{k}) = vch_stats.(vch_keys{k});
            end

            fprintf('  Updated %d custom channel(s) in cache.stats.%s\n', ...
                numel(vch_keys), group_key);

        catch ME
            fprintf('  [ERROR] %s\n', ME.message);
            if verbose
                fprintf('  %s\n', ME.getReport('basic'));
            end
        end
    end

    % ------------------------------------------------------------------
    %  Save updated cache
    % ------------------------------------------------------------------
    fprintf('\nSaving cache...\n');
    tic;
    smp_cache_save(top_level_dir, cache, save_mode, alias);
    fprintf('Cache saved in %.1fs.\n\n', toc);

    fprintf('============================================\n');
    fprintf('  Recompute VCH complete  [%s]\n', datestr(now, 'HH:MM:SS'));
    fprintf('============================================\n');
end


% ======================================================================= %
%  LOAD AND CONCAT  (mirrors smp_compile_event exactly)
% ======================================================================= %
function session = load_and_concat(files, channels_to_extract, verbose, T_gated, load_all, driver_map)
    if nargin < 5, load_all   = false; end
    if nargin < 6, driver_map = [];    end
    EXCEL_FILTERING        = 'C:\SimEnv\dataAcquisition\Motec_MP\filterRequest\filterRequest.xlsx';
    CHANNELS_FOR_START_VAL = {'Acceleration_Z_Filt'};

    if load_all
        rd_channels = {};
    else
        rd_channels = channels_to_extract;
    end

    if numel(files) == 1
        session     = motec_ld_reader(files{1}, rd_channels);
        try, fi = motec_ld_info(files{1}, false); catch, fi = struct(); end
        mfr = ''; if isfield(fi, 'manufacturer'), mfr = fi.manufacturer; end
        if isempty(mfr) && isfield(fi, 'driver') && ~isempty(driver_map)
            mfr = resolve_manufacturer(fi.driver, driver_map);
        end
        startingVal = startingValues(CHANNELS_FOR_START_VAL, EXCEL_FILTERING, session);
        before      = fieldnames(session);
        session     = smp_custom_channels(session, 'startingValues', startingVal, 'manufacturer', mfr);
        vch_names   = setdiff(fieldnames(session), before);
        [session, gated_names]  = smp_gated_channels(session, T_gated);
        channels_to_extract     = union(channels_to_extract, [vch_names(:); gated_names(:)]);
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
        s = motec_ld_reader(files{f}, rd_channels);
        fprintf('  motec_ld_reader: %.2fs\n', toc(t0));

        try fi = motec_ld_info(files{f}, false); catch, fi = struct(); end
        mfr = ''; if isfield(fi, 'manufacturer'), mfr = fi.manufacturer; end
        if isempty(mfr) && isfield(fi, 'driver') && ~isempty(driver_map)
            mfr = resolve_manufacturer(fi.driver, driver_map);
        end

        t0 = tic;
        startingVal = startingValues(CHANNELS_FOR_START_VAL, EXCEL_FILTERING, s);
        before      = fieldnames(s);
        s = smp_custom_channels(s, 'startingValues', startingVal, 'manufacturer', mfr);
        vch_names   = setdiff(fieldnames(s), before);
        fprintf('  smp_custom_channels: %.2fs\n', toc(t0));

        t0 = tic;
        [s, gated_names]    = smp_gated_channels(s, T_gated);
        channels_to_extract = union(channels_to_extract, [vch_names(:); gated_names(:)]);
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
%  BUILD GROUP LIST FROM MANIFEST
% ======================================================================= %
function groups = groups_from_manifest(manifest, session_filter)
    groups = struct('key', {}, 'team_acronym', {}, 'driver', {}, ...
                    'session', {}, 'files', {});

    if ~isempty(session_filter)
        keep     = ismember(manifest.Session, session_filter);
        manifest = manifest(keep, :);
    end

    ok       = manifest.LoadOK & ~cellfun(@isempty, manifest.GroupKey);
    manifest = manifest(ok, :);

    if height(manifest) == 0, return; end

    unique_keys = unique(manifest.GroupKey, 'stable');

    for k = 1:numel(unique_keys)
        gk   = unique_keys{k};
        rows = manifest(strcmp(manifest.GroupKey, gk), :);

        g.key          = gk;
        g.team_acronym = rows.TeamAcronym{1};
        g.driver       = rows.Driver{1};
        g.session      = rows.Session{1};
        g.files        = rows.Path;

        groups(end+1) = g; %#ok<AGROW>
    end
end


% ======================================================================= %
function val = get_opt(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end


% ======================================================================= %
%  Resolve manufacturer from a driver name via driver_map.
%  Mirrors the resolve_driver_meta logic in smp_compile_event.
% ======================================================================= %
function mfr = resolve_manufacturer(driver_name, driver_map)
% Mirrors resolve_driver_meta lookup order: direct → strip-normalised → alias.
    mfr = '';
    if isempty(driver_name) || isempty(driver_map), return; end
    key   = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]', '');
    names = fieldnames(driver_map);
    entry = [];
    % 1. Direct key
    if isfield(driver_map, driver_name), entry = driver_map.(driver_name); end
    % 2. Strip-normalised key
    if isempty(entry)
        for i = 1:numel(names)
            if strcmp(key, regexprep(lower(names{i}), '[^a-z0-9]', ''))
                entry = driver_map.(names{i}); break;
            end
        end
    end
    % 3. Alias search
    if isempty(entry)
        for i = 1:numel(names)
            e = driver_map.(names{i});
            if ~isfield(e, 'aliases'), continue; end
            for a = 1:numel(e.aliases)
                if strcmp(key, regexprep(lower(e.aliases{a}), '[^a-z0-9]', ''))
                    entry = e; break;
                end
            end
            if ~isempty(entry), break; end
        end
    end
    if ~isempty(entry) && isfield(entry, 'manufacturer')
        mfr = entry.manufacturer;
    end
end