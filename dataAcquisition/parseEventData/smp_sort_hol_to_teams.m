function smp_sort_hol_to_teams(hol_dir, driver_alias_file, opts)
% SMP_SORT_HOL_TO_TEAMS  Sort HOL .ld files into team subfolders.
%
% Parses DRV_TLA from the filename (first token before '_'), looks it up
% in driverAlias.xlsx using the DRV_TLA column, then copies/moves the
% file into:
%   <hol_dir>\<TM_sorting_TLA>\<filename>.ld
%
% Expected filename pattern: <DRV_TLA>_<year>_<session>.ld
%   e.g. MOS_2026_R15.ld  →  team folder for MOS
%
% Usage:
%   smp_sort_hol_to_teams(hol_dir, driver_alias_file)
%   smp_sort_hol_to_teams(hol_dir, driver_alias_file, opts)
%
% Inputs:
%   hol_dir            - path to the HOL folder containing unsorted .ld files
%                        e.g. 'E:\2026\E05_TAS\_TeamData\_HOL\R15'
%   driver_alias_file  - path to driverAlias.xlsx
%   opts               - optional struct:
%     .overwrite        true = overwrite existing files in dest (default: false)
%     .move             true = move files, false = copy (default: false)
%     .verbose          true = print each file action (default: true)
%     .dry_run          true = print actions without doing them (default: false)

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 3, opts = struct(); end
    overwrite = get_opt(opts, 'overwrite', false);
    do_move   = get_opt(opts, 'move',      true);
    verbose   = get_opt(opts, 'verbose',   true);
    dry_run   = get_opt(opts, 'dry_run',   false);

    if dry_run
        fprintf('[DRY RUN] No files will be moved or copied.\n\n');
    end

    % ------------------------------------------------------------------
    %  Load driver alias table
    % ------------------------------------------------------------------
    fprintf('Loading driver alias: %s\n', driver_alias_file);
    T = readtable(driver_alias_file, 'Sheet', 'driverAlias', 'TextType', 'char');

    % Validate required columns
    required = {'DRV_TLA', 'TM_sorting_TLA'};
    for i = 1:numel(required)
        if ~ismember(required{i}, T.Properties.VariableNames)
            error('smp_sort_hol_to_teams: Column "%s" not found in driverAlias sheet.\n  Available: %s', ...
                required{i}, strjoin(T.Properties.VariableNames, ', '));
        end
    end

    % Build lookup: DRV_TLA -> TM_sorting_TLA  (uppercase for matching)
    drv_tlas     = upper(strtrim(T.DRV_TLA));
    tm_sort_tlas = strtrim(T.TM_sorting_TLA);

    % ------------------------------------------------------------------
    %  Find .ld files in hol_dir (flat, non-recursive)
    % ------------------------------------------------------------------
    ld_files = dir(fullfile(hol_dir, '*.ld'));
    if isempty(ld_files)
        fprintf('No .ld files found in: %s\n', hol_dir);
        return;
    end
    fprintf('Found %d .ld file(s) to sort.\n\n', numel(ld_files));

    % ------------------------------------------------------------------
    %  Process each file
    % ------------------------------------------------------------------
    n_ok      = 0;
    n_skip    = 0;
    n_unknown = 0;

    for i = 1:numel(ld_files)
        src_path = fullfile(hol_dir, ld_files(i).name);

        % ---- Parse DRV_TLA from filename — first token before '_' ----
        % Pattern: <DRV_TLA>_<year>_<session>.ld  e.g. MOS_2026_R15.ld
        [~, fname_no_ext] = fileparts(ld_files(i).name);
        tokens  = strsplit(fname_no_ext, '_');
        drv_tla = upper(strtrim(tokens{1}));

        % ---- Lookup TM_sorting_TLA ----
        alias_idx = find(strcmp(drv_tla, drv_tlas), 1);

        if isempty(alias_idx)
            fprintf('  [!] DRV_TLA "%s" not found in alias file — skipping: %s\n', ...
                drv_tla, ld_files(i).name);
            n_unknown = n_unknown + 1;
            continue;
        end

        tm_tla = tm_sort_tlas{alias_idx};
        if isempty(tm_tla)
            fprintf('  [!] TM_sorting_TLA is empty for DRV_TLA "%s" — skipping: %s\n', ...
                drv_tla, ld_files(i).name);
            n_unknown = n_unknown + 1;
            continue;
        end

        % ---- Build destination path ----
        dest_dir  = fullfile(hol_dir, tm_tla);
        dest_path = fullfile(dest_dir, ld_files(i).name);

        % ---- Skip if already exists ----
        if exist(dest_path, 'file') && ~overwrite
            if verbose
                fprintf('  [skip] %s  →  %s\\ (already exists)\n', ld_files(i).name, tm_tla);
            end
            n_skip = n_skip + 1;
            continue;
        end

        % ---- Create team folder if needed ----
        if ~exist(dest_dir, 'dir') && ~dry_run
            mkdir(dest_dir);
            fprintf('  [mkdir] %s\n', dest_dir);
        end

        % ---- Copy or move ----
        action_str = 'copy';
        if do_move, action_str = 'move'; end

        if verbose || dry_run
            fprintf('  [%s] %-30s  →  %s\\\n', action_str, ld_files(i).name, tm_tla);
        end

        if ~dry_run
            if do_move
                movefile(src_path, dest_path);
            else
                copyfile(src_path, dest_path);
            end
        end

        n_ok = n_ok + 1;
    end

    % ------------------------------------------------------------------
    %  Summary
    % ------------------------------------------------------------------
    fprintf('\n=== Sort complete ===\n');
    fprintf('  Sorted  : %d\n', n_ok);
    fprintf('  Skipped : %d  (already existed)\n', n_skip);
    fprintf('  Unknown : %d  (no alias match — check DRV_TLA column)\n', n_unknown);
    if dry_run
        fprintf('  [DRY RUN] No files were actually moved/copied.\n');
    end
    fprintf('\n');
end


% ======================================================================= %
function val = get_opt(s, f, default)
    if isfield(s, f) && ~isempty(s.(f)), val = s.(f);
    else,                                 val = default; end
end