function result = smp_scan_folders(top_level_dir)
% SMP_SCAN_FOLDERS  Recursively scan the SMP team data directory structure.
%
% Searches through each team subfolder (named NN_XXX) for .ld files.
% Handles both flat and nested folder structures.
%
% Usage:
%   result = smp_scan_folders('C:\LOCAL_DATA\01 - SMP\_Team Data')
%
% Output:
%   result  - struct array, one entry per team, with fields:
%     .index     - numeric team index, e.g. 1 for "01_..."
%     .acronym   - three-letter team code, e.g. "T8R"
%     .folder    - absolute path to team subfolder
%     .files     - cell array of full .ld file paths found recursively

    if ~isfolder(top_level_dir)
        error('smp_scan_folders: Directory not found: %s', top_level_dir);
    end

    % Find all immediate subfolders matching NN_XXX pattern
    d = dir(top_level_dir);
    d = d([d.isdir]);
    d = d(~ismember({d.name}, {'.', '..'}));

    result = struct('index', {}, 'acronym', {}, 'folder', {}, 'files', {});
    n = 0;

    for i = 1:numel(d)
        name = d(i).name;

        % Match naming convention: NN_XXX  (e.g. "01_T8R", "02_WAU")
        tok = regexp(name, '^(\d+)_([A-Za-z0-9]+)', 'tokens');
        if isempty(tok)
            fprintf('  [SKIP] "%s" — does not match NN_XXX pattern\n', name);
            continue;
        end

        team_idx     = str2double(tok{1}{1});
        team_acronym = upper(tok{1}{2});
        team_folder  = fullfile(top_level_dir, name);

        % Recursively find all .ld files under this team folder
        ld_files = recursive_find_ld(team_folder);

        n = n + 1;
        result(n).index   = team_idx;
        result(n).acronym = team_acronym;
        result(n).folder  = team_folder;
        result(n).files   = ld_files;

        fprintf('  [%02d] %-6s  %s  (%d .ld files found)\n', ...
            team_idx, team_acronym, team_folder, numel(ld_files));
    end

    fprintf('\nsmp_scan_folders: Found %d teams.\n', n);
end


% ======================================================================= %
function files = recursive_find_ld(folder)
% Recursively find all .ld files under a given folder.
    files = {};

    % Files in this folder
    d_files = dir(fullfile(folder, '*.ld'));
    for i = 1:numel(d_files)
        files{end+1} = fullfile(folder, d_files(i).name); %#ok
    end

    % Recurse into subfolders
    d_dirs = dir(folder);
    d_dirs = d_dirs([d_dirs.isdir]);
    d_dirs = d_dirs(~ismember({d_dirs.name}, {'.', '..'}));

    for i = 1:numel(d_dirs)
        sub_files = recursive_find_ld(fullfile(folder, d_dirs(i).name));
        files = [files, sub_files]; %#ok
    end
end
