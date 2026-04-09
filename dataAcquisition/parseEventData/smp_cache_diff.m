function [to_load, cache] = smp_cache_diff(cache, scan)
% SMP_CACHE_DIFF  Compare scanned .ld files against the cache manifest.
%
% Returns files that need loading (new or changed), and flags missing files.

    to_load = struct('path', {}, 'team_index', {}, 'team_acronym', {});
    n = 0;

    % Build fast path -> row lookup
    if height(cache.manifest) > 0
        path_map = containers.Map(cache.manifest.Path, ...
                                  num2cell(1:height(cache.manifest)));
    else
        path_map = containers.Map();
    end

    seen_paths = {};

    for t = 1:numel(scan)
        team = scan(t);
        for f = 1:numel(team.files)
            fpath = team.files{f};
            seen_paths{end+1} = fpath; %#ok

            d = dir(fpath);
            if isempty(d)
                n = n + 1;
                to_load(n).path         = fpath;
                to_load(n).team_index   = team.index;
                to_load(n).team_acronym = team.acronym;
                continue;
            end

            disk_size    = d.bytes;
            disk_modtime = d.datenum;

            if isKey(path_map, fpath)
                row            = path_map(fpath);
                cached_size    = cache.manifest.FileSize(row);
                cached_modtime = cache.manifest.LastModifiedNum(row);
                changed = (disk_size ~= cached_size) || ...
                          (abs(disk_modtime - cached_modtime) > 1/86400);

                if changed
                    fprintf('  [CHANGED] %s\n', fpath);
                    n = n + 1;
                    to_load(n).path         = fpath;
                    to_load(n).team_index   = team.index;
                    to_load(n).team_acronym = team.acronym;
                    cache = smp_cache_remove(cache, fpath);
                end
            else
                n = n + 1;
                to_load(n).path         = fpath;
                to_load(n).team_index   = team.index;
                to_load(n).team_acronym = team.acronym;
            end
        end
    end

    % Flag entries no longer on disk
    if height(cache.manifest) > 0
        for row = 1:height(cache.manifest)
            p = cache.manifest.Path{row};
            if ~ismember(p, seen_paths) && ~cache.manifest.Missing(row)
                cache.manifest.Missing(row) = true;
                fprintf('  [MISSING] %s\n', p);
            end
        end
    end

    fprintf('smp_cache_diff: %d new/changed files to load.\n', n);
end
