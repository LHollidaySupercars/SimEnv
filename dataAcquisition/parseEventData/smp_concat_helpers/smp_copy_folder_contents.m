function smp_copy_folder_contents(src_dir, dest_dir, opts)
% SMP_COPY_FOLDER_CONTENTS  Copy all files from src_dir into dest_dir.
%
% Usage:
%   smp_copy_folder_contents(src_dir, dest_dir)
%   smp_copy_folder_contents(src_dir, dest_dir, opts)
%
% opts.pattern   - file glob to match (default '*.ld')
% opts.recursive - true = include subfolders (default false)
% opts.overwrite - true = overwrite existing files in dest (default false)
% opts.move      - true = move instead of copy (default false)
% opts.verbose   - true = print each action (default true)

if nargin < 3, opts = struct(); end
pattern   = get_opt(opts, 'pattern',   '*.ld');
recursive = get_opt(opts, 'recursive', true);
overwrite = get_opt(opts, 'overwrite', false);
do_move   = get_opt(opts, 'move',      false);
verbose   = get_opt(opts, 'verbose',   true);

if ~exist(dest_dir, 'dir')
    mkdir(dest_dir);
end

if recursive
    files = dir(fullfile(src_dir, '**', pattern));
else
    files = dir(fullfile(src_dir, pattern));
end

if isempty(files)
    fprintf('No files matching "%s" found in: %s\n', pattern, src_dir);
    return;
end

n_ok = 0; n_skip = 0;
for i = 1:numel(files)
    src_path  = fullfile(files(i).folder, files(i).name);
    dest_path = fullfile(dest_dir, files(i).name);

    if exist(dest_path, 'file') && ~overwrite
        if verbose
            fprintf('  [skip] %s (already exists)\n', files(i).name);
        end
        n_skip = n_skip + 1;
        continue;
    end

    if do_move
        movefile(src_path, dest_path);
        action = 'move';
    else
        copyfile(src_path, dest_path);
        action = 'copy';
    end

    if verbose
        fprintf('  [%s] %s\n', action, files(i).name);
    end
    n_ok = n_ok + 1;
end

fprintf('\nDone: %d copied/moved, %d skipped.\n', n_ok, n_skip);
end

function val = get_opt(s, f, default)
if isfield(s, f) && ~isempty(s.(f)), val = s.(f);
else,                                 val = default; end
end