function [SMP, cache] = smp_load_teams(top_level_dir, team_filter, varargin)
% SMP_LOAD_TEAMS  Scan folders, load new/changed .ld files, build SMP struct.
%
% Output structure:
%   SMP.(event).(team).meta        table of runs for this event+team
%   SMP.(event).(team).channels    cell array — channels{n} for run n
%   SMP.(event).(team).info        cell array — info{n} for run n
%
%   event  = sanitised canonical name from alias lookup on info.venue
%            e.g. venue "Sydney Motorsport Park" → alias lookup → 'SMP'
%            Falls back to sanitised raw venue string if no alias found.
%   team   = team acronym e.g. 'T8R', 'WAU'
%
% Usage:
%   [SMP, cache] = smp_load_teams('C:\LOCAL_DATA\01 - SMP\_Team Data', {})
%   [SMP, cache] = smp_load_teams('C:\LOCAL_DATA\01 - SMP\_Team Data', {'T8R'})
%
% Optional: place eventAlias.xlsx in top_level_dir or pass alias struct
% as a third argument to use alias-based event key resolution.
%
%   alias = smp_alias_load('C:\SMP\config\eventAlias.xlsx');
%   [SMP, cache] = smp_load_teams(dir, {}, alias);

    % Optional alias struct as third argument
    if nargin >= 3 && ~isempty(varargin)
        alias = varargin{1};
    else
        % Look for alias file alongside the data folder
        default_alias = fullfile(top_level_dir, 'eventAlias.xlsx');
        alias = smp_alias_load(default_alias);
    end

    % ------------------------------------------------------------------
    %  1. Scan all team folders
    % ------------------------------------------------------------------
    fprintf('=== Scanning: %s ===\n', top_level_dir);
    scan_all = smp_scan_folders(top_level_dir);
    if isempty(scan_all)
        error('smp_load_teams: No valid team folders found.');
    end

    % ------------------------------------------------------------------
    %  2. Narrow to requested teams
    % ------------------------------------------------------------------
    if isempty(team_filter)
        scan_load = scan_all;
    else
        scan_load = filter_scan(scan_all, team_filter);
        fprintf('Filter applied — loading %d of %d teams.\n', ...
            numel(scan_load), numel(scan_all));
    end

    if isempty(scan_load)
        error('smp_load_teams: No teams matched filter: %s', ...
            strjoin(team_filter, ', '));
    end

    % ------------------------------------------------------------------
    %  3. Load cache, diff, load new/changed files
    % ------------------------------------------------------------------
    cache = smp_cache_load(top_level_dir);
    [to_load, cache] = smp_cache_diff(cache, scan_load);

    if isempty(to_load)
        fprintf('All files up to date — nothing new to load.\n\n');
    else
        fprintf('\nLoading %d new/changed files...\n', numel(to_load));
        for i = 1:numel(to_load)
            fpath = to_load(i).path;
            tidx  = to_load(i).team_index;
            tacro = to_load(i).team_acronym;
            [~, fname] = fileparts(fpath);
            fprintf('  [%d/%d] %s  %s\n', i, numel(to_load), tacro, fname);

            info_s   = struct();
            channels = struct();
            load_ok  = false;
            err_msg  = '';

            try
                info_s = motec_ld_info(fpath);
            catch ME
                fprintf('    [WARN] motec_ld_info: %s\n', ME.message);
            end

            try
                channels = motec_ld_reader(fpath);
                load_ok  = true;
            catch ME
                err_msg = ME.message;
                fprintf('    [ERROR] motec_ld_reader: %s\n', ME.message);
            end

            cache = smp_cache_add(cache, fpath, tidx, tacro, ...
                                  info_s, channels, load_ok, err_msg);
        end
        smp_cache_save(top_level_dir, cache);
    end

    % ------------------------------------------------------------------
    %  4. Build SMP.(event).(team) struct
    % ------------------------------------------------------------------
    SMP = build_smp_struct(cache, scan_load, alias);

end


% ======================================================================= %
function scan_filtered = filter_scan(scan_all, team_filter)
    scan_filtered = struct('index',{}, 'acronym',{}, 'folder',{}, 'files',{});
    n = 0;
    for t = 1:numel(scan_all)
        idx_str = sprintf('%02d', scan_all(t).index);
        acro    = scan_all(t).acronym;
        for f = 1:numel(team_filter)
            key = upper(strtrim(team_filter{f}));
            if strcmp(key, idx_str) || strcmp(key, acro)
                n = n + 1;
                scan_filtered(n) = scan_all(t);
                break;
            end
        end
    end
end


% ======================================================================= %
function SMP = build_smp_struct(cache, scan_load, ~)
% Build SMP.(team).{meta, channels, info}
%
% Team key = team acronym e.g. 'T8R', 'WAU'
% All runs for a team are stored flat — all events, all sessions.
% Use smp_filter to narrow by event, session, year, etc. after loading.

    SMP = struct();

    for t = 1:numel(scan_load)
        acro = scan_load(t).acronym;
        mask = strcmp(cache.manifest.TeamAcronym, acro);

        if ~any(mask)
            fprintf('[WARN] "%s" not found in cache — skipping.\n', acro);
            continue;
        end

        rows      = find(mask);
        meta_rows = cache.manifest(rows, :);
        n_runs    = numel(rows);

        ch_cells = cell(n_runs, 1);
        in_cells = cell(n_runs, 1);
        for r = 1:n_runs
            p = meta_rows.Path{r};
            if isKey(cache.channels, p), ch_cells{r} = cache.channels(p); end
            if isKey(cache.info,     p), in_cells{r} = cache.info(p);     end
        end

        SMP.(acro).meta     = meta_rows;
        SMP.(acro).channels = ch_cells;
        SMP.(acro).info     = in_cells;
    end

    % Summary
    fprintf('\nSMP struct ready.\n');
    team_keys = fieldnames(SMP);
    for t = 1:numel(team_keys)
        tk = team_keys{t};
        n  = height(SMP.(tk).meta);
        sessions = unique(SMP.(tk).meta.Session);
        fprintf('  SMP.%-8s  %d runs   sessions: %s\n', ...
            tk, n, strjoin(sessions, ', '));
    end
    fprintf('\n');
end
