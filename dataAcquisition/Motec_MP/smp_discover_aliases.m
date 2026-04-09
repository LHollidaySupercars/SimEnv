% function result = smp_discover_aliases(data_dir, opts)
% % SMP_DISCOVER_ALIASES  Scan all .ld files and collect unique raw driver,
% %                       venue, and session strings without loading channel data.
% %
% % This is RAM-safe: only the file header (~1756 bytes) is read per file
% % via motec_ld_info. No channel data is loaded.
% %
% % Usage:
% %   result = smp_discover_aliases('E:\02_AGP\_Team Data')
% %   result = smp_discover_aliases(data_dir, opts)
% %
% % Options (opts struct):
% %   .verbose          logical    print progress              (default: true)
% %   .team_filter      cell       only these acronyms         (default: {} = all)
% %   .date_from        datetime/datenum/string
% %                                ignore files modified before this date
% %                                e.g. datetime(2026,3,5) or '05-Mar-2026'
% %                                (default: [] = all files)
% %   .alias_file       char       path to driverAlias.xlsx — when supplied,
% %                                a cross-reference is run and printed.
% %                                (default: '' = no xref)
% %   .event_alias_file char       path to eventAlias.xlsx for venue + session xref
% %                                (default: '' = no venue/session xref)
% %   .xref_export      char       path to write xref results as .xlsx
% %                                (default: '' = no export)
% %
% % Output (result struct):
% %   .drivers          cell of unique raw driver strings found
% %   .venues           cell of unique raw venue strings found
% %   .sessions         cell of unique raw session strings found
% %   .manifest         table  one row per file with Driver, Venue, Session,
% %                            TeamAcronym, Path, Date, CarNumber, Vehicle
% %   .xref             cross-reference struct (only present when alias_file set)
% %     .drivers.matched      cell {raw, canonical, match_method} per matched name
% %     .drivers.unmatched    cell of raw strings with no alias match
% %     .drivers.n_matched    count
% %     .drivers.n_unmatched  count
% %     .venues.matched       cell {raw, canonical, match_method} per matched name
% %     .venues.unmatched     cell of raw strings with no alias match
% %     .venues.n_matched     count
% %     .venues.n_unmatched   count
% %     .sessions.matched     cell {raw, canonical, match_method} per matched name
% %     .sessions.unmatched   cell of raw strings with no alias match
% %     .sessions.n_matched   count
% %     .sessions.n_unmatched count
% %     .ok                   true if ALL drivers AND sessions matched
% %
% % Example:
% %   clear opts
% %   opts.date_from        = datetime(2026, 3, 5);
% %   opts.alias_file       = 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
% %   opts.event_alias_file = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
% %   result = smp_discover_aliases('E:\02_AGP\_Team Data', opts);
% %   result.drivers            % paste into driverAlias.xlsx
% %   result.sessions           % paste into eventAlias.xlsx SESSION sheet
% %   result.xref.ok            % true only when drivers AND sessions fully matched
% 
%     % ------------------------------------------------------------------ %
%     %  Defaults
%     % ------------------------------------------------------------------ %
%     if nargin < 2 || isempty(opts), opts = struct(); end
%     verbose          = get_opt(opts, 'verbose',          true);
%     team_filter      = get_opt(opts, 'team_filter',      {});
%     date_from        = get_opt(opts, 'date_from',        []);
%     alias_file       = get_opt(opts, 'alias_file',       '');
%     event_alias_file = get_opt(opts, 'event_alias_file', '');
%     xref_export      = get_opt(opts, 'xref_export',      '');
% 
%     % ------------------------------------------------------------------ %
%     %  Scan folders (unchanged smp_scan_folders — no extra args)
%     % ------------------------------------------------------------------ %
%     if verbose
%         fprintf('\n=== smp_discover_aliases ===\n');
%         fprintf('Scanning: %s\n', data_dir);
%         if ~isempty(date_from)
%             fprintf('DateFrom filter: %s\n', datestr(to_datenum(date_from)));
%         end
%         fprintf('\n');
%     end
% 
%     teams = smp_scan_folders(data_dir);
% 
%     % Apply team filter
%     if ~isempty(team_filter)
%         keep = false(1, numel(teams));
%         for i = 1:numel(teams)
%             keep(i) = any(strcmpi(teams(i).acronym, team_filter));
%         end
%         teams = teams(keep);
%     end
% 
%     % Apply date filter post-scan (keeps smp_scan_folders signature unchanged)
%     if ~isempty(date_from)
%         date_from_dn = to_datenum(date_from);
%         n_before = sum(cellfun(@numel, {teams.files}));
%         for i = 1:numel(teams)
%             files = teams(i).files;
%             keep_files = false(1, numel(files));
%             for j = 1:numel(files)
%                 d = dir(files{j});
%                 keep_files(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
%             end
%             teams(i).files = files(keep_files);
%         end
%         n_after = sum(cellfun(@numel, {teams.files}));
%         if verbose
%             fprintf('DateFrom filter: %d -> %d files retained.\n\n', n_before, n_after);
%         end
%     end
% 
%     % Count total files
%     total_files = sum(cellfun(@numel, {teams.files}));
%     if verbose
%         fprintf('Teams to scan: %d  |  Total .ld files: %d\n\n', ...
%             numel(teams), total_files);
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  Pre-allocate manifest rows
%     % ------------------------------------------------------------------ %
%     paths       = cell(total_files, 1);
%     team_names  = cell(total_files, 1);
%     drivers     = cell(total_files, 1);
%     venues      = cell(total_files, 1);
%     sessions    = cell(total_files, 1);
%     car_numbers = cell(total_files, 1);
%     vehicles    = cell(total_files, 1);
%     dates       = cell(total_files, 1);
%     ok_flags    = false(total_files, 1);
%     err_msgs    = cell(total_files, 1);
% 
%     row        = 0;
%     file_count = 0;
% 
%     for t = 1:numel(teams)
%         tm    = teams(t);
%         files = tm.files;
% 
%         if verbose
%             fprintf('[%s]  %d files\n', tm.acronym, numel(files));
%         end
% 
%         for f = 1:numel(files)
%             fpath = files{f};
%             file_count = file_count + 1;
%             row = row + 1;
% 
%             try
%                 info = motec_ld_info(fpath);
%                 paths{row}       = fpath;
%                 team_names{row}  = tm.acronym;
%                 drivers{row}     = info.driver;
%                 venues{row}      = info.venue;
%                 sessions{row}    = info.session;
%                 car_numbers{row} = info.car_number;
%                 vehicles{row}    = info.vehicle;
%                 dates{row}       = info.date;
%                 ok_flags(row)    = true;
%                 err_msgs{row}    = '';
% 
%                 if verbose
%                     fprintf('  [%4d/%4d] %-20s  drv=%-25s  venue=%s\n', ...
%                         file_count, total_files, ...
%                         truncate(tm.acronym, 20), ...
%                         truncate(info.driver, 25), ...
%                         info.venue);
%                 end
% 
%             catch ME
%                 paths{row}       = fpath;
%                 team_names{row}  = tm.acronym;
%                 drivers{row}     = '';
%                 venues{row}      = '';
%                 sessions{row}    = '';
%                 car_numbers{row} = '';
%                 vehicles{row}    = '';
%                 dates{row}       = '';
%                 ok_flags(row)    = false;
%                 err_msgs{row}    = ME.message;
% 
%                 if verbose
%                     fprintf('  [%4d/%4d] ERROR: %s — %s\n', ...
%                         file_count, total_files, fpath, ME.message);
%                 end
%             end
%         end
%     end
% 
%     % Trim to actual rows used
%     paths       = paths(1:row);
%     team_names  = team_names(1:row);
%     drivers     = drivers(1:row);
%     venues      = venues(1:row);
%     sessions    = sessions(1:row);
%     car_numbers = car_numbers(1:row);
%     vehicles    = vehicles(1:row);
%     dates       = dates(1:row);
%     ok_flags    = ok_flags(1:row);
%     err_msgs    = err_msgs(1:row);
% 
%     % ------------------------------------------------------------------ %
%     %  Build manifest table
%     % ------------------------------------------------------------------ %
%     result.manifest = table( ...
%         paths, team_names, drivers, venues, sessions, ...
%         car_numbers, vehicles, dates, ok_flags, err_msgs, ...
%         'VariableNames', { ...
%             'Path','TeamAcronym','Driver','Venue','Session', ...
%             'CarNumber','Vehicle','Date','LoadOK','ErrorMsg'});
% 
%     % ------------------------------------------------------------------ %
%     %  Unique aliases
%     % ------------------------------------------------------------------ %
%     raw_drivers  = strtrim(drivers(ok_flags));
%     raw_venues   = strtrim(venues(ok_flags));
%     raw_sessions = strtrim(sessions(ok_flags));
% 
%     result.drivers  = sort(unique(raw_drivers(~cellfun(@isempty, raw_drivers))));
%     result.venues   = sort(unique(raw_venues(~cellfun(@isempty, raw_venues))));
%     result.sessions = sort(unique(raw_sessions(~cellfun(@isempty, raw_sessions))));
% 
%     % ------------------------------------------------------------------ %
%     %  Summary
%     % ------------------------------------------------------------------ %
%     if verbose
%         fprintf('\n--- Results ---\n');
%         fprintf('Files scanned : %d\n', row);
%         fprintf('Files OK      : %d\n', sum(ok_flags));
%         fprintf('Files failed  : %d\n', sum(~ok_flags));
% 
%         fprintf('\nUnique DRIVERS (%d):\n', numel(result.drivers));
%         for i = 1:numel(result.drivers)
%             fprintf('  "%s"\n', result.drivers{i});
%         end
% 
%         fprintf('\nUnique VENUES (%d):\n', numel(result.venues));
%         for i = 1:numel(result.venues)
%             fprintf('  "%s"\n', result.venues{i});
%         end
% 
%         fprintf('\nUnique SESSIONS (%d):\n', numel(result.sessions));
%         for i = 1:numel(result.sessions)
%             fprintf('  "%s"\n', result.sessions{i});
%         end
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  Alias cross-reference — inlined, no external smp_alias_xref needed
%     % ------------------------------------------------------------------ %
%     if ~isempty(alias_file)
%         if verbose
%             fprintf('\n--- Running alias cross-reference ---\n');
%         end
% 
%         driver_map = smp_driver_alias_load(alias_file);
% 
%         % Build driver lookup: lowercase alias -> canonical name
%         drv_lut    = containers.Map('KeyType','char','ValueType','char');
%         drv_fields = fieldnames(driver_map);
%         for i = 1:numel(drv_fields)
%             entry = driver_map.(drv_fields{i});
%             if ~isstruct(entry) || ~isfield(entry,'canonical'), continue; end
%             canonical   = entry.canonical;
%             all_aliases = {};
%             if isfield(entry,'aliases'), all_aliases = entry.aliases; end
%             all_aliases{end+1} = lower(canonical);
%             if isfield(entry,'tla') && ~isempty(entry.tla)
%                 all_aliases{end+1} = lower(entry.tla);
%             end
%             all_aliases = unique(all_aliases);
%             for j = 1:numel(all_aliases)
%                 k = strtrim(all_aliases{j});
%                 if ~isempty(k) && ~isKey(drv_lut, k)
%                     drv_lut(k) = canonical;
%                 end
%             end
%         end
% 
%         % Build venue + session lookups from eventAlias if supplied
%         ven_lut = containers.Map('KeyType','char','ValueType','char');
%         ses_lut = containers.Map('KeyType','char','ValueType','char');
%         if ~isempty(event_alias_file) && exist(event_alias_file,'file')
%             event_alias = smp_alias_load(event_alias_file);
%             if isfield(event_alias,'venue')
%                 src = event_alias.venue.lookup;
%                 src_keys = keys(src);
%                 for k = 1:numel(src_keys)
%                     ven_lut(src_keys{k}) = src(src_keys{k});
%                 end
%             end
%             if isfield(event_alias,'session')
%                 src = event_alias.session.lookup;
%                 src_keys = keys(src);
%                 for k = 1:numel(src_keys)
%                     ses_lut(src_keys{k}) = src(src_keys{k});
%                 end
%             end
%         end
% 
%         % Cross-reference
%         [drv_matched, drv_unmatched] = xref_names(result.drivers,  drv_lut);
%         [ven_matched, ven_unmatched] = xref_names(result.venues,   ven_lut);
%         [ses_matched, ses_unmatched] = xref_names(result.sessions, ses_lut);
% 
%         % Store
%         xref.drivers.matched      = drv_matched;
%         xref.drivers.unmatched    = drv_unmatched;
%         xref.drivers.n_matched    = numel(drv_matched);
%         xref.drivers.n_unmatched  = numel(drv_unmatched);
%         xref.venues.matched       = ven_matched;
%         xref.venues.unmatched     = ven_unmatched;
%         xref.venues.n_matched     = numel(ven_matched);
%         xref.venues.n_unmatched   = numel(ven_unmatched);
%         xref.sessions.matched     = ses_matched;
%         xref.sessions.unmatched   = ses_unmatched;
%         xref.sessions.n_matched   = numel(ses_matched);
%         xref.sessions.n_unmatched = numel(ses_unmatched);
%         xref.ok = (xref.drivers.n_unmatched == 0) && (xref.sessions.n_unmatched == 0);
%         result.xref = xref;
% 
%         % Print
%         if verbose
%             print_xref('DRIVERS',  drv_matched, drv_unmatched, 'driverAlias.xlsx');
%             if ~isempty(result.venues)
%                 print_xref('VENUES', ven_matched, ven_unmatched, 'eventAlias.xlsx  [VENUE sheet]');
%             end
%             print_xref('SESSIONS', ses_matched, ses_unmatched, 'eventAlias.xlsx  [SESSION sheet]');
%             print_xref_summary(xref);
%         end
% 
%         % Optional Excel export
%         if ~isempty(xref_export)
%             write_xref_excel(xref, xref_export);
%             fprintf('  Xref saved: %s\n', xref_export);
%         end
%     end
% 
% end
% 
% 
% % ======================================================================= %
% %  LOCAL HELPERS
% % ======================================================================= %
% 
% function val = get_opt(s, field, default)
%     if isfield(s, field) && ~isempty(s.(field))
%         val = s.(field);
%     else
%         val = default;
%     end
% end
% 
% function s = truncate(s, n)
%     if numel(s) > n, s = [s(1:n-2) '..']; end
% end
% 
% function dn = to_datenum(d)
%     if isnumeric(d)
%         dn = d;
%     elseif isdatetime(d)
%         dn = datenum(d);
%     else
%         dn = datenum(char(d));
%     end
% end
% 
% function [matched, unmatched] = xref_names(raw_names, lut)
% % Match raw name strings against a containers.Map lookup.
% % Three-pass strategy: exact -> partial -> reverse-partial.
%     matched   = {};
%     unmatched = {};
%     if lut.Count == 0
%         unmatched = raw_names;
%         return;
%     end
%     all_keys = keys(lut);
%     for i = 1:numel(raw_names)
%         raw       = raw_names{i};
%         raw_lower = lower(strtrim(raw));
%         if isempty(raw_lower), continue; end
%         found = false;
% 
%         % 1. Exact lowercase match
%         if isKey(lut, raw_lower)
%             matched{end+1} = {raw, lut(raw_lower), 'exact'};  %#ok
%             found = true;
%         end
% 
%         % 2. Alias key is a substring of raw name
%         if ~found
%             for k = 1:numel(all_keys)
%                 if contains(raw_lower, all_keys{k})
%                     matched{end+1} = {raw, lut(all_keys{k}), ...
%                         sprintf('partial ("%s")', all_keys{k})};  %#ok
%                     found = true;
%                     break;
%                 end
%             end
%         end
% 
%         % 3. Raw name is a substring of an alias key
%         if ~found
%             for k = 1:numel(all_keys)
%                 if contains(all_keys{k}, raw_lower)
%                     matched{end+1} = {raw, lut(all_keys{k}), ...
%                         sprintf('reverse-partial ("%s")', all_keys{k})};  %#ok
%                     found = true;
%                     break;
%                 end
%             end
%         end
% 
%         if ~found
%             unmatched{end+1} = raw;  %#ok
%         end
%     end
% end
% 
% function print_xref(label, matched, unmatched, alias_file_hint)
%     if nargin < 4, alias_file_hint = 'alias file'; end
%     n_total = numel(matched) + numel(unmatched);
%     fprintf('\n--- %s (%d found, %d matched, %d unmatched) ---\n', ...
%         label, n_total, numel(matched), numel(unmatched));
%     if ~isempty(matched)
%         fprintf('  Matched:\n');
%         for i = 1:numel(matched)
%             r = matched{i};
%             fprintf('    [OK] %-30s  ->  %-25s  (%s)\n', r{1}, r{2}, r{3});
%         end
%     end
%     if ~isempty(unmatched)
%         fprintf('  *** UNMATCHED — add to %s ***\n', alias_file_hint);
%         for i = 1:numel(unmatched)
%             fprintf('    [!!] %s\n', unmatched{i});
%         end
%     end
% end
% 
% function print_xref_summary(xref)
%     sep = repmat('-', 1, 40);
%     fprintf('\n%s\n', sep);
% 
%     % Drivers
%     if xref.drivers.n_unmatched == 0
%         fprintf('  DRIVERS  : ALL MATCHED\n');
%     else
%         fprintf('  DRIVERS  : %d UNMATCHED\n', xref.drivers.n_unmatched);
%         for i = 1:numel(xref.drivers.unmatched)
%             fprintf('    [!!] %s\n', xref.drivers.unmatched{i});
%         end
%     end
% 
%     % Sessions
%     if xref.sessions.n_unmatched == 0
%         fprintf('  SESSIONS : ALL MATCHED\n');
%     else
%         fprintf('  SESSIONS : %d UNMATCHED\n', xref.sessions.n_unmatched);
%         for i = 1:numel(xref.sessions.unmatched)
%             fprintf('    [!!] %s\n', xref.sessions.unmatched{i});
%         end
%     end
% 
%     fprintf('%s\n', sep);
%     if xref.ok
%         fprintf('  STATUS: ALL NAMES MATCHED  [xref.ok = true]\n');
%     else
%         fprintf('  STATUS: UNRESOLVED NAMES FOUND  [xref.ok = false]\n');
%         fprintf('  Fix the alias files above, then re-run.\n');
%     end
%     fprintf('%s\n\n', sep);
% end
% 
% function write_xref_excel(xref, filepath)
%     write_xref_sheet(xref.drivers,  filepath, 'Drivers',  'driverAlias.xlsx');
%     write_xref_sheet(xref.venues,   filepath, 'Venues',   'eventAlias.xlsx [VENUE]');
%     write_xref_sheet(xref.sessions, filepath, 'Sessions', 'eventAlias.xlsx [SESSION]');
% end
% 
% function write_xref_sheet(section, filepath, sheet_name, hint)
%     raw = {};  canonical = {};  status = {};  via = {};
%     for i = 1:numel(section.matched)
%         r = section.matched{i};
%         raw{end+1}       = r{1};       %#ok
%         canonical{end+1} = r{2};       %#ok
%         status{end+1}    = 'MATCHED';  %#ok
%         via{end+1}       = r{3};       %#ok
%     end
%     for i = 1:numel(section.unmatched)
%         raw{end+1}       = section.unmatched{i};                        %#ok
%         canonical{end+1} = '';                                          %#ok
%         status{end+1}    = ['UNMATCHED — ADD TO ' upper(hint)];        %#ok
%         via{end+1}       = '';                                          %#ok
%     end
%     if isempty(raw), return; end
%     T = table(raw(:), canonical(:), status(:), via(:), ...
%         'VariableNames', {'Raw_Name_From_File','Matched_Canonical','Status','Match_Method'});
%     writetable(T, filepath, 'Sheet', sheet_name);
% end

function result = smp_discover_aliases(data_dir, opts)
% SMP_DISCOVER_ALIASES  Scan all .ld files and collect unique raw driver,
%                       venue, and session strings without loading channel data.
%
% This is RAM-safe: only the file header (~1756 bytes) is read per file
% via motec_ld_info. No channel data is loaded.
%
% Usage:
%   result = smp_discover_aliases('E:\02_AGP\_Team Data')
%   result = smp_discover_aliases(data_dir, opts)
%
% Options (opts struct):
%   .verbose          logical    print progress              (default: true)
%   .team_filter      cell       only these acronyms         (default: {} = all)
%   .date_from        datetime/datenum/string
%                                ignore files modified before this date
%                                e.g. datetime(2026,3,5) or '05-Mar-2026'
%                                (default: [] = all files)
%   .alias_file       char       path to driverAlias.xlsx — when supplied,
%                                a cross-reference is run and printed.
%                                (default: '' = no xref)
%   .event_alias_file char       path to eventAlias.xlsx for venue + session xref
%                                (default: '' = no venue/session xref)
%   .xref_export      char       path to write xref results as .xlsx
%                                (default: '' = no export)
%
% Output (result struct):
%   .drivers          cell of unique raw driver strings found
%   .venues           cell of unique raw venue strings found
%   .sessions         cell of unique raw session strings found
%   .manifest         table  one row per file with Driver, Venue, Session,
%                            TeamAcronym, Path, Date, CarNumber, Vehicle
%   .xref             cross-reference struct (only present when alias_file set)
%     .drivers.matched      cell {raw, canonical, match_method} per matched name
%     .drivers.unmatched    cell of raw strings with no alias match
%     .drivers.n_matched    count
%     .drivers.n_unmatched  count
%     .venues.matched       cell {raw, canonical, match_method} per matched name
%     .venues.unmatched     cell of raw strings with no alias match
%     .venues.n_matched     count
%     .venues.n_unmatched   count
%     .sessions.matched     cell {raw, canonical, match_method} per matched name
%     .sessions.unmatched   cell of raw strings with no alias match
%     .sessions.n_matched   count
%     .sessions.n_unmatched count
%     .ok                   true if ALL drivers AND sessions matched
%
% Example:
%   clear opts
%   opts.date_from        = datetime(2026, 3, 5);
%   opts.alias_file       = 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
%   opts.event_alias_file = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
%   result = smp_discover_aliases('E:\02_AGP\_Team Data', opts);
%   result.drivers            % paste into driverAlias.xlsx
%   result.sessions           % paste into eventAlias.xlsx SESSION sheet
%   result.xref.ok            % true only when drivers AND sessions fully matched

    % ------------------------------------------------------------------ %
    %  Defaults
    % ------------------------------------------------------------------ %
    if nargin < 2 || isempty(opts), opts = struct(); end
    verbose          = get_opt(opts, 'verbose',          true);
    team_filter      = get_opt(opts, 'team_filter',      {});
    date_from        = get_opt(opts, 'date_from',        []);
    alias_file       = get_opt(opts, 'alias_file',       '');
    event_alias_file = get_opt(opts, 'event_alias_file', '');
    xref_export      = get_opt(opts, 'xref_export',      '');

    % ------------------------------------------------------------------ %
    %  Scan folders (unchanged smp_scan_folders — no extra args)
    % ------------------------------------------------------------------ %
    if verbose
        fprintf('\n=== smp_discover_aliases ===\n');
        fprintf('Scanning: %s\n', data_dir);
        if ~isempty(date_from)
            fprintf('DateFrom filter: %s\n', datestr(to_datenum(date_from)));
        end
        fprintf('\n');
    end

    teams = smp_scan_folders(data_dir);

    % Apply team filter
    if ~isempty(team_filter)
        keep = false(1, numel(teams));
        for i = 1:numel(teams)
            keep(i) = any(strcmpi(teams(i).acronym, team_filter));
        end
        teams = teams(keep);
    end

    % Apply date filter post-scan (keeps smp_scan_folders signature unchanged)
    if ~isempty(date_from)
        date_from_dn = to_datenum(date_from);
        n_before = sum(cellfun(@numel, {teams.files}));
        for i = 1:numel(teams)
            files = teams(i).files;
            keep_files = false(1, numel(files));
            for j = 1:numel(files)
                d = dir(files{j});
                keep_files(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
            end
            teams(i).files = files(keep_files);
        end
        n_after = sum(cellfun(@numel, {teams.files}));
        if verbose
            fprintf('DateFrom filter: %d -> %d files retained.\n\n', n_before, n_after);
        end
    end

    % Count total files
    total_files = sum(cellfun(@numel, {teams.files}));
    if verbose
        fprintf('Teams to scan: %d  |  Total .ld files: %d\n\n', ...
            numel(teams), total_files);
    end

    % ------------------------------------------------------------------ %
    %  Pre-allocate manifest rows
    % ------------------------------------------------------------------ %
    paths       = cell(total_files, 1);
    team_names  = cell(total_files, 1);
    drivers     = cell(total_files, 1);
    venues      = cell(total_files, 1);
    sessions    = cell(total_files, 1);
    car_numbers = cell(total_files, 1);
    vehicles    = cell(total_files, 1);
    dates       = cell(total_files, 1);
    ok_flags    = false(total_files, 1);
    err_msgs    = cell(total_files, 1);

    row        = 0;
    file_count = 0;

    for t = 1:numel(teams)
        tm    = teams(t);
        files = tm.files;

        if verbose
            fprintf('[%s]  %d files\n', tm.acronym, numel(files));
        end

        for f = 1:numel(files)
            fpath = files{f};
            file_count = file_count + 1;
            row = row + 1;

            try
                info = motec_ld_info(fpath);
                paths{row}       = fpath;
                team_names{row}  = tm.acronym;
                drivers{row}     = info.driver;
                venues{row}      = info.venue;
                sessions{row}    = info.session;
                car_numbers{row} = info.car_number;
                vehicles{row}    = info.vehicle;
                dates{row}       = info.date;
                ok_flags(row)    = true;
                err_msgs{row}    = '';

                if verbose
                    fprintf('  [%4d/%4d] %-20s  drv=%-25s  venue=%s\n', ...
                        file_count, total_files, ...
                        truncate(tm.acronym, 20), ...
                        truncate(info.driver, 25), ...
                        info.venue);
                end

            catch ME
                paths{row}       = fpath;
                team_names{row}  = tm.acronym;
                drivers{row}     = '';
                venues{row}      = '';
                sessions{row}    = '';
                car_numbers{row} = '';
                vehicles{row}    = '';
                dates{row}       = '';
                ok_flags(row)    = false;
                err_msgs{row}    = ME.message;

                if verbose
                    fprintf('  [%4d/%4d] ERROR: %s — %s\n', ...
                        file_count, total_files, fpath, ME.message);
                end
            end
        end
    end

    % Trim to actual rows used
    paths       = paths(1:row);
    team_names  = team_names(1:row);
    drivers     = drivers(1:row);
    venues      = venues(1:row);
    sessions    = sessions(1:row);
    car_numbers = car_numbers(1:row);
    vehicles    = vehicles(1:row);
    dates       = dates(1:row);
    ok_flags    = ok_flags(1:row);
    err_msgs    = err_msgs(1:row);

    % ------------------------------------------------------------------ %
    %  Build manifest table
    % ------------------------------------------------------------------ %
    result.manifest = table( ...
        paths, team_names, drivers, venues, sessions, ...
        car_numbers, vehicles, dates, ok_flags, err_msgs, ...
        'VariableNames', { ...
            'Path','TeamAcronym','Driver','Venue','Session', ...
            'CarNumber','Vehicle','Date','LoadOK','ErrorMsg'});

    % ------------------------------------------------------------------ %
    %  Unique aliases
    % ------------------------------------------------------------------ %
    raw_drivers  = strtrim(drivers(ok_flags));
    raw_venues   = strtrim(venues(ok_flags));
    raw_sessions = strtrim(sessions(ok_flags));

    result.drivers  = sort(unique(raw_drivers(~cellfun(@isempty, raw_drivers))));
    result.venues   = sort(unique(raw_venues(~cellfun(@isempty, raw_venues))));
    result.sessions = sort(unique(raw_sessions(~cellfun(@isempty, raw_sessions))));

    % ------------------------------------------------------------------ %
    %  Summary
    % ------------------------------------------------------------------ %
    if verbose
        fprintf('\n--- Results ---\n');
        fprintf('Files scanned : %d\n', row);
        fprintf('Files OK      : %d\n', sum(ok_flags));
        fprintf('Files failed  : %d\n', sum(~ok_flags));

        fprintf('\nUnique DRIVERS (%d):\n', numel(result.drivers));
        for i = 1:numel(result.drivers)
            fprintf('  "%s"\n', result.drivers{i});
        end

        fprintf('\nUnique VENUES (%d):\n', numel(result.venues));
        for i = 1:numel(result.venues)
            fprintf('  "%s"\n', result.venues{i});
        end

        fprintf('\nUnique SESSIONS (%d):\n', numel(result.sessions));
        for i = 1:numel(result.sessions)
            fprintf('  "%s"\n', result.sessions{i});
        end
    end

    % ------------------------------------------------------------------ %
    %  Alias cross-reference — inlined, no external smp_alias_xref needed
    % ------------------------------------------------------------------ %
    if ~isempty(alias_file)
        if verbose
            fprintf('\n--- Running alias cross-reference ---\n');
        end

        driver_map = smp_driver_alias_load(alias_file);

        % Build driver lookup: lowercase alias -> canonical name
        drv_lut    = containers.Map('KeyType','char','ValueType','char');
        drv_fields = fieldnames(driver_map);
        for i = 1:numel(drv_fields)
            entry = driver_map.(drv_fields{i});
            if ~isstruct(entry) || ~isfield(entry,'canonical'), continue; end
            canonical   = entry.canonical;
            all_aliases = {};
            if isfield(entry,'aliases'), all_aliases = entry.aliases; end
            all_aliases{end+1} = lower(canonical);
            if isfield(entry,'tla') && ~isempty(entry.tla)
                all_aliases{end+1} = lower(entry.tla);
            end
            all_aliases = unique(all_aliases);
            for j = 1:numel(all_aliases)
                k = strtrim(all_aliases{j});
                if ~isempty(k) && ~isKey(drv_lut, k)
                    drv_lut(k) = canonical;
                end
            end
        end

        % Build venue + session lookups from eventAlias if supplied
        ven_lut = containers.Map('KeyType','char','ValueType','char');
        ses_lut = containers.Map('KeyType','char','ValueType','char');
        if ~isempty(event_alias_file) && exist(event_alias_file,'file')
            event_alias = smp_alias_load(event_alias_file);
            if isfield(event_alias,'venue')
                src = event_alias.venue.lookup;
                src_keys = keys(src);
                for k = 1:numel(src_keys)
                    ven_lut(src_keys{k}) = src(src_keys{k});
                end
            end
            if isfield(event_alias,'session')
                src = event_alias.session.lookup;
                src_keys = keys(src);
                for k = 1:numel(src_keys)
                    ses_lut(src_keys{k}) = src(src_keys{k});
                end
            end
        end

        % Cross-reference
        [drv_matched, drv_unmatched] = xref_names(result.drivers,  drv_lut);
        [ven_matched, ven_unmatched] = xref_names(result.venues,   ven_lut);
        [ses_matched, ses_unmatched] = xref_names(result.sessions, ses_lut);

        % Store
        xref.drivers.matched      = drv_matched;
        xref.drivers.unmatched    = drv_unmatched;
        xref.drivers.n_matched    = numel(drv_matched);
        xref.drivers.n_unmatched  = numel(drv_unmatched);
        xref.venues.matched       = ven_matched;
        xref.venues.unmatched     = ven_unmatched;
        xref.venues.n_matched     = numel(ven_matched);
        xref.venues.n_unmatched   = numel(ven_unmatched);
        xref.sessions.matched     = ses_matched;
        xref.sessions.unmatched   = ses_unmatched;
        xref.sessions.n_matched   = numel(ses_matched);
        xref.sessions.n_unmatched = numel(ses_unmatched);
        xref.ok = (xref.drivers.n_unmatched == 0) && (xref.sessions.n_unmatched == 0);
        result.xref = xref;

        % Print
        if verbose
            print_xref('DRIVERS',  drv_matched, drv_unmatched, 'driverAlias.xlsx');
            if ~isempty(result.venues)
                print_xref('VENUES', ven_matched, ven_unmatched, 'eventAlias.xlsx  [VENUE sheet]');
            end
            print_xref('SESSIONS', ses_matched, ses_unmatched, 'eventAlias.xlsx  [SESSION sheet]');
            print_xref_summary(xref);
        end

        % Optional Excel export
        if ~isempty(xref_export)
            write_xref_excel(xref, xref_export);
            fprintf('  Xref saved: %s\n', xref_export);
        end
    end

end


% ======================================================================= %
%  LOCAL HELPERS
% ======================================================================= %

function val = get_opt(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end

function s = truncate(s, n)
    if numel(s) > n, s = [s(1:n-2) '..']; end
end

function dn = to_datenum(d)
    if isnumeric(d)
        dn = d;
    elseif isdatetime(d)
        dn = datenum(d);
    else
        dn = datenum(char(d));
    end
end

function [matched, unmatched] = xref_names(raw_names, lut)
% Match raw name strings against a containers.Map lookup.
% Exact match only (case-insensitive via lowercase key normalisation).
    matched   = {};
    unmatched = {};
    if lut.Count == 0
        unmatched = raw_names;
        return;
    end
    for i = 1:numel(raw_names)
        raw       = raw_names{i};
        raw_lower = lower(strtrim(raw));
        if isempty(raw_lower), continue; end

        if isKey(lut, raw_lower)
            matched{end+1} = {raw, lut(raw_lower), 'exact'};  %#ok
        else
            unmatched{end+1} = raw;  %#ok
        end
    end
end

function print_xref(label, matched, unmatched, alias_file_hint)
    if nargin < 4, alias_file_hint = 'alias file'; end
    n_total = numel(matched) + numel(unmatched);
    fprintf('\n--- %s (%d found, %d matched, %d unmatched) ---\n', ...
        label, n_total, numel(matched), numel(unmatched));
    if ~isempty(matched)
        fprintf('  Matched:\n');
        for i = 1:numel(matched)
            r = matched{i};
            fprintf('    [OK] %-30s  ->  %-25s  (%s)\n', r{1}, r{2}, r{3});
        end
    end
    if ~isempty(unmatched)
        fprintf('  *** UNMATCHED — add to %s ***\n', alias_file_hint);
        for i = 1:numel(unmatched)
            fprintf('    [!!] %s\n', unmatched{i});
        end
    end
end

function print_xref_summary(xref)
    sep = repmat('-', 1, 40);
    fprintf('\n%s\n', sep);

    % Drivers
    if xref.drivers.n_unmatched == 0
        fprintf('  DRIVERS  : ALL MATCHED\n');
    else
        fprintf('  DRIVERS  : %d UNMATCHED\n', xref.drivers.n_unmatched);
        for i = 1:numel(xref.drivers.unmatched)
            fprintf('    [!!] %s\n', xref.drivers.unmatched{i});
        end
    end

    % Sessions
    if xref.sessions.n_unmatched == 0
        fprintf('  SESSIONS : ALL MATCHED\n');
    else
        fprintf('  SESSIONS : %d UNMATCHED\n', xref.sessions.n_unmatched);
        for i = 1:numel(xref.sessions.unmatched)
            fprintf('    [!!] %s\n', xref.sessions.unmatched{i});
        end
    end

    fprintf('%s\n', sep);
    if xref.ok
        fprintf('  STATUS: ALL NAMES MATCHED  [xref.ok = true]\n');
    else
        fprintf('  STATUS: UNRESOLVED NAMES FOUND  [xref.ok = false]\n');
        fprintf('  Fix the alias files above, then re-run.\n');
    end
    fprintf('%s\n\n', sep);
end

function write_xref_excel(xref, filepath)
    write_xref_sheet(xref.drivers,  filepath, 'Drivers',  'driverAlias.xlsx');
    write_xref_sheet(xref.venues,   filepath, 'Venues',   'eventAlias.xlsx [VENUE]');
    write_xref_sheet(xref.sessions, filepath, 'Sessions', 'eventAlias.xlsx [SESSION]');
end

function write_xref_sheet(section, filepath, sheet_name, hint)
    raw = {};  canonical = {};  status = {};  via = {};
    for i = 1:numel(section.matched)
        r = section.matched{i};
        raw{end+1}       = r{1};       %#ok
        canonical{end+1} = r{2};       %#ok
        status{end+1}    = 'MATCHED';  %#ok
        via{end+1}       = r{3};       %#ok
    end
    for i = 1:numel(section.unmatched)
        raw{end+1}       = section.unmatched{i};                        %#ok
        canonical{end+1} = '';                                          %#ok
        status{end+1}    = ['UNMATCHED — ADD TO ' upper(hint)];        %#ok
        via{end+1}       = '';                                          %#ok
    end
    if isempty(raw), return; end
    T = table(raw(:), canonical(:), status(:), via(:), ...
        'VariableNames', {'Raw_Name_From_File','Matched_Canonical','Status','Match_Method'});
    writetable(T, filepath, 'Sheet', sheet_name);
end