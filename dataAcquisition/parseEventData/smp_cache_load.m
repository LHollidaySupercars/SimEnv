% function cache = smp_cache_load(top_level_dir)
% % SMP_CACHE_LOAD  Load the SMP file cache manifest from disk.
% % If no cache exists yet, returns an empty cache struct ready to be populated.
% % Cache file lives at: <top_level_dir>\smp_cache.mat
% 
%     cache_path = fullfile(top_level_dir, 'smp_cache.mat');
% 
%     if exist(cache_path, 'file')
%         fprintf('Loading cache: %s\n', cache_path);
%         tic
%         loaded = load(cache_path, 'cache');
%         toc
%         cache  = loaded.cache;
%         fprintf('  Cache has %d entries.\n', height(cache.manifest));
%     else
%         fprintf('No cache found — starting fresh.\n');
%         cache = smp_cache_empty();
%     end
% end
function cache = smp_cache_load(top_level_dir, session_filter)
% SMP_CACHE_LOAD  Load the SMP cache from disk.
%
% Automatically detects whether the cache was saved in 'legacy' (single
% file) or 'session' (per-session files) mode, and loads accordingly.
%
% Usage:
%   cache = smp_cache_load(top_level_dir)
%       Legacy mode  : loads smp_cache.mat  (all sessions, same as before)
%       Session mode : loads ALL smp_cache_*.mat files and merges them
%
%   cache = smp_cache_load(top_level_dir, {'RA1','RA2'})
%       Legacy mode  : loads smp_cache.mat  (filter applied after load —
%                      same RAM cost, but you only pay it once at compile time)
%       Session mode : loads ONLY smp_cache_RA1.mat + smp_cache_RA2.mat
%                      (fast — other sessions never touch RAM)
%
%   cache = smp_cache_load(top_level_dir, {})
%       Loads all sessions regardless of mode (pass {} or omit arg).
%
% Output:
%   cache — standard cache struct with fields:
%     .manifest   table
%     .stats      struct
%     .traces     struct
%     .channels   containers.Map
%     .mode       'stream' or 'bulk'
%     .save_mode  'legacy' or 'session'
%
% Backwards compatibility:
%   If only smp_cache.mat exists (old pipeline), it is loaded as-is.
%   The returned struct is identical in shape to what downstream functions
%   (smp_filter_cache, smp_cache_diff, etc.) have always expected.

    if nargin < 2
        session_filter = {};
    end
    if ischar(session_filter) || isstring(session_filter)
        session_filter = {char(session_filter)};
    end

    legacy_path    = fullfile(top_level_dir, 'smp_cache.mat');
    session_files  = dir(fullfile(top_level_dir, 'smp_cache_*.mat'));

    % ------------------------------------------------------------------
    %  Detect mode
    % ------------------------------------------------------------------
    has_legacy   = exist(legacy_path, 'file') == 2;
    has_sessions = ~isempty(session_files);

    if ~has_legacy && ~has_sessions
        fprintf('No cache found — starting fresh.\n');
        cache = smp_cache_empty();
        cache.save_mode = 'legacy';   % default for new caches
        return;
    end

    % If both exist, session files take precedence (user has migrated)
    if has_sessions
        cache = load_session_files(top_level_dir, session_files, session_filter);
    else
        % Legacy only
        cache = load_legacy(legacy_path, session_filter);
    end
end


% ======================================================================= %
%  LOAD LEGACY — single smp_cache.mat
% ======================================================================= %
function cache = load_legacy(legacy_path, session_filter)
    fprintf('Loading cache (legacy): %s\n', legacy_path);
    tic;
    loaded = load(legacy_path, 'cache');
    t = toc;
    cache = loaded.cache;

    % Backwards compat fields
    if ~isfield(cache, 'stats'),     cache.stats     = struct(); end
    if ~isfield(cache, 'traces'),    cache.traces    = struct(); end
    if ~isfield(cache, 'save_mode'), cache.save_mode = 'legacy'; end
    if ~isfield(cache, 'mode'),      cache.mode      = 'stream'; end
    if ~isfield(cache, 'channels') || ~isa(cache.channels, 'containers.Map')
        cache.channels = containers.Map('KeyType','char','ValueType','any');
    end

    fprintf('  Cache loaded in %.1fs  (%d entries)\n', t, height(cache.manifest));

    % Session filter is informational only in legacy mode — we load
    % everything but warn the user that splitting would be faster.
    if ~isempty(session_filter)
        fprintf('  [INFO] session_filter supplied in legacy mode — all data loaded.\n');
        fprintf('         Re-compile with save_mode=''session'' for faster partial loads.\n');
    end
end


% ======================================================================= %
%  LOAD SESSION FILES — merge selected smp_cache_*.mat files
% ======================================================================= %
function cache = load_session_files(top_level_dir, session_files, session_filter)

    % Build list of (session_name, file_path) pairs from filenames
    % Filename format: smp_cache_<sess_safe>.mat
    file_sessions = cell(numel(session_files), 1);
    file_paths    = cell(numel(session_files), 1);

    for i = 1:numel(session_files)
        fname = session_files(i).name;
        % Strip prefix 'smp_cache_' and suffix '.mat'
        tok = regexp(fname, '^smp_cache_(.+)\.mat$', 'tokens');
        if ~isempty(tok)
            file_sessions{i} = tok{1}{1};   % e.g. 'FP1', 'RA1'
        else
            file_sessions{i} = fname;
        end
        file_paths{i} = fullfile(top_level_dir, fname);
    end

    % Filter to requested sessions
    if isempty(session_filter)
        to_load_idx = 1:numel(session_files);
        fprintf('Loading cache (session mode): all %d session file(s)...\n', numel(session_files));
    else
        % Match session_filter against discovered session names
        % Use case-insensitive partial match so 'RA1' matches file 'RA1'
        to_load_idx = [];
        for f = 1:numel(file_sessions)
            for k = 1:numel(session_filter)
                if strcmpi(file_sessions{f}, strtrim(session_filter{k}))
                    to_load_idx(end+1) = f; %#ok<AGROW>
                    break;
                end
            end
        end

        if isempty(to_load_idx)
            fprintf('  [WARN] No session cache files matched filter: %s\n', ...
                strjoin(session_filter, ', '));
            fprintf('         Available: %s\n', strjoin(file_sessions, ', '));
            fprintf('         Starting fresh.\n');
            cache = smp_cache_empty();
            cache.save_mode = 'session';
            return;
        end

        fprintf('Loading cache (session mode): %d/%d file(s) matching [%s]...\n', ...
            numel(to_load_idx), numel(session_files), strjoin(session_filter, ', '));
    end

    % ------------------------------------------------------------------
    %  Load and merge
    % ------------------------------------------------------------------
    cache = smp_cache_empty();
    cache.save_mode = 'session';
    cache.mode      = 'stream';   % will be overwritten from first file

    for i = 1:numel(to_load_idx)
        idx  = to_load_idx(i);
        fpath = file_paths{idx};
        sess  = file_sessions{idx};

        fprintf('  [%d/%d] %s ... ', i, numel(to_load_idx), sess);
        tic;
        loaded = load(fpath, 'sess_cache');
        sc     = loaded.sess_cache;
        t      = toc;
        fprintf('%.1fs  (%d rows)\n', t, height(sc.manifest));

        % ---- Merge manifest ----
        if height(cache.manifest) == 0
            cache.manifest = sc.manifest;
        else
            % Align columns before vertical concat
            cache.manifest = merge_tables(cache.manifest, sc.manifest);
        end

        % ---- Merge stats ----
        if isfield(sc, 'stats')
            fns = fieldnames(sc.stats);
            for k = 1:numel(fns)
                cache.stats.(fns{k}) = sc.stats.(fns{k});
            end
        end

        % ---- Merge traces ----
        if isfield(sc, 'traces')
            fns = fieldnames(sc.traces);
            for k = 1:numel(fns)
                cache.traces.(fns{k}) = sc.traces.(fns{k});
            end
        end

        % ---- Merge channels map (bulk mode compat) ----
        if isfield(sc, 'channels') && isa(sc.channels, 'containers.Map') && sc.channels.Count > 0
            ckeys = keys(sc.channels);
            for k = 1:numel(ckeys)
                cache.channels(ckeys{k}) = sc.channels(ckeys{k});
            end
        end

        % ---- Propagate mode ----
        if isfield(sc, 'mode')
            cache.mode = sc.mode;
        end
    end

    % Deduplicate manifest rows by Path (safety net for overlapping compiles)
    if height(cache.manifest) > 0
        [~, ui] = unique(cache.manifest.Path, 'stable');
        cache.manifest = cache.manifest(ui, :);
    end

    fprintf('Session load complete: %d total entries.\n', height(cache.manifest));
end


% ======================================================================= %
%  TABLE MERGE — align columns before vertcat
% ======================================================================= %
function T = merge_tables(T1, T2)
% Vertically concatenate two tables that may have different column sets.
% Missing columns are filled with appropriate empty values.

    cols1 = T1.Properties.VariableNames;
    cols2 = T2.Properties.VariableNames;
    all_cols = union(cols1, cols2, 'stable');

    % Add missing columns to T1
    for c = 1:numel(all_cols)
        col = all_cols{c};
        if ~ismember(col, cols1)
            T1 = add_empty_col(T1, col, T2.(col));
        end
    end

    % Add missing columns to T2
    for c = 1:numel(all_cols)
        col = all_cols{c};
        if ~ismember(col, cols2)
            T2 = add_empty_col(T2, col, T1.(col));
        end
    end

    % Reorder T2 to match T1 column order
    T2 = T2(:, T1.Properties.VariableNames);
    T  = [T1; T2];
end


function T = add_empty_col(T, col_name, ref_col)
% Add a column of the same type as ref_col, filled with empty/zero/NaT.
    n = height(T);
    if isnumeric(ref_col)
        T.(col_name) = zeros(n, 1);
    elseif islogical(ref_col)
        T.(col_name) = false(n, 1);
    elseif isdatetime(ref_col)
        T.(col_name) = NaT(n, 1);
    elseif isstring(ref_col)
        T.(col_name) = strings(n, 1);
    elseif iscell(ref_col)
        T.(col_name) = repmat({''}, n, 1);
    else
        T.(col_name) = repmat({''}, n, 1);
    end
end