function ld_paths = recursive_find_ld(root_dir)
% RECURSIVE_FIND_LD  Recursively find all .ld files under root_dir.
    ld_paths = {};
    if ~isfolder(root_dir), return; end
    stack = {root_dir};
    while ~isempty(stack)
        cur = stack{end}; stack(end) = [];
        d = dir(fullfile(cur, '*.ld'));
        for k = 1:numel(d)
            if ~startsWith(d(k).name, '._')
                ld_paths{end+1} = fullfile(cur, d(k).name); %#ok<AGROW>
            end
        end
        sub = dir(cur);
        for k = 1:numel(sub)
            if sub(k).isdir && sub(k).name(1) ~= '.'
                stack{end+1} = fullfile(cur, sub(k).name); %#ok<AGROW>
            end
        end
    end
end

