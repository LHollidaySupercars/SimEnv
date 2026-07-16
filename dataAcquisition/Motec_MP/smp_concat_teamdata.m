% function smp_concat_teamdata(cfg)
% %% smp_concat_teamdata(cfg)
% % Concat multi-stint TeamData .ld files into one HOL file per driver/session.
% %
% % Extracted from helper/validate_concat_sessions.m (real-data section only).
% % Synthetic unit tests have been removed — see git history if needed.
% %
% % Required cfg fields:
% %   cfg.td_input_dir        — root _TeamData folder
% %   cfg.session_filter      — cell array of session names, {} = all
% %   cfg.team_filter         — cell array of team acronyms, {} = all
% %   cfg.driver_filter       — cell array of driver names,  {} = all
% %   cfg.event_alias_file    — path to eventAlias.xlsx
% %   cfg.driver_alias_file   — path to driverAlias.xlsx
% %   cfg.unique_fp           — true = drop duplicate/superset stints
% %   cfg.show_report         — true = blocking smp_show_concat_report pop-up
% %   cfg.td_hol_output_dir   — root HOL output folder ('' = skip writing)
% %   cfg.overwrite           — true = replace existing HOL files
% %   cfg.hol_venue           — venue string patched into output header
% %   cfg.hol_event           — event string patched into output header
% %
% % Optional filtering cfg fields:
% %   cfg.event_date          — event date string 'YYYY-MM-DD'; files whose
% %                             filesystem date falls outside the tolerance
% %                             window are flagged DATE? in the concat report
% %                             and confirmed via questdlg before exclusion.
% %                             Leave '' or omit to disable.
% %   cfg.date_tolerance_days — integer days either side of event_date that
% %                             are considered valid (default: 1)
% %   cfg.flagged_paths       — cell array of substrings; any file whose full
% %                             path contains one of these strings is confirmed
% %                             via questdlg before exclusion. {} = disable.
% 
% fprintf('=== smp_concat_teamdata ===\n\n');
% fprintf('  Input : %s\n', cfg.td_input_dir);
% if ~isempty(cfg.td_hol_output_dir)
%     fprintf('  Output: %s\n', cfg.td_hol_output_dir);
% end
% fprintf('\n');
% 
% if ~isfolder(cfg.td_input_dir)
%     error('smp_concat_teamdata: td_input_dir not found:\n  %s', cfg.td_input_dir);
% end
% 
% alias      = smp_alias_load(cfg.event_alias_file);
% driver_map = smp_driver_alias_load(cfg.driver_alias_file);
% 
% % =========================================================================
% %  Scan & group
% % =========================================================================
% scan_all = smp_scan_folders(cfg.td_input_dir);
% if ~isempty(cfg.team_filter)
%     keep_mask = ismember({scan_all.acronym}, cfg.team_filter);
%     scan_all  = scan_all(keep_mask);
% end
% 
% to_load = struct('path', {}, 'team_index', {}, 'team_acronym', {});
% n_tl = 0;
% for t = 1 : numel(scan_all)
%     for f = 1 : numel(scan_all(t).files)
%         n_tl = n_tl + 1;
%         to_load(n_tl).path         = scan_all(t).files{f};
%         to_load(n_tl).team_index   = scan_all(t).index;
%         to_load(n_tl).team_acronym = scan_all(t).acronym;
%     end
% end
% 
% fprintf('  Files scanned: %d\n', numel(to_load));
% groups_all = smp_append_stints(to_load, driver_map, alias, cfg.session_filter);
% 
% groups = groups_all;
% if ~isempty(cfg.driver_filter)
%     keep_mask = ismember(lower({groups.driver}), lower(cfg.driver_filter));
%     groups    = groups(keep_mask);
% end
% fprintf('  Groups: %d\n\n', numel(groups));
% 
% if isempty(groups)
%     fprintf('  [SKIP] No groups found for session filter: %s\n\n', ...
%         strjoin(cfg.session_filter, ', '));
%     return;
% end
% 
% % =========================================================================
% %  Concat each group
% % =========================================================================
% concat_opts.uniqueFingerprint = cfg.unique_fp;
% concat_opts.verbose           = true;
% 
% csv_rows            = {'Team,Driver,Session,File,Status,MatchedFile,Reason'};
% csv_has_data        = false;
% hol_manifest        = {'Driver,Team,Session,OutputFile,Status,SourceFiles'};
% hol_written_drivers = {};
% 
% % Infer year from input dir path
% yr_tok = regexp(cfg.td_input_dir, '(?:^|[\\/])(\d{4})(?:[\\/]|$)', 'tokens');
% if ~isempty(yr_tok)
%     hol_yr = yr_tok{1}{1};
% else
%     hol_yr = datestr(now, 'yyyy');
% end
% 
% hol_ses = strjoin(cfg.session_filter, '_');
% 
% for g = 1 : numel(groups)
%     grp = groups(g);
% 
%     % ---- Early overwrite check (skip expensive load/concat if not needed) ----
%     if ~isempty(cfg.td_hol_output_dir) && ~cfg.overwrite
%         [~, ~, ref_ext_pre] = fileparts(grp.files{1});
%         drv_tla_pre      = lookup_driver_tla(driver_map, grp.driver);
%         hol_out_dir_pre  = fullfile(cfg.td_hol_output_dir, grp.session);
%         hol_name_pre     = sprintf('%s_%s_%s', drv_tla_pre, hol_yr, hol_ses);
%         existing_pre     = smp_find_existing_hol(cfg.td_hol_output_dir, [hol_name_pre ref_ext_pre]);
%         if ~isempty(existing_pre)
%             fprintf('  [%d/%d]  %s | %s | %s  — HOL exists (%s), skipping (overwrite=false)\n', ...
%                 g, numel(groups), grp.team_acronym, grp.driver, grp.session, existing_pre);
%             continue;
%         end
%     end
% 
%     fprintf('  [%d/%d]  %s | %s | %s  (%d file(s))\n', ...
%         g, numel(groups), grp.team_acronym, grp.driver, grp.session, grp.n_files);
%     for fi = 1 : grp.n_files
%         [~, fn, ext] = fileparts(grp.files{fi});
%         fprintf('    Stint %d: %s%s\n', fi, fn, ext);
%     end
% 
%     % ---- Flagged-path filter (explicit questdlg per match) ----
%     if isfield(cfg,'flagged_paths') && ~isempty(cfg.flagged_paths)
%         keep_fp = true(grp.n_files, 1);
%         for fi = 1 : grp.n_files
%             if any(cellfun(@(p) contains(grp.files{fi}, p), cfg.flagged_paths))
%                 [~, fn, ext] = fileparts(grp.files{fi});
%                 ans_fp = questdlg( ...
%                     sprintf('File matches a flagged path pattern:\n  %s%s\n\nExclude from concat?', fn, ext), ...
%                     'Flagged Path', 'Exclude', 'Keep', 'Keep');
%                 if strcmp(ans_fp, 'Exclude')
%                     keep_fp(fi) = false;
%                     fprintf('    [FLAGGED PATH] Excluded: %s%s\n', fn, ext);
%                     csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,EXCLUDED_PATH,,"Flagged path match"', ... %#ok<AGROW>
%                         grp.team_acronym, grp.driver, grp.session, fn, ext);
%                     csv_has_data = true;
%                 end
%             end
%         end
%         grp.files   = grp.files(keep_fp);
%         grp.n_files = sum(keep_fp);
%         if grp.n_files == 0
%             fprintf('  [SKIP] All files excluded by flagged-path filter\n\n');
%             continue;
%         end
%     end
% 
%     % ---- Date filter — build date_flags for report; exclusion after report ----
%     use_date_filter = isfield(cfg,'event_date') && ~isempty(cfg.event_date);
%     date_flags = [];
%     if use_date_filter
%         tol_days = 1;
%         if isfield(cfg,'date_tolerance_days') && ~isempty(cfg.date_tolerance_days)
%             tol_days = cfg.date_tolerance_days;
%         end
%         event_dn = datenum(cfg.event_date, 'yyyy-mm-dd');
%         date_flags = struct('is_suspect', cell(grp.n_files,1), ...
%                             'file_date',  cell(grp.n_files,1), ...
%                             'event_date', cell(grp.n_files,1));
%         for fi = 1 : grp.n_files
%             d = dir(grp.files{fi});
%             file_dn = 0;
%             if ~isempty(d), file_dn = floor(d(1).datenum); end
%             is_sus = (file_dn > 0) && (abs(file_dn - event_dn) > tol_days);
%             date_flags(fi).is_suspect = is_sus;
%             date_flags(fi).file_date  = datestr(file_dn, 'yyyy-mm-dd');
%             date_flags(fi).event_date = cfg.event_date;
%             if is_sus
%                 [~, fn, ext] = fileparts(grp.files{fi});
%                 fprintf('    [DATE FLAG] %s%s  (file: %s  event: %s)\n', ...
%                     fn, ext, date_flags(fi).file_date, cfg.event_date);
%             end
%         end
%     end
% 
%     % Sort files largest-first so superset is reference R in concat_sessions
%     file_sizes = zeros(grp.n_files, 1);
%     for fi = 1 : grp.n_files
%         d = dir(grp.files{fi});
%         if ~isempty(d), file_sizes(fi) = d(1).bytes; end
%     end
%     [~, sort_idx] = sort(file_sizes, 'descend');
%     grp.files = grp.files(sort_idx);
% 
%     % Load raw channel data
%     all_sess = cell(grp.n_files, 1);
%     load_ok  = true;
%     for fi = 1 : grp.n_files
%         try
%             all_sess{fi} = motec_ld_reader(grp.files{fi}, {});
%         catch ME
%             fprintf('    [ERROR] Load failed for stint %d: %s\n', fi, ME.message);
%             load_ok = false;
%         end
%     end
%     if ~load_ok, fprintf('\n'); continue; end
% 
%     [merged_sess, fp_report] = concat_sessions(all_sess, concat_opts);
%     exclude_mask = false(grp.n_files, 1);
%     if cfg.show_report
%         exclude_mask = smp_show_concat_report(fp_report, grp.key, grp.files, all_sess, merged_sess, date_flags);
%     elseif use_date_filter
%         % No report shown — still prompt for any date-suspect files
%         for fi = 1 : grp.n_files
%             if ~isempty(date_flags) && date_flags(fi).is_suspect
%                 [~, fn, ext] = fileparts(grp.files{fi});
%                 ans_dt = questdlg( ...
%                     sprintf('File %s%s was recorded on %s but event date is %s.\n\nExclude from concat?', ...
%                         fn, ext, date_flags(fi).file_date, date_flags(fi).event_date), ...
%                     'Date Warning', 'Exclude', 'Keep', 'Keep');
%                 exclude_mask(fi) = strcmp(ans_dt, 'Exclude');
%             end
%         end
%     end
% 
%     % Apply date exclusions
%     if any(exclude_mask)
%         for fi = find(exclude_mask(:)')
%             [~, fn, ext] = fileparts(grp.files{fi});
%             fprintf('    [DATE EXCLUDED] %s%s\n', fn, ext);
%             if use_date_filter && ~isempty(date_flags) && numel(date_flags) >= fi
%                 file_date_str  = date_flags(fi).file_date;
%                 event_date_str = date_flags(fi).event_date;
%             else
%                 file_date_str  = 'N/A';
%                 event_date_str = 'N/A';
%             end
%             csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,EXCLUDED_DATE,,"%s vs event %s"', ... %#ok<AGROW>
%                 grp.team_acronym, grp.driver, grp.session, fn, ext, ...
%                 file_date_str, event_date_str);
%             csv_has_data = true;
%         end
%         all_sess    = all_sess(~exclude_mask);
%         grp.files   = grp.files(~exclude_mask);
%         grp.n_files = numel(grp.files);
%         if grp.n_files == 0
%             fprintf('  [SKIP] All files excluded by date filter\n\n');
%             clear merged_sess;
%             continue;
%         end
%         % Re-run concat without excluded files
%         [merged_sess, fp_report] = concat_sessions(all_sess, concat_opts);
%     end
% 
%     % ---- Chronological re-sort (right before write) ----
%     % All data checks and dedup are done.  Re-order the surviving sessions
%     % by header date+time so the HOL output is oldest-to-newest.
%     % Falls back to filesystem datenum if the header clock fields are empty.
%     if grp.n_files > 1
%         file_datenums = zeros(grp.n_files, 1);
%         for fi = 1 : grp.n_files
%             dn = 0;
%             try
%                 hi = motec_ld_info(grp.files{fi}, false);
%                 if ~isempty(hi.date) && ~isempty(hi.time)
%                     dt_str = strtrim([hi.date ' ' hi.time]);
%                     dn = datenum(dt_str, 'dd/mm/yyyy HH:MM:SS');
%                 end
%             catch
%             end
%             if dn == 0
%                 d_fi = dir(grp.files{fi});
%                 if ~isempty(d_fi), dn = d_fi(1).datenum; end
%             end
%             file_datenums(fi) = dn;
%         end
%         [~, chron_idx] = sort(file_datenums, 'ascend');
%         if ~isequal(chron_idx(:)', 1:grp.n_files)
%             all_sess  = all_sess(chron_idx);
%             grp.files = grp.files(chron_idx);
%             fprintf('  Chronological order after re-sort:\n');
%             for fi = 1 : grp.n_files
%                 [~, fn, ext] = fileparts(grp.files{fi});
%                 fprintf('    %d: %s%s  (datenum=%.5f)\n', fi, fn, ext, file_datenums(chron_idx(fi)));
%             end
%             reorder_opts = concat_opts;
%             reorder_opts.uniqueFingerprint = false;
%             reorder_opts.verbose           = false;
%             merged_sess = concat_sessions(all_sess, reorder_opts);
%         end
%     end
%     clear all_sess;  % free raw stint data
% 
%     % ---- Write HOL .ld ----
%     if ~isempty(cfg.td_hol_output_dir)
%         hol_out_dir = fullfile(cfg.td_hol_output_dir, grp.session);
%         if ~exist(hol_out_dir, 'dir'), mkdir(hol_out_dir); end
% 
%         [~, ~, ref_ext] = fileparts(grp.files{1});
%         drv_tla      = lookup_driver_tla(driver_map, grp.driver);
%         hol_name     = sprintf('%s_%s_%s', drv_tla, hol_yr, hol_ses);
%         hol_out_file = fullfile(hol_out_dir, [hol_name ref_ext]);
% 
%         % Recursive existence check across the whole output tree
%         existing_path = smp_find_existing_hol(cfg.td_hol_output_dir, [hol_name ref_ext]);
%         file_exists   = ~isempty(existing_path);
% 
%         if ~cfg.overwrite && file_exists
%             fprintf('  HOL skip (exists elsewhere): %s\n', existing_path);
%         else
%             if grp.n_files == 1
%                 try
%                     copyfile(grp.files{1}, hol_out_file);
%                     fprintf('  HOL copied: %s\n', hol_out_file);
%                     hol_manifest{end+1} = sprintf('"%s",%s,%s,"%s",COPIED,"%s"', ...  %#ok<AGROW>
%                         grp.driver, grp.team_acronym, grp.session, hol_out_file, grp.files{1});
%                     hol_written_drivers{end+1} = lower(strtrim(grp.driver));           %#ok<AGROW>
%                 catch ME_hol
%                     fprintf('  [ERROR] HOL copy failed: %s\n', ME_hol.message);
%                 end
%             else
%                 try
%                     smp_hol_write_concat(grp.files{1}, merged_sess, hol_out_file);
%                     fprintf('  HOL written: %s\n', hol_out_file);
%                     hol_manifest{end+1} = sprintf('"%s",%s,%s,"%s",WRITTEN,"%s"', ...  %#ok<AGROW>
%                         grp.driver, grp.team_acronym, grp.session, hol_out_file, ...
%                         strjoin(grp.files, '; '));
%                     hol_written_drivers{end+1} = lower(strtrim(grp.driver));           %#ok<AGROW>
%                 catch ME_hol
%                     fprintf('  [ERROR] HOL write failed: %s\n', ME_hol.message);
%                 end
%             end
%         end
% 
%         % Patch metadata (runs even if file was pre-existing)
%         if exist(hol_out_file, 'file')
%             patch_ld_header_td(hol_out_file, grp.session, cfg.hol_venue, cfg.hol_event);
%         end
%     end
%     clear merged_sess;  % free merged data before loading next group
%     clear reorder_opts;
% 
%     % Accumulate CSV rows
%     for si = 1 : min(numel(fp_report), grp.n_files)
%         [~, fn, ext] = fileparts(grp.files{si});
%         matched_file = '';
%         if fp_report(si).matched_idx > 0 && fp_report(si).matched_idx <= grp.n_files
%             [~, mfn, mext] = fileparts(grp.files{fp_report(si).matched_idx});
%             matched_file = [mfn mext];
%         end
%         reason_safe = strrep(fp_report(si).reason, ',', ';');
%         csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,%s,%s,"%s"', ...           %#ok<AGROW>
%             grp.team_acronym, grp.driver, grp.session, fn, ext, ...
%             upper(fp_report(si).status), matched_file, reason_safe);
%     end
%     csv_has_data = true;
%     fprintf('\n');
% end
% 
% % =========================================================================
% %  Write CSV report
% % =========================================================================
% if csv_has_data
%     csv_path = fullfile(cfg.td_input_dir, ...
%         sprintf('concat_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
%     fid = fopen(csv_path, 'w');
%     if fid ~= -1
%         for ri = 1 : numel(csv_rows)
%             fprintf(fid, '%s\n', csv_rows{ri});
%         end
%         fclose(fid);
%         fprintf('  CSV saved: %s\n\n', csv_path);
%     else
%         fprintf('  [WARN] Could not write CSV to: %s\n\n', csv_path);
%     end
% end
% 
% % =========================================================================
% %  HOL manifest (present + missing drivers)
% % =========================================================================
% if ~isempty(cfg.td_hol_output_dir) && numel(hol_manifest) > 1
%     dm_keys = fieldnames(driver_map);
%     for di = 1 : numel(dm_keys)
%         canonical = driver_map.(dm_keys{di}).canonical;
%         if ~any(strcmp(lower(strtrim(canonical)), hol_written_drivers))
%             hol_manifest{end+1} = sprintf('"%s",,,,%s,', canonical, 'MISSING'); %#ok<AGROW>
%         end
%     end
%     hol_csv_path = fullfile(cfg.td_hol_output_dir, ...
%         sprintf('hol_manifest_%s.csv', strjoin(cfg.session_filter, '_')));
%     fid = fopen(hol_csv_path, 'w');
%     if fid ~= -1
%         for ri = 1 : numel(hol_manifest)
%             fprintf(fid, '%s\n', hol_manifest{ri});
%         end
%         fclose(fid);
%         n_written = sum(cellfun(@(r) contains(r,'WRITTEN') || contains(r,'COPIED'), hol_manifest));
%         n_missing = sum(cellfun(@(r) contains(r,'MISSING'), hol_manifest));
%         fprintf('  HOL manifest: %d written/copied, %d missing -> %s\n\n', ...
%             n_written, n_missing, hol_csv_path);
%     else
%         fprintf('  [WARN] Could not write HOL manifest to: %s\n\n', hol_csv_path);
%     end
% end
% 
% fprintf('=== smp_concat_teamdata done ===\n');
% 
% end  % function smp_concat_teamdata
% 
% 
% % =========================================================================
% %  LOCAL FUNCTIONS
% % =========================================================================
% 
% function tla = lookup_driver_tla(driver_map, driver_name)
%     tla = '';
%     if ~isempty(driver_map) && ~isempty(driver_name)
%         name_lower = lower(strtrim(driver_name));
%         keys = fieldnames(driver_map);
%         for k = 1 : numel(keys)
%             if any(strcmp(name_lower, driver_map.(keys{k}).aliases))
%                 tla = driver_map.(keys{k}).tla;
%                 break;
%             end
%         end
%     end
%     if isempty(tla)
%         tla = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]+', '_');
%         tla = regexprep(tla, '^_|_$', '');
%         if ~isempty(driver_name) && ~isempty(tla)
%             fprintf('  [WARN] No TLA for driver "%s" — using "%s"\n', driver_name, tla);
%         end
%     end
% end
% 
% % =========================================================================
% function patch_ld_header_td(filepath, session_str, venue_str, event_str)
% % Patch session (0x5E4/32b), venue (0x15E/64b), event (0x624/32b) in-place.
%     FIELDS = {hex2dec('5E4'), session_str, 32; ...
%               hex2dec('15E'), venue_str,   64; ...
%               hex2dec('624'), event_str,   32};
%     fid = fopen(filepath, 'r+b');
%     if fid == -1
%         fprintf('  [WARN] patch_ld_header_td: cannot open %s\n', filepath);
%         return;
%     end
%     c = onCleanup(@() fclose(fid)); %#ok<NASGU>
%     for k = 1 : size(FIELDS, 1)
%         str = FIELDS{k, 2};
%         if isempty(str), continue; end
%         offset    = FIELDS{k, 1};
%         field_len = FIELDS{k, 3};
%         bytes     = zeros(1, field_len, 'uint8');
%         n         = min(numel(str), field_len);
%         bytes(1:n) = uint8(str(1:n));
%         fseek(fid, offset, 'bof');
%         fwrite(fid, bytes, 'uint8');
%     end
% end
% 
% function found_path = smp_find_existing_hol(root_dir, target_filename)
% % Recursively search root_dir for a file matching target_filename (name+ext).
% % Returns full path of first match, or '' if not found.
% found_path = '';
% if ~isfolder(root_dir), return; end
% d = dir(fullfile(root_dir, '**', target_filename));
% if ~isempty(d)
%     found_path = fullfile(d(1).folder, d(1).name);
% end
% end

function smp_concat_teamdata(cfg)
%% smp_concat_teamdata(cfg)
% Concat multi-stint TeamData .ld files into one HOL file per driver/session.
%
% Extracted from helper/validate_concat_sessions.m (real-data section only).
% Synthetic unit tests have been removed — see git history if needed.
%
% Required cfg fields:
%   cfg.td_input_dir        — root _TeamData folder
%   cfg.session_filter      — cell array of session names, {} = all
%   cfg.team_filter         — cell array of team acronyms, {} = all
%   cfg.driver_filter       — cell array of driver names,  {} = all
%   cfg.event_alias_file    — path to eventAlias.xlsx
%   cfg.driver_alias_file   — path to driverAlias.xlsx
%   cfg.unique_fp           — true = drop duplicate/superset stints
%   cfg.show_report         — true = blocking smp_show_concat_report pop-up
%   cfg.td_hol_output_dir   — root HOL output folder ('' = skip writing)
%   cfg.overwrite           — true = replace existing HOL files
%   cfg.hol_venue           — venue string patched into output header
%   cfg.hol_event           — event string patched into output header
%
% Optional filtering cfg fields:
%   cfg.event_date          — event date string 'YYYY-MM-DD'; files whose
%                             filesystem date falls outside the tolerance
%                             window are flagged DATE? in the concat report
%                             and confirmed via questdlg before exclusion.
%                             Leave '' or omit to disable.
%   cfg.date_tolerance_days — integer days either side of event_date that
%                             are considered valid (default: 1)
%   cfg.flagged_paths       — cell array of substrings; any file whose full
%                             path contains one of these strings is confirmed
%                             via questdlg before exclusion. {} = disable.

fprintf('=== smp_concat_teamdata ===\n\n');
fprintf('  Input : %s\n', cfg.td_input_dir);
if ~isempty(cfg.td_hol_output_dir)
    fprintf('  Output: %s\n', cfg.td_hol_output_dir);
end
fprintf('\n');

if ~isfolder(cfg.td_input_dir)
    error('smp_concat_teamdata: td_input_dir not found:\n  %s', cfg.td_input_dir);
end

alias      = smp_alias_load(cfg.event_alias_file);
driver_map = smp_driver_alias_load(cfg.driver_alias_file);

% =========================================================================
%  Scan & group
% =========================================================================
scan_all = smp_scan_folders(cfg.td_input_dir);
if ~isempty(cfg.team_filter)
    keep_mask = ismember({scan_all.acronym}, cfg.team_filter);
    scan_all  = scan_all(keep_mask);
end

to_load = struct('path', {}, 'team_index', {}, 'team_acronym', {});
n_tl = 0;
for t = 1 : numel(scan_all)
    for f = 1 : numel(scan_all(t).files)
        n_tl = n_tl + 1;
        to_load(n_tl).path         = scan_all(t).files{f};
        to_load(n_tl).team_index   = scan_all(t).index;
        to_load(n_tl).team_acronym = scan_all(t).acronym;
    end
end

fprintf('  Files scanned: %d\n', numel(to_load));
groups_all = smp_append_stints(to_load, driver_map, alias, cfg.session_filter);

groups = groups_all;
if ~isempty(cfg.driver_filter)
    keep_mask = ismember(lower({groups.driver}), lower(cfg.driver_filter));
    groups    = groups(keep_mask);
end
fprintf('  Groups: %d\n\n', numel(groups));

if isempty(groups)
    fprintf('  [SKIP] No groups found for session filter: %s\n\n', ...
        strjoin(cfg.session_filter, ', '));
    return;
end

% =========================================================================
%  Concat each group
% =========================================================================
concat_opts.uniqueFingerprint = cfg.unique_fp;
concat_opts.verbose           = true;

csv_rows            = {'Team,Driver,Session,File,Status,MatchedFile,Reason'};
csv_has_data        = false;
hol_manifest        = {'Driver,Team,Session,OutputFile,Status,SourceFiles'};
hol_written_drivers = {};

% Infer year from input dir path
yr_tok = regexp(cfg.td_input_dir, '(?:^|[\\/])(\d{4})(?:[\\/]|$)', 'tokens');
if ~isempty(yr_tok)
    hol_yr = yr_tok{1}{1};
else
    hol_yr = datestr(now, 'yyyy');
end

hol_ses = strjoin(cfg.session_filter, '_');

for g = 1 : numel(groups)
    grp = groups(g);

    % ---- Early overwrite check (skip expensive load/concat if not needed) ----
    if ~isempty(cfg.td_hol_output_dir) && ~cfg.overwrite
        [~, ~, ref_ext_pre] = fileparts(grp.files{1});
        drv_tla_pre      = lookup_driver_tla(driver_map, grp.driver);
        hol_out_dir_pre  = fullfile(cfg.td_hol_output_dir, grp.session);
        hol_name_pre     = sprintf('%s_%s_%s', drv_tla_pre, hol_yr, hol_ses);
        existing_pre     = smp_find_existing_hol(cfg.td_hol_output_dir, [hol_name_pre ref_ext_pre]);
        if ~isempty(existing_pre)
            fprintf('  [%d/%d]  %s | %s | %s  — HOL exists (%s), skipping (overwrite=false)\n', ...
                g, numel(groups), grp.team_acronym, grp.driver, grp.session, existing_pre);
            continue;
        end
    end

    fprintf('  [%d/%d]  %s | %s | %s  (%d file(s))\n', ...
        g, numel(groups), grp.team_acronym, grp.driver, grp.session, grp.n_files);
    for fi = 1 : grp.n_files
        [~, fn, ext] = fileparts(grp.files{fi});
        fprintf('    Stint %d: %s%s\n', fi, fn, ext);
    end

    % ---- Flagged-path filter (explicit questdlg per match) ----
    if isfield(cfg,'flagged_paths') && ~isempty(cfg.flagged_paths)
        keep_fp = true(grp.n_files, 1);
        for fi = 1 : grp.n_files
            if any(cellfun(@(p) contains(grp.files{fi}, p), cfg.flagged_paths))
                [~, fn, ext] = fileparts(grp.files{fi});
                ans_fp = questdlg( ...
                    sprintf('File matches a flagged path pattern:\n  %s%s\n\nExclude from concat?', fn, ext), ...
                    'Flagged Path', 'Exclude', 'Keep', 'Keep');
                if strcmp(ans_fp, 'Exclude')
                    keep_fp(fi) = false;
                    fprintf('    [FLAGGED PATH] Excluded: %s%s\n', fn, ext);
                    csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,EXCLUDED_PATH,,"Flagged path match"', ... %#ok<AGROW>
                        grp.team_acronym, grp.driver, grp.session, fn, ext);
                    csv_has_data = true;
                end
            end
        end
        grp.files   = grp.files(keep_fp);
        grp.n_files = sum(keep_fp);
        if grp.n_files == 0
            fprintf('  [SKIP] All files excluded by flagged-path filter\n\n');
            continue;
        end
    end

    % ---- Date filter — build date_flags for report; exclusion after report ----
    use_date_filter = isfield(cfg,'event_date') && ~isempty(cfg.event_date);
    date_flags = [];
    if use_date_filter
        tol_days = 1;
        if isfield(cfg,'date_tolerance_days') && ~isempty(cfg.date_tolerance_days)
            tol_days = cfg.date_tolerance_days;
        end
        event_dn = datenum(cfg.event_date, 'yyyy-mm-dd');
        date_flags = struct('is_suspect', cell(grp.n_files,1), ...
                            'file_date',  cell(grp.n_files,1), ...
                            'event_date', cell(grp.n_files,1));
        for fi = 1 : grp.n_files
            d = dir(grp.files{fi});
            file_dn = 0;
            if ~isempty(d), file_dn = floor(d(1).datenum); end
            is_sus = (file_dn > 0) && (abs(file_dn - event_dn) > tol_days);
            date_flags(fi).is_suspect = is_sus;
            date_flags(fi).file_date  = datestr(file_dn, 'yyyy-mm-dd');
            date_flags(fi).event_date = cfg.event_date;
            if is_sus
                [~, fn, ext] = fileparts(grp.files{fi});
                fprintf('    [DATE FLAG] %s%s  (file: %s  event: %s)\n', ...
                    fn, ext, date_flags(fi).file_date, cfg.event_date);
            end
        end
    end

    % Sort files largest-first so superset is reference R in concat_sessions
    file_sizes = zeros(grp.n_files, 1);
    for fi = 1 : grp.n_files
        d = dir(grp.files{fi});
        if ~isempty(d), file_sizes(fi) = d(1).bytes; end
    end
    [~, sort_idx] = sort(file_sizes, 'descend');
    grp.files = grp.files(sort_idx);

    % Load raw channel data
    all_sess = cell(grp.n_files, 1);
    load_ok  = true;
    for fi = 1 : grp.n_files
        try
            all_sess{fi} = motec_ld_reader(grp.files{fi}, {});
        catch ME
            fprintf('    [ERROR] Load failed for stint %d: %s\n', fi, ME.message);
            load_ok = false;
        end
    end
    if ~load_ok, fprintf('\n'); continue; end

    [merged_sess, fp_report] = concat_sessions(all_sess, concat_opts);
    exclude_mask = false(grp.n_files, 1);
    if cfg.show_report
        exclude_mask = smp_show_concat_report(fp_report, grp.key, grp.files, all_sess, merged_sess, date_flags);
    elseif use_date_filter
        % No report shown — still prompt for any date-suspect files
        for fi = 1 : grp.n_files
            if ~isempty(date_flags) && date_flags(fi).is_suspect
                [~, fn, ext] = fileparts(grp.files{fi});
                ans_dt = questdlg( ...
                    sprintf('File %s%s was recorded on %s but event date is %s.\n\nExclude from concat?', ...
                        fn, ext, date_flags(fi).file_date, date_flags(fi).event_date), ...
                    'Date Warning', 'Exclude', 'Keep', 'Keep');
                exclude_mask(fi) = strcmp(ans_dt, 'Exclude');
            end
        end
    end

    % Apply date exclusions
    if any(exclude_mask)
        for fi = find(exclude_mask(:)')
            [~, fn, ext] = fileparts(grp.files{fi});
            fprintf('    [DATE EXCLUDED] %s%s\n', fn, ext);
            if use_date_filter && ~isempty(date_flags) && numel(date_flags) >= fi
                file_date_str  = date_flags(fi).file_date;
                event_date_str = date_flags(fi).event_date;
            else
                file_date_str  = 'N/A';
                event_date_str = 'N/A';
            end
            csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,EXCLUDED_DATE,,"%s vs event %s"', ... %#ok<AGROW>
                grp.team_acronym, grp.driver, grp.session, fn, ext, ...
                file_date_str, event_date_str);
            csv_has_data = true;
        end
        all_sess    = all_sess(~exclude_mask);
        grp.files   = grp.files(~exclude_mask);
        grp.n_files = numel(grp.files);
        if grp.n_files == 0
            fprintf('  [SKIP] All files excluded by date filter\n\n');
            clear merged_sess;
            continue;
        end
        % Re-run concat without excluded files
        [merged_sess, fp_report] = concat_sessions(all_sess, concat_opts);
    end

    % ---- Chronological re-sort (right before write) ----
    % All data checks and dedup are done.  Re-order the surviving sessions
    % by header date+time so the HOL output is oldest-to-newest.
    % Falls back to filesystem datenum if the header clock fields are empty.
    if grp.n_files > 1
        file_datenums = zeros(grp.n_files, 1);
        for fi = 1 : grp.n_files
            dn = 0;
            try
                hi = motec_ld_info(grp.files{fi}, false);
                if ~isempty(hi.date) && ~isempty(hi.time)
                    dt_str = strtrim([hi.date ' ' hi.time]);
                    dn = datenum(dt_str, 'dd/mm/yyyy HH:MM:SS');
                end
            catch
            end
            if dn == 0
                d_fi = dir(grp.files{fi});
                if ~isempty(d_fi), dn = d_fi(1).datenum; end
            end
            file_datenums(fi) = dn;
        end
        [~, chron_idx] = sort(file_datenums, 'ascend');
        if ~isequal(chron_idx(:)', 1:grp.n_files)
            all_sess  = all_sess(chron_idx);
            grp.files = grp.files(chron_idx);
            fprintf('  Chronological order after re-sort:\n');
            for fi = 1 : grp.n_files
                [~, fn, ext] = fileparts(grp.files{fi});
                fprintf('    %d: %s%s  (datenum=%.5f)\n', fi, fn, ext, file_datenums(chron_idx(fi)));
            end
            reorder_opts = concat_opts;
            reorder_opts.uniqueFingerprint = false;
            reorder_opts.verbose           = false;
            merged_sess = concat_sessions(all_sess, reorder_opts);
        end
    end
    clear all_sess;  % free raw stint data

    % ---- Write HOL .ld ----
    if ~isempty(cfg.td_hol_output_dir)
        hol_out_dir = fullfile(cfg.td_hol_output_dir, grp.session);
        if ~exist(hol_out_dir, 'dir'), mkdir(hol_out_dir); end

        [~, ~, ref_ext] = fileparts(grp.files{1});
        drv_tla      = lookup_driver_tla(driver_map, grp.driver);
        hol_name     = sprintf('%s_%s_%s', drv_tla, hol_yr, hol_ses);
        hol_out_file = fullfile(hol_out_dir, [hol_name ref_ext]);
        
        % Recursive existence check across the whole output tree
        existing_path = smp_find_existing_hol(cfg.td_hol_output_dir, [hol_name ref_ext]);
        file_exists   = ~isempty(existing_path);
        
        if ~cfg.overwrite && file_exists
            fprintf('  HOL skip (exists elsewhere): %s\n', existing_path);
        else
            if grp.n_files == 1
                try
                    copyfile(grp.files{1}, hol_out_file);
                    fprintf('  HOL copied: %s\n', hol_out_file);
                    hol_manifest{end+1} = sprintf('"%s",%s,%s,"%s",COPIED,"%s"', ...  %#ok<AGROW>
                        grp.driver, grp.team_acronym, grp.session, hol_out_file, grp.files{1});
                    hol_written_drivers{end+1} = lower(strtrim(grp.driver));           %#ok<AGROW>
                catch ME_hol
                    fprintf('  [ERROR] HOL copy failed: %s\n', ME_hol.message);
                end
            else
                try
                    smp_hol_write_concat(grp.files{1}, merged_sess, hol_out_file);
                    fprintf('  HOL written: %s\n', hol_out_file);
                    hol_manifest{end+1} = sprintf('"%s",%s,%s,"%s",WRITTEN,"%s"', ...  %#ok<AGROW>
                        grp.driver, grp.team_acronym, grp.session, hol_out_file, ...
                        strjoin(grp.files, '; '));
                    hol_written_drivers{end+1} = lower(strtrim(grp.driver));           %#ok<AGROW>
                catch ME_hol
                    fprintf('  [ERROR] HOL write failed: %s\n', ME_hol.message);
                end
            end
        end

        % Patch metadata (runs even if file was pre-existing)
        if exist(hol_out_file, 'file')
            patch_ld_header_td(hol_out_file, grp.session, cfg.hol_venue, cfg.hol_event);
        end
    end
    clear merged_sess;  % free merged data before loading next group
    clear reorder_opts;

    % Accumulate CSV rows
    for si = 1 : min(numel(fp_report), grp.n_files)
        [~, fn, ext] = fileparts(grp.files{si});
        matched_file = '';
        if fp_report(si).matched_idx > 0 && fp_report(si).matched_idx <= grp.n_files
            [~, mfn, mext] = fileparts(grp.files{fp_report(si).matched_idx});
            matched_file = [mfn mext];
        end
        reason_safe = strrep(fp_report(si).reason, ',', ';');
        csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,%s,%s,"%s"', ...           %#ok<AGROW>
            grp.team_acronym, grp.driver, grp.session, fn, ext, ...
            upper(fp_report(si).status), matched_file, reason_safe);
    end
    csv_has_data = true;
    fprintf('\n');
end

% =========================================================================
%  Write CSV report
% =========================================================================
if csv_has_data
    csv_path = fullfile(cfg.td_input_dir, ...
        sprintf('concat_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
    fid = fopen(csv_path, 'w');
    if fid ~= -1
        for ri = 1 : numel(csv_rows)
            fprintf(fid, '%s\n', csv_rows{ri});
        end
        fclose(fid);
        fprintf('  CSV saved: %s\n\n', csv_path);
    else
        fprintf('  [WARN] Could not write CSV to: %s\n\n', csv_path);
    end
end

% =========================================================================
%  HOL manifest (present + missing drivers)
% =========================================================================
if ~isempty(cfg.td_hol_output_dir) && numel(hol_manifest) > 1
    dm_keys = fieldnames(driver_map);
    for di = 1 : numel(dm_keys)
        canonical = driver_map.(dm_keys{di}).canonical;
        if ~any(strcmp(lower(strtrim(canonical)), hol_written_drivers))
            hol_manifest{end+1} = sprintf('"%s",,,,%s,', canonical, 'MISSING'); %#ok<AGROW>
        end
    end
    hol_csv_path = fullfile(cfg.td_hol_output_dir, ...
        sprintf('hol_manifest_%s.csv', strjoin(cfg.session_filter, '_')));
    fid = fopen(hol_csv_path, 'w');
    if fid ~= -1
        for ri = 1 : numel(hol_manifest)
            fprintf(fid, '%s\n', hol_manifest{ri});
        end
        fclose(fid);
        n_written = sum(cellfun(@(r) contains(r,'WRITTEN') || contains(r,'COPIED'), hol_manifest));
        n_missing = sum(cellfun(@(r) contains(r,'MISSING'), hol_manifest));
        fprintf('  HOL manifest: %d written/copied, %d missing -> %s\n\n', ...
            n_written, n_missing, hol_csv_path);
    else
        fprintf('  [WARN] Could not write HOL manifest to: %s\n\n', hol_csv_path);
    end
end

fprintf('=== smp_concat_teamdata done ===\n');

end  % function smp_concat_teamdata


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function tla = lookup_driver_tla(driver_map, driver_name)
    tla = '';
    if ~isempty(driver_map) && ~isempty(driver_name)
        name_lower = lower(strtrim(driver_name));
        keys = fieldnames(driver_map);
        for k = 1 : numel(keys)
            if any(strcmp(name_lower, driver_map.(keys{k}).aliases))
                tla = driver_map.(keys{k}).tla;
                break;
            end
        end
    end
    if isempty(tla)
        tla = regexprep(lower(strtrim(driver_name)), '[^a-z0-9]+', '_');
        tla = regexprep(tla, '^_|_$', '');
        if ~isempty(driver_name) && ~isempty(tla)
            fprintf('  [WARN] No TLA for driver "%s" — using "%s"\n', driver_name, tla);
        end
    end
end

% =========================================================================
function patch_ld_header_td(filepath, session_str, venue_str, event_str)
% Patch session (0x5E4/32b), venue (0x15E/64b), event (0x624/32b) in-place.
%
% Also patches the secondary "correction" block (session + venue), when
% present, so both copies agree. That block is located by signature
% search (uint32 x4 = [100 56 4 1]) rather than a fixed offset, since its
% exact position drifts by a byte or two between files depending on
% earlier variable-length header content. See ld_set_session_all.m for
% the standalone version of this logic.
    FIELDS = {hex2dec('5E4'), session_str, 32; ...
              hex2dec('15E'), venue_str,   64; ...
              hex2dec('624'), event_str,   32};
    fid = fopen(filepath, 'r+b');
    if fid == -1
        fprintf('  [WARN] patch_ld_header_td: cannot open %s\n', filepath);
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for k = 1 : size(FIELDS, 1)
        str = FIELDS{k, 2};
        if isempty(str), continue; end
        offset    = FIELDS{k, 1};
        field_len = FIELDS{k, 3};
        bytes     = zeros(1, field_len, 'uint8');
        n         = min(numel(str), field_len);
        bytes(1:n) = uint8(str(1:n));
        fseek(fid, offset, 'bof');
        fwrite(fid, bytes, 'uint8');
    end
    clear c;  % onCleanup already closes fid here — no explicit fclose needed

    % ---- Secondary correction block (session + venue) ---------------------
    patch_ld_correction_block(filepath, session_str, venue_str);
end

% =========================================================================
function patch_ld_correction_block(filepath, session_str, venue_str)
% Locate the secondary venue/session block via signature search and
% overwrite its session (and venue, if supplied) fields to match the
% primary header. No-op if no block is found — not every file has one.
    SIG            = uint8(typecast(uint32([100 56 4 1]), 'uint8'));
    VENUE_REL      = 48;
    SESSION_REL    = 112;
    CORR_FIELD_LEN = 64;
    SCAN_CAP       = 4 * 1024 * 1024;

    d = dir(filepath);
    if isempty(d), return; end
    scan_len = min(d.bytes, SCAN_CAP);

    fid = fopen(filepath, 'rb');
    if fid == -1, return; end
    raw = fread(fid, scan_len, 'uint8=>uint8')';
    fclose(fid);

    hit = strfind(raw, SIG);
    if isempty(hit), return; end   % no correction block in this file — nothing to do
    sig_off = hit(1) - 1;          % 0-based

    fid = fopen(filepath, 'r+b');
    if fid == -1
        fprintf('  [WARN] patch_ld_correction_block: cannot open %s\n', filepath);
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    if ~isempty(session_str)
        write_corr_field(fid, sig_off + SESSION_REL, CORR_FIELD_LEN, session_str, filepath);
    end
    if ~isempty(venue_str)
        write_corr_field(fid, sig_off + VENUE_REL, CORR_FIELD_LEN, venue_str, filepath);
    end
end

function write_corr_field(fid, offset, field_len, str, filepath)
    if numel(str) > field_len - 1
        fprintf('  [WARN] patch_ld_correction_block: "%s" exceeds %d chars, truncating (%s)\n', ...
            str, field_len - 1, filepath);
        str = str(1:field_len - 1);
    end
    bytes = zeros(1, field_len, 'uint8');
    n     = numel(str);
    bytes(1:n) = uint8(str);
    fseek(fid, offset, 'bof');
    fwrite(fid, bytes, 'uint8');
end

function found_path = smp_find_existing_hol(root_dir, target_filename)
% Recursively search root_dir for a file matching target_filename (name+ext).
% Returns full path of first match, or '' if not found.
found_path = '';
if ~isfolder(root_dir), return; end
d = dir(fullfile(root_dir, '**', target_filename));
if ~isempty(d)
    found_path = fullfile(d(1).folder, d(1).name);
end
end