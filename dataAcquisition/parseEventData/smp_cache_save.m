% function smp_cache_save(top_level_dir, cache)
% % SMP_CACHE_SAVE  Save the updated cache manifest to disk.
% 
%     cache_path = fullfile(top_level_dir, 'smp_cache.mat');
%     save(cache_path, 'cache', '-v7.3');
%     fprintf('Cache saved: %s  (%d entries)\n', cache_path, height(cache.manifest));
% end
function smp_cache_save(top_level_dir, cache, save_mode, alias)
% SMP_CACHE_SAVE  Save the SMP cache to disk.
%
% Two modes controlled by the optional save_mode argument (or cache.save_mode):
%
%   'legacy'  (default) — saves everything to one file: smp_cache.mat
%             Identical behaviour to the original function.
%
%   'session' — splits the cache by Session and saves one file per session:
%               smp_cache_FP1.mat, smp_cache_RA1.mat, etc.
%             If alias is provided, session names are resolved to their
%             canonical alias value before use as filenames.
%             Sessions with no alias mapping are skipped with a warning.
%             If alias is not provided, raw session strings are used as-is
%             (original behaviour — backwards compatible).
%
% Usage:
%   smp_cache_save(top_level_dir, cache)                      % legacy
%   smp_cache_save(top_level_dir, cache, 'session')           % session, raw names
%   smp_cache_save(top_level_dir, cache, 'session', alias)    % session, aliased names

    % ------------------------------------------------------------------
    %  Resolve mode
    % ------------------------------------------------------------------
    if nargin < 3 || isempty(save_mode)
        save_mode = '';
    end
    if nargin < 4
        alias = [];
    end

    if ~isempty(save_mode)
        mode = lower(strtrim(save_mode));
    elseif isfield(cache, 'save_mode') && ~isempty(cache.save_mode)
        mode = lower(strtrim(cache.save_mode));
    else
        mode = 'legacy';
    end

    if ~ismember(mode, {'legacy', 'session'})
        warning('smp_cache_save: unknown save_mode "%s" — defaulting to legacy.', mode);
        mode = 'legacy';
    end

    cache.save_mode = mode;

    % ------------------------------------------------------------------
    %  Dispatch
    % ------------------------------------------------------------------
    switch mode
        case 'legacy'
            save_legacy(top_level_dir, cache);
        case 'session'
            save_by_session(top_level_dir, cache, alias);
    end
end


% ======================================================================= %
%  LEGACY — single file, identical to original behaviour
% ======================================================================= %
function save_legacy(top_level_dir, cache)
    cache_path = fullfile(top_level_dir, 'smp_cache.mat');
    fprintf('Saving cache (legacy): %s\n', cache_path);
    tic;
    try
        save(cache_path, 'cache', '-v7');
    catch
        fprintf('  File too large for -v7, falling back to -v7.3 (slower)...\n');
        save(cache_path, 'cache', '-v7.3');
    end
    t = toc;
    fprintf('Cache saved in %.1fs  (%d entries)\n', t, height(cache.manifest));
end


% ======================================================================= %
%  SESSION SPLIT — one .mat per session
% ======================================================================= %
function save_by_session(top_level_dir, cache, alias)

    T = cache.manifest;

    if height(T) == 0
        fprintf('smp_cache_save (session): manifest is empty — nothing to save.\n');
        return;
    end

    % Build alias lookup if provided
    has_alias = ~isempty(alias) && isstruct(alias) && ...
                isfield(alias, 'session') && isfield(alias.session, 'lookup') && ...
                alias.session.lookup.Count > 0;

    % Unique raw session strings present in this cache
    raw_sessions = unique(string(T.Session));
    raw_sessions  = raw_sessions(strtrim(raw_sessions) ~= "");

    if isempty(raw_sessions)
        fprintf('  [WARN] No Session column values found — falling back to legacy save.\n');
        save_legacy(top_level_dir, cache);
        return;
    end

    fprintf('Saving cache (session mode): %d raw session(s)...\n', numel(raw_sessions));

    n_saved  = 0;
    n_skip   = 0;

    for s = 1:numel(raw_sessions)
        raw_sess = char(raw_sessions(s));

        % --- Resolve to canonical name via alias ---
        if has_alias
            lut = alias.session.lookup;
            if isKey(lut, lower(raw_sess))
                canonical = lut(lower(raw_sess));
            else
                fprintf('  [SKIP] "%s" — no alias mapping found. Add to eventAlias.xlsx SESSION sheet.\n', raw_sess);
                n_skip = n_skip + 1;
                continue;
            end
        else
            % No alias provided — use raw string as-is (backwards compat)
            canonical = raw_sess;
        end

        sess_safe = matlab.lang.makeValidName(canonical);

        % ---- Partition manifest by raw session string ----
        row_mask      = strcmp(string(T.Session), raw_sess);
        part_manifest = T(row_mask, :);

        % ---- Partition stats and traces by group key ----
        part_stats  = struct();
        part_traces = struct();

        if ismember('GroupKey', part_manifest.Properties.VariableNames)
            gkeys = unique(string(part_manifest.GroupKey));
            gkeys = gkeys(strtrim(gkeys) ~= "");

            for k = 1:numel(gkeys)
                gk     = char(gkeys(k));
                gk_vld = matlab.lang.makeValidName(gk);

                if isfield(cache.stats, gk_vld)
                    part_stats.(gk_vld) = cache.stats.(gk_vld);
                end
                if isfield(cache.traces, gk_vld)
                    part_traces.(gk_vld) = cache.traces.(gk_vld);
                end
            end
        else
            % No GroupKey — best effort match by session name in key string
            all_keys = fieldnames(cache.stats);
            for k = 1:numel(all_keys)
                if contains(lower(all_keys{k}), lower(sess_safe))
                    part_stats.(all_keys{k}) = cache.stats.(all_keys{k});
                    if isfield(cache.traces, all_keys{k})
                        part_traces.(all_keys{k}) = cache.traces.(all_keys{k});
                    end
                end
            end
        end

        % ---- Assemble session cache ----
        sess_cache           = struct();
        sess_cache.manifest  = part_manifest;
        sess_cache.stats     = part_stats;
        sess_cache.traces    = part_traces;
        sess_cache.mode      = cache.mode;
        sess_cache.save_mode = 'session';
        sess_cache.canonical_session = canonical;   % store for load-side display

        % Bulk mode channels map
        if isfield(cache, 'channels') && isa(cache.channels, 'containers.Map')
            paths = part_manifest.Path;
            sess_cache.channels = containers.Map('KeyType','char','ValueType','any');
            for p = 1:numel(paths)
                pk = char(paths(p));
                if isKey(cache.channels, pk)
                    sess_cache.channels(pk) = cache.channels(pk);
                end
            end
        else
            sess_cache.channels = containers.Map('KeyType','char','ValueType','any');
        end

        % ---- Save ----
        cache_path = fullfile(top_level_dir, sprintf('smp_cache_%s.mat', sess_safe));
        fprintf('  [%d/%d] "%s" → "%s"  (%d rows, %d stats, %d traces)\n', ...
            s, numel(raw_sessions), raw_sess, canonical, height(part_manifest), ...
            numel(fieldnames(part_stats)), numel(fieldnames(part_traces)));
        tic;
        try
            save(cache_path, 'sess_cache', '-v7');
            fmt = '-v7';
        catch
            save(cache_path, 'sess_cache', '-v7.3');
            fmt = '-v7.3';
        end
        t = toc;
        fprintf('    saved in %.1fs  [%s]  → %s\n', t, fmt, cache_path);
        n_saved = n_saved + 1;
    end

    fprintf('Session cache save complete: %d saved, %d skipped.\n', n_saved, n_skip);
    if n_skip > 0
        fprintf('  Add skipped sessions to eventAlias.xlsx SESSION sheet to include them.\n');
    end
end


% ======================================================================= %
%  LEGACY — single file, identical to original behaviour
% ======================================================================= %
% function save_legacy(top_level_dir, cache)
%     cache_path = fullfile(top_level_dir, 'smp_cache.mat');
%     fprintf('Saving cache (legacy): %s\n', cache_path);
%     tic;
%     try
%         save(cache_path, 'cache', '-v7');
%     catch
%         fprintf('  File too large for -v7, falling back to -v7.3 (slower)...\n');
%         save(cache_path, 'cache', '-v7.3');
%     end
%     t = toc;
%     fprintf('Cache saved in %.1fs  (%d entries)\n', t, height(cache.manifest));
% end


% ======================================================================= %
%  SESSION SPLIT — one .mat per session
% ======================================================================= %
% function save_by_session(top_level_dir, cache)
% 
%     T = cache.manifest;
% 
%     if height(T) == 0
%         fprintf('smp_cache_save (session): manifest is empty — nothing to save.\n');
%         return;
%     end
% 
%     % Unique sessions present in this cache
%     sessions = unique(string(T.Session));
%     sessions = sessions(strtrim(sessions) ~= "");
% 
%     if isempty(sessions)
%         fprintf('  [WARN] No Session column values found — falling back to legacy save.\n');
%         save_legacy(top_level_dir, cache);
%         return;
%     end
% 
%     fprintf('Saving cache (session mode): %d session(s)...\n', numel(sessions));
% 
%     for s = 1:numel(sessions)
%         sess      = char(sessions(s));
%         sess_safe = matlab.lang.makeValidName(sess);   % e.g. 'FP1', 'RA1'
% 
%         % ---- Partition manifest ----
%         row_mask      = strcmp(string(T.Session), sess);
%         part_manifest = T(row_mask, :);
% 
%         % ---- Partition stats and traces by group key ----
%         % Group keys that belong to this session are identified by cross-
%         % referencing the manifest GroupKey column for matching rows.
%         part_stats  = struct();
%         part_traces = struct();
% 
%         if ismember('GroupKey', part_manifest.Properties.VariableNames)
%             gkeys = unique(string(part_manifest.GroupKey));
%             gkeys = gkeys(strtrim(gkeys) ~= "");
% 
%             for k = 1:numel(gkeys)
%                 gk     = char(gkeys(k));
%                 gk_vld = matlab.lang.makeValidName(gk);
% 
%                 if isfield(cache.stats, gk_vld)
%                     part_stats.(gk_vld) = cache.stats.(gk_vld);
%                 end
%                 if isfield(cache.traces, gk_vld)
%                     part_traces.(gk_vld) = cache.traces.(gk_vld);
%                 end
%             end
%         else
%             % No GroupKey column — best-effort: match by session name in key string
%             all_keys = fieldnames(cache.stats);
%             for k = 1:numel(all_keys)
%                 if contains(lower(all_keys{k}), lower(sess_safe))
%                     part_stats.(all_keys{k}) = cache.stats.(all_keys{k});
%                     if isfield(cache.traces, all_keys{k})
%                         part_traces.(all_keys{k}) = cache.traces.(all_keys{k});
%                     end
%                 end
%             end
%         end
% 
%         % ---- Assemble session cache ----
%         sess_cache           = struct();
%         sess_cache.manifest  = part_manifest;
%         sess_cache.stats     = part_stats;
%         sess_cache.traces    = part_traces;
%         sess_cache.mode      = cache.mode;
%         sess_cache.save_mode = 'session';
% 
%         % Carry over channels map if present (bulk mode compat)
%         if isfield(cache, 'channels') && isa(cache.channels, 'containers.Map')
%             paths = part_manifest.Path;
%             sess_cache.channels = containers.Map('KeyType','char','ValueType','any');
%             for p = 1:numel(paths)
%                 pk = char(paths(p));
%                 if isKey(cache.channels, pk)
%                     sess_cache.channels(pk) = cache.channels(pk);
%                 end
%             end
%         else
%             sess_cache.channels = containers.Map('KeyType','char','ValueType','any');
%         end
% 
%         % ---- Save ----
%         cache_path = fullfile(top_level_dir, sprintf('smp_cache_%s.mat', sess_safe));
%         fprintf('  [%d/%d] %s  (%d rows, %d stats, %d traces) → %s\n', ...
%             s, numel(sessions), sess, height(part_manifest), ...
%             numel(fieldnames(part_stats)), numel(fieldnames(part_traces)), ...
%             cache_path);
%         tic;
%         try
%             save(cache_path, 'sess_cache', '-v7');
%             fmt = '-v7';
%         catch
%             save(cache_path, 'sess_cache', '-v7.3');
%             fmt = '-v7.3';
%         end
%         t = toc;
%         fprintf('    saved in %.1fs  [%s]\n', t, fmt);
%     end
% 
%     fprintf('Session cache save complete.\n');
% end