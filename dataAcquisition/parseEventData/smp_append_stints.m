% function groups = smp_append_stints(file_list, driver_map, alias)
% % SMP_APPEND_STINTS  Group .ld files that belong to the same driver/car/session.
% %
% % Teams sometimes pull the car in mid-session to download data and then
% % send it out again. This creates multiple .ld files for what is effectively
% % one continuous session outing. This function detects those cases and
% % groups the files together so they can be concatenated before lap slicing.
% %
% % Grouping key (after alias resolution):
% %   resolved_driver + resolved_session + car_number
% %
% % Files within a group are sorted by log_date (filename timestamp) ascending,
% % so channels are concatenated in chronological order.
% %
% % Usage:
% %   groups = smp_append_stints(file_list, driver_map, alias)
% %
% % Inputs:
% %   file_list   - struct array from smp_scan_folders/smp_cache_diff, each with:
% %                   .path           full path to .ld file
% %                   .team_acronym   team code string
% %   driver_map  - struct from smp_driver_alias_load() — for driver name resolution
% %   alias       - struct from smp_alias_load()        — for session name resolution
% %
% % Output:
% %   groups  - struct array, one per unique driver/session/car combination:
% %     .key            string identifier for this group
% %     .driver         resolved driver name
% %     .car            car number string
% %     .session        resolved session name
% %     .team_acronym   team acronym
% %     .files          cell array of full .ld file paths (chronological order)
% %     .n_files        number of files in this group
% 
%     if isempty(file_list)
%         groups = struct('key',{},'driver',{},'car',{},'session',{},...
%                         'team_acronym',{},'files',{},'n_files',{});
%         return;
%     end
% 
%     fprintf('smp_append_stints: grouping %d file(s)...\n', numel(file_list));
% 
%     % ------------------------------------------------------------------
%     %  Read metadata for all files and resolve through aliases
%     % ------------------------------------------------------------------
%     n = numel(file_list);
%     meta_list = struct('path',     cell(n,1), ...
%                        'team',     cell(n,1), ...
%                        'driver',   cell(n,1), ...
%                        'car',      cell(n,1), ...
%                        'session',  cell(n,1), ...
%                        'log_date', cell(n,1), ...
%                        'key',      cell(n,1));
% 
%     for i = 1:n
%         fpath = file_list(i).path;
%         tacro = file_list(i).team_acronym;
% 
%         % Read file header
%         try
%             info = motec_ld_info(fpath);
%         catch ME
%             fprintf('  [WARN] Cannot read header: %s — %s\n', fpath, ME.message);
%             info = struct();
%         end
% 
%         raw_driver  = strtrim(char(string(safe_field(info, 'driver',  ''))));
%         raw_session = strtrim(char(string(safe_field(info, 'session', ''))))
%         raw_car     = strtrim(char(string(safe_field(info, 'car_number', ''))));
%         log_date    = strtrim(char(string(safe_field(info, 'log_date', '19700101'))));
% 
%         % Resolve driver through alias table
%         res_driver = resolve_driver(raw_driver, driver_map);
% 
%         % Resolve session through alias table
%         res_session = resolve_session(raw_session, alias);
% 
%         % Build group key
%         group_key = lower(sprintf('%s|%s|%s|%s', tacro, res_driver, res_session, raw_car));
%         group_key = regexprep(group_key, '\s+', '_');
% 
%         meta_list(i).path     = fpath;
%         meta_list(i).team     = tacro;
%         meta_list(i).driver   = res_driver;
%         meta_list(i).car      = raw_car;
%         meta_list(i).session  = res_session;
%         meta_list(i).log_date = log_date;
%         meta_list(i).key      = group_key;
%     end
% 
%     % ------------------------------------------------------------------
%     %  Group by key
%     % ------------------------------------------------------------------
%     all_keys = {meta_list.key};
%     unique_keys = unique(all_keys, 'stable');
% 
%     groups = struct('key',{},'driver',{},'car',{},'session',{},...
%                     'team_acronym',{},'files',{},'n_files',{});
% 
%     for g = 1:numel(unique_keys)
%         uk   = unique_keys{g};
%         mask = strcmp(all_keys, uk);
%         members = meta_list(mask);
% 
%         % Sort chronologically by log_date (filename timestamp)
%         dates = cell(numel(members), 1);
%         for si = 1:numel(members)
%             dates{si} = members(si).log_date;
%         end
%         [~, ord] = sort(dates);
%         members  = members(ord);
% 
%         groups(g).key          = uk;
%         groups(g).driver       = members(1).driver;
%         groups(g).car          = members(1).car;
%         groups(g).session      = members(1).session;
%         groups(g).team_acronym = members(1).team;
%         groups(g).files        = {members.path};
%         groups(g).n_files      = numel(members);
% 
%         if numel(members) >= 1
%             fprintf('  [MULTI-STINT] %s | %s | %s | %d files\n', ...
%                 members(1).team, members(1).driver, members(1).session, numel(members));
%             for f = 1:numel(members)
%                 [~, fname] = fileparts(members(f).path);
%                 fprintf('    %d: %s\n', f, fname);
%             end
%         end
%     end
% 
%     n_multi = sum([groups.n_files] > 1);
%     fprintf('smp_append_stints: %d group(s) — %d multi-stint.\n\n', ...
%         numel(groups), n_multi);
% end
% 
% 
% % ======================================================================= %
% %  ALIAS RESOLUTION HELPERS
% % ======================================================================= %
% function resolved = resolve_driver(raw_name, driver_map)
% % Resolve raw driver name to canonical name via driver alias map.
% % Falls back to the raw name if no match found.
% 
%     resolved = raw_name;
%     if isempty(driver_map) || ~isstruct(driver_map) || isempty(raw_name)
%         return;
%     end
% 
%     name_lower = lower(strtrim(raw_name));
%     keys = fieldnames(driver_map);
%     for k = 1:numel(keys)
%         entry = driver_map.(keys{k});
%         if isfield(entry, 'aliases') && any(strcmp(entry.aliases, name_lower))
%             % Use the canonical key as the resolved name (or entry.name if present)
%             if isfield(entry, 'name') && ~isempty(entry.name)
%                 resolved = entry.name;
%             else
%                 resolved = keys{k};
%             end
%             return;
%         end
%     end
% end
% 
% 
% function resolved = resolve_session(raw_session, alias)
% % Resolve raw session string to canonical name via session alias map.
% % Falls back to raw session string if no match found.
% 
%     resolved = raw_session;
%     if isempty(alias) || ~isstruct(alias) || isempty(raw_session)
%         return;
%     end
%     if ~isfield(alias, 'session') || ~isfield(alias.session, 'lookup')
%         return;
%     end
% 
%     lut = alias.session.lookup;
%     if lut.Count == 0, return; end
% 
%     key = lower(strtrim(raw_session));
%     if isKey(lut, key)
%         resolved = lut(key);   % canonical
%     end
% end
% 
% 
% % ======================================================================= %
% function val = safe_field(s, field, default)
%     if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
%         val = s.(field);
%     else
%         val = default;
%     end
% end


function groups = smp_append_stints(file_list, driver_map, alias, session_filter)
% SMP_APPEND_STINTS  Group .ld files that belong to the same driver/car/session.
%
% Teams sometimes pull the car in mid-session to download data and then
% send it out again. This creates multiple .ld files for what is effectively
% one continuous session outing. This function detects those cases and
% groups the files together so they can be concatenated before lap slicing.
%
% Grouping key (after alias resolution):
%   resolved_driver + resolved_session + car_number
%
% Files within a group are sorted by log_date (filename timestamp) ascending,
% so channels are concatenated in chronological order.
%
% Usage:
%   groups = smp_append_stints(file_list, driver_map, alias)
%
% Inputs:
%   file_list   - struct array from smp_scan_folders/smp_cache_diff, each with:
%                   .path           full path to .ld file
%                   .team_acronym   team code string
%   driver_map  - struct from smp_driver_alias_load() — for driver name resolution
%   alias       - struct from smp_alias_load()        — for session name resolution
%
% Output:
%   groups  - struct array, one per unique driver/session/car combination:
%     .key            string identifier for this group
%     .driver         resolved driver name
%     .car            car number string
%     .session        resolved session name
%     .team_acronym   team acronym
%     .files          cell array of full .ld file paths (chronological order)
%     .n_files        number of files in this group

    if isempty(file_list)
        groups = struct('key',{},'driver',{},'car',{},'session',{},...
                        'team_acronym',{},'files',{},'n_files',{});
        return;
    end

    % Normalise session_filter
    if nargin < 4 || isempty(session_filter)
        session_filter = {};
    end
    if ischar(session_filter) || isstring(session_filter)
        session_filter = {char(session_filter)};
    end
    filter_lower = lower(session_filter);
    use_filter   = ~isempty(filter_lower);

    fprintf('smp_append_stints: grouping %d file(s)...\n', numel(file_list));
    if use_filter
        fprintf('  Session filter active: [%s]\n', strjoin(session_filter, ', '));
    end

    % ------------------------------------------------------------------
    %  Read metadata for all files and resolve through aliases
    % ------------------------------------------------------------------
    n = numel(file_list);
    meta_list = struct('path',     cell(n,1), ...
                       'team',     cell(n,1), ...
                       'driver',   cell(n,1), ...
                       'car',      cell(n,1), ...
                       'session',  cell(n,1), ...
                       'log_date', cell(n,1), ...
                       'key',      cell(n,1));

    for i = 1:n
        fpath = file_list(i).path;
        tacro = file_list(i).team_acronym;

        % Read file header
        try
            info = motec_ld_info(fpath);
        catch ME
            fprintf('  [WARN] Cannot read header: %s — %s\n', fpath, ME.message);
            info = struct();
        end

        raw_driver  = strtrim(char(string(safe_field(info, 'driver',  ''))));
        raw_session = strtrim(char(string(safe_field(info, 'session', ''))))
        raw_car     = strtrim(char(string(safe_field(info, 'car_number', ''))));
        log_date    = strtrim(char(string(safe_field(info, 'log_date', '19700101'))));

        % Resolve driver through alias table
        res_driver = resolve_driver(raw_driver, driver_map);

        % Resolve session through alias table
        res_session = resolve_session(raw_session, alias);

        % Session filter — skip file before grouping if session not wanted
        if use_filter && ~any(strcmpi(res_session, filter_lower))
            fprintf('  [SKIP] %s — session "%s" not in filter\n', fpath, res_session);
            continue;
        end

        % Build group key
        group_key = lower(sprintf('%s|%s|%s|%s', tacro, res_driver, res_session, raw_car));
        group_key = regexprep(group_key, '\s+', '_');

        meta_list(i).path     = fpath;
        meta_list(i).team     = tacro;
        meta_list(i).driver   = res_driver;
        meta_list(i).car      = raw_car;
        meta_list(i).session  = res_session;
        meta_list(i).log_date = log_date;
        meta_list(i).key      = group_key;
    end

    % ------------------------------------------------------------------
    %  Group by key
    % ------------------------------------------------------------------
    % Remove empty rows from skipped files (pre-allocation leaves blanks)
    keep_mask = ~cellfun(@isempty, {meta_list.key});
    meta_list = meta_list(keep_mask);

    if isempty(meta_list)
        fprintf('smp_append_stints: no files matched session filter — returning empty.\n\n');
        groups = struct('key',{},'driver',{},'car',{},'session',{},...
                        'team_acronym',{},'files',{},'n_files',{});
        return;
    end

    all_keys = {meta_list.key};
    unique_keys = unique(all_keys, 'stable');

    groups = struct('key',{},'driver',{},'car',{},'session',{},...
                    'team_acronym',{},'files',{},'n_files',{});

    for g = 1:numel(unique_keys)
        uk   = unique_keys{g};
        mask = strcmp(all_keys, uk);
        members = meta_list(mask);

        % Sort chronologically by log_date (filename timestamp)
        dates = cell(numel(members), 1);
        for si = 1:numel(members)
            dates{si} = members(si).log_date;
        end
        [~, ord] = sort(dates);
        members  = members(ord);

        groups(g).key          = uk;
        groups(g).driver       = members(1).driver;
        groups(g).car          = members(1).car;
        groups(g).session      = members(1).session;
        groups(g).team_acronym = members(1).team;
        groups(g).files        = {members.path};
        groups(g).n_files      = numel(members);

        if numel(members) >= 1
            fprintf('  [MULTI-STINT] %s | %s | %s | %d files\n', ...
                members(1).team, members(1).driver, members(1).session, numel(members));
            for f = 1:numel(members)
                [~, fname] = fileparts(members(f).path);
                fprintf('    %d: %s\n', f, fname);
            end
        end
    end

    n_multi = sum([groups.n_files] > 1);
    fprintf('smp_append_stints: %d group(s) — %d multi-stint.\n\n', ...
        numel(groups), n_multi);
end


% ======================================================================= %
%  ALIAS RESOLUTION HELPERS
% ======================================================================= %
function resolved = resolve_driver(raw_name, driver_map)
% Resolve raw driver name to canonical name via driver alias map.
% Falls back to the raw name if no match found.

    resolved = raw_name;
    if isempty(driver_map) || ~isstruct(driver_map) || isempty(raw_name)
        return;
    end

    name_lower = lower(strtrim(raw_name));
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        if isfield(entry, 'aliases') && any(strcmp(entry.aliases, name_lower))
            % Use the canonical key as the resolved name (or entry.name if present)
            if isfield(entry, 'name') && ~isempty(entry.name)
                resolved = entry.name;
            else
                resolved = keys{k};
            end
            return;
        end
    end
end


function resolved = resolve_session(raw_session, alias)
% Resolve raw session string to canonical name via session alias map.
% Falls back to raw session string if no match found.

    resolved = raw_session;
    if isempty(alias) || ~isstruct(alias) || isempty(raw_session)
        return;
    end
    if ~isfield(alias, 'session') || ~isfield(alias.session, 'lookup')
        return;
    end

    lut = alias.session.lookup;
    if lut.Count == 0, return; end

    key = lower(strtrim(raw_session));
    if isKey(lut, key)
        resolved = lut(key);   % canonical
    end
end


% ======================================================================= %
function val = safe_field(s, field, default)
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end