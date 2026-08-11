function relpath = strip_common_prefix(filepath, root_folder)
% STRIP_COMMON_PREFIX  Convert absolute path to relative path.
% If filepath starts with root_folder, strip it and return remainder.
% Otherwise return filepath unchanged.
    if startsWith(filepath, root_folder, 'IgnoreCase', true)
        relpath = filepath(length(root_folder)+1:end);
        if startsWith(relpath, filesep)
            relpath = relpath(2:end);
        end
    else
        relpath = filepath;
    end
end

