function cache = smp_cache_empty()
% SMP_CACHE_EMPTY  Return a blank cache struct with correct schema.

    cache.manifest = table( ...
        strings(0,1), ...   Path
        zeros(0,1),   ...   TeamIndex
        strings(0,1), ...   TeamAcronym
        zeros(0,1),   ...   FileSize
        zeros(0,1),   ...   LastModifiedNum
        NaT(0,1),     ...   LastModified
        strings(0,1), ...   Driver
        strings(0,1), ...   CarNumber
        strings(0,1), ...   TeamName
        strings(0,1), ...   Vehicle
        strings(0,1), ...   Manufacturer
        strings(0,1), ...   EngineID
        strings(0,1), ...   Venue
        strings(0,1), ...   Session
        strings(0,1), ...   Run
        strings(0,1), ...   Date
        strings(0,1), ...   Time
        strings(0,1), ...   Year
        strings(0,1), ...   LogDate
        false(0,1),   ...   LoadOK
        false(0,1),   ...   Missing
        strings(0,1), ...   ErrorMsg
        NaT(0,1),     ...   CachedAt
        'VariableNames', { ...
            'Path','TeamIndex','TeamAcronym', ...
            'FileSize','LastModifiedNum','LastModified', ...
            'Driver','CarNumber','TeamName', ...
            'Vehicle','Manufacturer','EngineID', ...
            'Venue','Session','Run', ...
            'Date','Time','Year','LogDate', ...
            'LoadOK','Missing','ErrorMsg','CachedAt'});

    cache.channels = containers.Map('KeyType','char','ValueType','any');
    cache.info     = containers.Map('KeyType','char','ValueType','any');
    cache.stats    = struct();
    cache.traces   = struct();
end


% function cache = smp_cache_empty()
% % SMP_CACHE_EMPTY  Return a blank cache struct with correct schema.
% 
%     cache.manifest = table( ...
%         strings(0,1), ...   Path
%         zeros(0,1),   ...   TeamIndex
%         strings(0,1), ...   TeamAcronym
%         zeros(0,1),   ...   FileSize
%         zeros(0,1),   ...   LastModifiedNum
%         NaT(0,1),     ...   LastModified
%         strings(0,1), ...   Driver
%         strings(0,1), ...   CarNumber
%         strings(0,1), ...   TeamName
%         strings(0,1), ...   Vehicle
%         strings(0,1), ...   Manufacturer
%         strings(0,1), ...   EngineID
%         strings(0,1), ...   Venue
%         strings(0,1), ...   Session
%         strings(0,1), ...   Run
%         strings(0,1), ...   Date
%         strings(0,1), ...   Time
%         strings(0,1), ...   Year
%         strings(0,1), ...   LogDate
%         false(0,1),   ...   LoadOK
%         false(0,1),   ...   Missing
%         strings(0,1), ...   ErrorMsg
%         NaT(0,1),     ...   CachedAt
%         strings(0,1), ...   GroupKey
%         'VariableNames', { ...
%             'Path','TeamIndex','TeamAcronym', ...
%             'FileSize','LastModifiedNum','LastModified', ...
%             'Driver','CarNumber','TeamName', ...
%             'Vehicle','Manufacturer','EngineID', ...
%             'Venue','Session','Run', ...
%             'Date','Time','Year','LogDate', ...
%             'LoadOK','Missing','ErrorMsg','CachedAt','GroupKey'});
% 
%     cache.stats  = containers.Map('KeyType','char','ValueType','any');
%     cache.traces = containers.Map('KeyType','char','ValueType','any');
% end