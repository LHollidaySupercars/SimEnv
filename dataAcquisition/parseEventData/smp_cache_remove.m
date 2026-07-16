function cache = smp_cache_remove(cache, fpath)
% SMP_CACHE_REMOVE  Remove a single entry from the cache by file path.

    mask = ~strcmp(cache.manifest.Path, fpath);
    cache.manifest = cache.manifest(mask, :);
    if isKey(cache.channels, fpath), remove(cache.channels, fpath); end
    if isKey(cache.info,     fpath), remove(cache.info,     fpath); end
end
