%% smp_build_merge_map.m
% Build a merge-map Excel from _TeamData, ECU, and L180 folders.
%
% Phase 1 — _TeamData concat + validate  (mirrors validate_concat_sessions):
%   smp_scan_folders → smp_append_stints → motec_ld_reader → concat_sessions
%   → smp_show_concat_report pop-up per multi-stint group → CSV report
%
% Phase 2 — ECU + L180  (header scan only, no concat):
%   recursive_find_ld → smp_append_stints (reads headers, resolves aliases)
%
% Phase 3 — Match by resolved session string, build rows (cartesian product)
%
% Phase 4 — Write merge_map_<timestamp>.xlsx to ROOT_FOLDER

% clear; clc;
% addpath(genpath('dataAcquisition/parseEventData'));
% addpath(genpath('dataAcquisition/Motec_MP'));

% =========================================================================
%  CONFIG — edit here
% =========================================================================
ROOT_FOLDER       = 'E:\2026\E05_TAS';

EVENT_ALIAS_FILE  = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
DRIVER_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';

SESSION_FILTER    = {'Q14'};   % {} = all sessions, or e.g. {'Q14', 'Race 1'}
TEAM_FILTER       = {};   % {} = all teams,    or e.g. {'T8R', 'WAU'}
DRIVER_FILTER     = {};   % {} = all drivers,  or e.g. {'Lastname'}

UNIQUE_FP         = true;    % drop duplicate/superset stints in _TeamData
SHOW_REPORT       = false;    % smp_show_concat_report blocking pop-up per group
HOL_OUTPUT_DIR    = 'E:\2026\E05_TAS\HOL';   % output dir for HOL .ld files, '' = skip
OVERWRITE_HOL     = false;   % true = replace existing HOL .ld files
HOL_VENUE         = 'Symmons Plains Raceway';      % venue string to write into output .ld header, '' = keep source
HOL_EVENT         = 'E05TAS';      % event string written to the run header field, '' = keep source

% =========================================================================
%  PATHS
% =========================================================================
td_dir   = fullfile(ROOT_FOLDER, '_TeamData');
ecu_dir  = fullfile(ROOT_FOLDER, 'HOL', 'ECU');
l180_dir = fullfile(ROOT_FOLDER, 'HOL', 'L180');

for chk = {td_dir, ecu_dir, l180_dir}
    if ~isfolder(chk{1})
        fprintf('[WARN] Folder not found: %s\n', chk{1});
    end
end

fprintf('=== smp_build_merge_map ===\n');
fprintf('Root: %s\n\n', ROOT_FOLDER);

% =========================================================================
%  Load alias tables (used by smp_append_stints for all three folder types)
% =========================================================================
alias      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);

% =========================================================================
%  PHASE 1 — _TeamData: concat + validate + write HOL files
%  Mirrors validate_concat_sessions.m
% =========================================================================
fprintf('--- Phase 1: _TeamData concat + validate ---\n');

scan_all = smp_scan_folders(td_dir);
if ~isempty(TEAM_FILTER)
    keep_mask = ismember({scan_all.acronym}, TEAM_FILTER);
    scan_all  = scan_all(keep_mask);
end

to_load = struct('path', {}, 'team_index', {}, 'team_acronym', {});
n_tl = 0;
for t = 1:numel(scan_all)
    for f = 1:numel(scan_all(t).files)
        n_tl = n_tl + 1;
        to_load(n_tl).path         = scan_all(t).files{f};
        to_load(n_tl).team_index   = scan_all(t).index;
        to_load(n_tl).team_acronym = scan_all(t).acronym;
    end
end

fprintf('  Files scanned: %d\n', numel(to_load));
groups_all = smp_append_stints(to_load, driver_map, alias, SESSION_FILTER);

td_groups = groups_all;
if ~isempty(DRIVER_FILTER)
    keep_mask = ismember(lower({td_groups.driver}), lower(DRIVER_FILTER));
    td_groups = td_groups(keep_mask);
end
fprintf('  Groups: %d\n\n', numel(td_groups));

concat_opts.uniqueFingerprint = UNIQUE_FP;
concat_opts.verbose           = true;

csv_rows            = {'Team,Driver,Session,File,Status,MatchedFile,Reason'};
csv_has_data        = false;
hol_manifest        = {'Driver,Team,Session,OutputFile,Status,SourceFiles'};
hol_written_drivers = {};

for g = 1:numel(td_groups)
    grp = td_groups(g);
    fprintf('  [%d/%d]  %s | %s | %s  (%d file(s))\n', ...
        g, numel(td_groups), grp.team_acronym, grp.driver, grp.session, grp.n_files);
    for fi = 1:grp.n_files
        [~, fn, ext] = fileparts(grp.files{fi});
        fprintf('    Stint %d: %s%s\n', fi, fn, ext);
    end

    % Sort files largest-first so superset is reference R in concat_sessions
    file_sizes = zeros(grp.n_files, 1);
    for fi = 1:grp.n_files
        d = dir(grp.files{fi});
        if ~isempty(d), file_sizes(fi) = d(1).bytes; end
    end
    [~, sort_idx] = sort(file_sizes, 'descend');
    grp.files     = grp.files(sort_idx);

    % Load raw channel data
    all_sess = cell(grp.n_files, 1);
    load_ok  = true;
    for fi = 1:grp.n_files
        try
            all_sess{fi} = motec_ld_reader(grp.files{fi}, {});
        catch ME
            fprintf('    [ERROR] Load failed for stint %d: %s\n', fi, ME.message);
            load_ok = false;
        end
    end

    if ~load_ok, fprintf('\n'); continue; end

    [merged_sess, fp_report] = concat_sessions(all_sess, concat_opts);
    if SHOW_REPORT
        smp_show_concat_report(fp_report, grp.key, grp.files, all_sess, merged_sess);
    end
    clear all_sess;  % free raw stint data

    % ---- Write HOL .ld ----
    if ~isempty(HOL_OUTPUT_DIR)
        hol_out_dir = fullfile(HOL_OUTPUT_DIR, grp.session);
        if ~exist(hol_out_dir, 'dir'), mkdir(hol_out_dir); end

        [~, ~, ref_ext] = fileparts(grp.files{1});
        yr_tok = regexp(td_dir, '(?:^|[\\//])(\d{4})(?:[\\//]|$)', 'tokens');
        if ~isempty(yr_tok), hol_yr = yr_tok{1}{1}; else, hol_yr = datestr(now,'yyyy'); end
%         drv_safe     = lower(regexprep(grp.driver, '[^a-zA-Z0-9]+', '_'));
%         drv_safe     = regexprep(drv_safe, '^_|_$', '');
        drv_tla  = lookup_driver_tla(driver_map, grp.driver);
        hol_name = sprintf('%s_%s_%s', drv_tla, hol_yr, grp.session);
        hol_out_file = fullfile(hol_out_dir, [hol_name ref_ext]);

        if ~OVERWRITE_HOL && exist(hol_out_file, 'file')
            fprintf('  HOL skip (exists): %s\n', hol_out_file);
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
                hol_ch_list = {};
                hol_fields  = fieldnames(merged_sess);
                for hfi = 1:numel(hol_fields)
                    hf  = hol_fields{hfi};
                    hch = merged_sess.(hf);
                    if ~isstruct(hch),             continue; end
                    if ~isfield(hch, 'data'),      continue; end
                    if ~isfield(hch, 'time'),      continue; end
                    if numel(hch.data) < 2,        continue; end
                    ld_ch             = struct();
                    ld_ch.name        = hf;
                    ld_ch.units       = '';
                    if isfield(hch, 'units'),       ld_ch.units       = hch.units;       end
                    ld_ch.sample_rate = 0;
                    if isfield(hch, 'sample_rate'), ld_ch.sample_rate = hch.sample_rate; end
                    ld_ch.value       = double(hch.data(:));
                    ld_ch.dec_places  = 2;
                    if isfield(hch, 'dec_places'),  ld_ch.dec_places  = hch.dec_places;  end
                    ld_ch.mul    = 1;
                    ld_ch.scale  = 1;
                    ld_ch.offset = 0;
                    hol_ch_list{end+1} = ld_ch; %#ok<AGROW>
                end
                try
                    ld_add_channel(grp.files{1}, hol_out_file, hol_ch_list);
                    fprintf('  HOL written (%d ch): %s\n', numel(hol_ch_list), hol_out_file);
                    hol_manifest{end+1} = sprintf('"%s",%s,%s,"%s",WRITTEN,"%s"', ...  %#ok<AGROW>
                        grp.driver, grp.team_acronym, grp.session, hol_out_file, ...
                        strjoin(grp.files, '; '));
                    hol_written_drivers{end+1} = lower(strtrim(grp.driver));           %#ok<AGROW>
                catch ME_hol
                    fprintf('  [ERROR] HOL write failed: %s\n', ME_hol.message);
                end
            end
        end

        % Always patch metadata (runs even if file was pre-existing)
        if exist(hol_out_file, 'file')
            patch_ld_header(hol_out_file, grp.session, HOL_VENUE, HOL_EVENT);
        end
    end
    clear merged_sess;  % free merged data before next group

    % Accumulate CSV rows
    for si = 1:min(numel(fp_report), grp.n_files)
        [~, fn, ext] = fileparts(grp.files{si});
        matched_file = '';
        if fp_report(si).matched_idx > 0 && fp_report(si).matched_idx <= grp.n_files
            [~, mfn, mext] = fileparts(grp.files{fp_report(si).matched_idx});
            matched_file   = [mfn mext];
        end
        reason_safe = strrep(fp_report(si).reason, ',', ';');
        csv_rows{end+1} = sprintf('%s,%s,%s,%s%s,%s,%s,"%s"', ...           %#ok<AGROW>
            grp.team_acronym, grp.driver, grp.session, fn, ext, ...
            upper(fp_report(si).status), matched_file, reason_safe);
    end
    csv_has_data = true;
    fprintf('\n');
end

% Write CSV (mirrors validate_concat_sessions)
if csv_has_data
    csv_path = fullfile(td_dir, ...
        sprintf('concat_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
    fid = fopen(csv_path, 'w');
    if fid ~= -1
        for ri = 1:numel(csv_rows)
            fprintf(fid, '%s\n', csv_rows{ri});
        end
        fclose(fid);
        fprintf('  CSV saved: %s\n\n', csv_path);
    else
        fprintf('  [WARN] Could not write CSV to: %s\n\n', csv_path);
    end
end

% ---- HOL manifest CSV + MISSING rows ----
if ~isempty(HOL_OUTPUT_DIR) && numel(hol_manifest) > 1
    dm_keys = fieldnames(driver_map);
    for di = 1:numel(dm_keys)
        canonical = driver_map.(dm_keys{di}).canonical;
        if ~any(strcmp(lower(strtrim(canonical)), hol_written_drivers))
            hol_manifest{end+1} = sprintf('"%s",,,,%s,', canonical, 'MISSING'); %#ok<AGROW>
        end
    end
    hol_csv_path = fullfile(HOL_OUTPUT_DIR, ...
        sprintf('hol_manifest_%s.csv', strjoin(SESSION_FILTER, '_')));
    fid = fopen(hol_csv_path, 'w');
    if fid ~= -1
        for ri = 1:numel(hol_manifest)
            fprintf(fid, '%s\n', hol_manifest{ri});
        end
        fclose(fid);
        n_written = sum(cellfun(@(r) contains(r,'WRITTEN') || contains(r,'COPIED'), hol_manifest));
        n_missing = sum(cellfun(@(r) contains(r,'MISSING'), hol_manifest));
        fprintf('  HOL manifest: %d written/copied, %d missing -> %s\n\n', ...
            n_written, n_missing, hol_csv_path);
    else
        fprintf('  [WARN] Could not write HOL manifest: %s\n\n', hol_csv_path);
    end
end

% =========================================================================
%  PHASE 1b — Re-read HOL files from disk
% =========================================================================
fprintf('--- Phase 1b: Re-read HOL files ---\n');
hol_groups = scan_folder_headers(HOL_OUTPUT_DIR, '_TeamData', driver_map, alias, SESSION_FILTER);
fprintf('  HOL groups found: %d\n\n', numel(hol_groups));

% =========================================================================
%  PHASE 2 — ECU + L180: header scan via smp_append_stints (no concat)
% =========================================================================
fprintf('--- Phase 2: ECU + L180 header scan ---\n');

ecu_groups  = scan_folder_headers(ecu_dir,  'ECU',  driver_map, alias, SESSION_FILTER);
l180_groups = scan_folder_headers(l180_dir, 'L180', driver_map, alias, SESSION_FILTER);

fprintf('  ECU  groups: %d\n',  numel(ecu_groups));
fprintf('  L180 groups: %d\n\n', numel(l180_groups));

% =========================================================================
%  PHASE 3 — Match hol_groups vs ECU vs L180
%  Tier 1: exact session string  |  Tier 2: date (log_date YYYYMMDD)
% =========================================================================
fprintf('--- Phase 3: Matching ---\n');

hol_sess  = lower({hol_groups.session});
ecu_sess  = lower({ecu_groups.session});
l180_sess = lower({l180_groups.session});

all_sessions = unique([hol_sess, ecu_sess, l180_sess], 'stable');
fprintf('  Unique sessions (Tier 1): %d\n', numel(all_sessions));

rows = {};
matched_hol  = false(1, max(1, numel(hol_groups)));
matched_ecu  = false(1, max(1, numel(ecu_groups)));
matched_l180 = false(1, max(1, numel(l180_groups)));

% --- Tier 1: exact session string ---
for s = 1:numel(all_sessions)
    sess = all_sessions{s};

    ti_list  = find(strcmp(hol_sess,  sess));
    ei_list  = find(strcmp(ecu_sess,  sess));
    li_list  = find(strcmp(l180_sess, sess));

    if isempty(ti_list),  ti_list  = 0; end
    if isempty(ei_list),  ei_list  = 0; end
    if isempty(li_list),  li_list  = 0; end

    for ti = ti_list
        for ei = ei_list
            for li = li_list
                has_hol = ti > 0;
                has_ecu = ei > 0;
                has_l18 = li > 0;

                if     has_hol && has_ecu && has_l18,  mq = 'full';
                elseif has_hol && has_ecu,             mq = 'no_l180';
                elseif has_hol && has_l18,             mq = 'no_ecu';
                elseif has_ecu && has_l18,             mq = 'no_hol';
                elseif has_hol,                        mq = 'hol_only';
                elseif has_ecu,                        mq = 'ecu_only';
                else,                                  mq = 'l180_only';
                end

                rows{end+1} = build_row(sess, mq, 1, ...   %#ok<AGROW>
                    hol_groups,  ti, ...
                    ecu_groups,  ei, ...
                    l180_groups, li);

                if ti > 0, matched_hol(ti)  = true; end
                if ei > 0, matched_ecu(ei)  = true; end
                if li > 0, matched_l180(li) = true; end
            end
        end
    end
end

% --- Tier 2: date-based fallback for unmatched files ---
unmatched_hol  = find(~matched_hol(1:numel(hol_groups)));
unmatched_ecu  = find(~matched_ecu(1:numel(ecu_groups)));
unmatched_l180 = find(~matched_l180(1:numel(l180_groups)));

if ~isempty([unmatched_hol, unmatched_ecu, unmatched_l180])
    fprintf('  Unmatched — HOL:%d  ECU:%d  L180:%d -> date match\n', ...
        numel(unmatched_hol), numel(unmatched_ecu), numel(unmatched_l180));

    hol_dates  = {hol_groups.log_date};
    ecu_dates  = {ecu_groups.log_date};
    l180_dates = {l180_groups.log_date};

    all_dates = {};
    if ~isempty(unmatched_hol),  all_dates = [all_dates,  hol_dates(unmatched_hol)];  end
    if ~isempty(unmatched_ecu),  all_dates = [all_dates,  ecu_dates(unmatched_ecu)];  end
    if ~isempty(unmatched_l180), all_dates = [all_dates, l180_dates(unmatched_l180)]; end
    all_dates = unique(all_dates, 'stable');

    for d = 1:numel(all_dates)
        dt = all_dates{d};
        if isempty(dt), continue; end

        ti_list = []; ei_list = []; li_list = [];
        if ~isempty(unmatched_hol)
            ti_list = unmatched_hol(strcmp(hol_dates(unmatched_hol),   dt));
        end
        if ~isempty(unmatched_ecu)
            ei_list = unmatched_ecu(strcmp(ecu_dates(unmatched_ecu),   dt));
        end
        if ~isempty(unmatched_l180)
            li_list = unmatched_l180(strcmp(l180_dates(unmatched_l180), dt));
        end

        if isempty(ti_list), ti_list = 0; end
        if isempty(ei_list), ei_list = 0; end
        if isempty(li_list), li_list = 0; end

        for ti = ti_list
            for ei = ei_list
                for li = li_list
                    rows{end+1} = build_row(dt, 'date_match', 2, ... %#ok<AGROW>
                        hol_groups,  ti, ...
                        ecu_groups,  ei, ...
                        l180_groups, li);
                end
            end
        end
    end
end

fprintf('  Total rows: %d\n\n', numel(rows));

% =========================================================================
%  PHASE 4 — Write Excel
% =========================================================================
fprintf('--- Phase 4: Writing Excel ---\n');

xl_path = fullfile(ROOT_FOLDER, ...
    sprintf('merge_map_%s.xlsx', datestr(now, 'yyyymmdd_HHMMSS')));

% Column layout (25 total):
%  1-3   : match info (quality, key, tier)
%  4-10  : HOL      (7 cols)
%  11-17 : ECU      (7 cols)
%  18-24 : L180     (7 cols)
%  25    : match_date (Tier 2 rows)
headers = { ...
    'match_quality',  'match_key',     'match_tier', ...
    'HOL_path',       'HOL_driver',    'HOL_session', ...
    'HOL_venue',      'HOL_date',      'HOL_car',      'HOL_team', ...
    'ECU_paths',      'ECU_driver',    'ECU_session', ...
    'ECU_venue',      'ECU_date',      'ECU_car',      'ECU_team', ...
    'L180_paths',     'L180_driver',   'L180_session', ...
    'L180_venue',     'L180_date',     'L180_car',     'L180_team', ...
    'match_date' };

n_cols = numel(headers);   % 25
out    = [headers; cell(numel(rows), n_cols)];
for r = 1:numel(rows)
    out(r + 1, :) = rows{r};
end

writecell(out, xl_path);
fprintf('  Saved: %s\n', xl_path);
fprintf('\n=== Done ===\n');


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function groups = scan_folder_headers(folder, type_tag, driver_map, alias, session_filter)
% SCAN_FOLDER_HEADERS  Recursively find .ld files and group via smp_append_stints.
%   type_tag is a short string used as the team_acronym (e.g. 'ECU', 'L180').
    groups = struct('key',{},'driver',{},'car',{},'session',{},...
                    'venue',{},'log_date',{},'time_str',{},'run_number',{},...
                    'team_acronym',{},'files',{},'n_files',{});

    if ~isfolder(folder)
        return;
    end

    ld_files = recursive_find_ld(folder);
    if isempty(ld_files)
        return;
    end

    file_list = struct('path', {}, 'team_index', {}, 'team_acronym', {});
    for i = 1:numel(ld_files)
        file_list(i).path         = ld_files{i};
        file_list(i).team_index   = 1;
        file_list(i).team_acronym = type_tag;
    end

    groups = smp_append_stints(file_list, driver_map, alias, session_filter);
end


function row = build_row(key, mq, tier, hol_groups, ti, ecu_groups, ei, l180_groups, li)
% BUILD_ROW  Assemble one 25-element Excel row.
    row    = cell(1, 25);
    row{1} = mq;
    row{2} = key;
    row{3} = tier;

    % HOL columns (4-10)
    if ti > 0
        g       = hol_groups(ti);
        row{4}  = strjoin(g.files, '; ');
        row{5}  = g.driver;
        row{6}  = g.session;
        row{7}  = g.venue;
        row{8}  = g.log_date;
        row{9}  = g.car;
        row{10} = g.team_acronym;
    else
        row(4:10) = repmat({''}, 1, 7);
    end

    % ECU columns (11-17)
    if ei > 0
        e       = ecu_groups(ei);
        row{11} = strjoin(e.files, '; ');
        row{12} = e.driver;
        row{13} = e.session;
        row{14} = e.venue;
        row{15} = e.log_date;
        row{16} = e.car;
        row{17} = e.team_acronym;
    else
        row(11:17) = repmat({''}, 1, 7);
    end

    % L180 columns (18-24)
    if li > 0
        l       = l180_groups(li);
        row{18} = strjoin(l.files, '; ');
        row{19} = l.driver;
        row{20} = l.session;
        row{21} = l.venue;
        row{22} = l.log_date;
        row{23} = l.car;
        row{24} = l.team_acronym;
    else
        row(18:24) = repmat({''}, 1, 7);
    end

    % match_date col (25) — Tier 2 rows
    if tier == 2
        row{25} = key;
    else
        row{25} = '';
    end
end


function files = recursive_find_ld(folder)
% RECURSIVE_FIND_LD  Find all .ld files under a folder recursively.
    files = {};
    if ~isfolder(folder), return; end

    d_files = dir(fullfile(folder, '*.ld'));
    for i = 1:numel(d_files)
        files{end+1} = fullfile(folder, d_files(i).name); %#ok<AGROW>
    end

    d_dirs = dir(folder);
    d_dirs = d_dirs([d_dirs.isdir]);
    d_dirs = d_dirs(~ismember({d_dirs.name}, {'.', '..'}));
    for i = 1:numel(d_dirs)
        sub   = recursive_find_ld(fullfile(folder, d_dirs(i).name));
        files = [files, sub]; %#ok<AGROW>
    end
end


function patch_ld_header(filepath, session_str, venue_str, event_str)
% Patch session (0x5E4/32b), venue (0x15E/64b), event via run (0x624/32b)
% in a MoTeC .ld file in-place. Empty strings are skipped.
    FIELDS = {hex2dec('5E4'), session_str, 32; ...
              hex2dec('15E'), venue_str,   64; ...
              hex2dec('624'), event_str,   32};
    fid = fopen(filepath, 'r+b');
    if fid == -1
        fprintf('  [WARN] patch_ld_header: cannot open %s\n', filepath);
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for fi = 1:size(FIELDS, 1)
        off = FIELDS{fi, 1};
        str = FIELDS{fi, 2};
        len = FIELDS{fi, 3};
        if isempty(str), continue; end
        bytes      = zeros(1, len, 'uint8');
        n          = min(numel(str), len - 1);
        bytes(1:n) = uint8(str(1:n));
        fseek(fid, off, 'bof');
        fwrite(fid, bytes, 'uint8');
    end
end


% -------------------------------------------------------------------------
function tla = lookup_driver_tla(driver_map, driver_name)
% Look up driver TLA (DRV_TLA column) from alias map.
% Falls back to safe lower-case driver_name if no TLA found.
    tla = '';
    if ~isempty(driver_map) && ~isempty(driver_name)
        name_lower = lower(strtrim(driver_name));
        keys = fieldnames(driver_map);
        for k = 1:numel(keys)
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