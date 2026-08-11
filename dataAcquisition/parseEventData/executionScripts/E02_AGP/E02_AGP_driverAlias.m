%% Full — date filter + xref against both alias files + export
% clear opts
opts.date_from        = datetime(2026, 3, 5);   % auto-filled: earliest session date for this event/track

opts.alias_file       = fullfile(pwd, 'dataAcquisition/Motec_MP/alias/driverAlias.xlsx');
opts.event_alias_file = fullfile(pwd, 'dataAcquisition\parseEventData\executionScripts\E02_AGP/eventAlias.xlsx');
opts.xref_export      = fullfile(pwd, 'dataAcquisition/parseEventData/aliasReports/AGP_alias_check.xlsx');
% opts.verbose          = false;
result = smp_discover_aliases('E:\2026/E02_AGP/_TeamData', opts);

% -----------------------------------------------------------------------
% Inspect raw strings (paste these into alias Excel files):
result.drivers;            % -> driverAlias.xlsx          (DRV column)
result.sessions      ;     % -> eventAlias.xlsx SESSION sheet (col A)
result.venues         ;    % -> eventAlias.xlsx VENUE sheet   (col A)

% Inspect xref breakdown:
result.xref.drivers  ;     % .matched / .unmatched / .n_matched / .n_unmatched
result.xref.sessions ;     % .matched / .unmatched / .n_matched / .n_unmatched
result.xref.venues   ;     % .matched / .unmatched / .n_matched / .n_unmatched

% Overall status:
result.xref.ok       ;     % true ONLY when drivers AND sessions are fully matched
%%

result.xref.sessions.unmatched_detail;
result.xref.drivers.unmatched_detail;
result.xref.venues.unmatched_detail;

%% =========================================================================
%  MANUAL DEBUG / PATCH TOOLS  (one-off use only — NOT auto-templated)
% =========================================================================
problematicFiles = result.xref.sessions.unmatched_detail.Path;
for i = 1:numel(problematicFiles)
  debug_print_session_field(problematicFiles{i})
  answerTheQuestion = input('Do you want to continue with the rewrite? [Y/N] ', 's');
  if strcmpi(answerTheQuestion, 'Y')
      % debug_print_session_field(problematgicFiles{i})
      pause(0.5)
      ld_set_session_all(problematicFiles{i}, 'Qualifying 9 - Part 2');
  elseif strcmp(answerTheQuestion, 'end')
      return
  end
end

%% ======================================================================= %
%  FUNCTIONS
%  (local functions — keep everything below this point at the bottom of
%  the file; MATLAB requires each function name to appear only once)
% ======================================================================= %

function debug_print_session_field(filepath)
% DEBUG_PRINT_SESSION_FIELD  Print exactly what is stored at the session
% name offset (0x5E4, 32 bytes) in a MoTeC .ld file — the PRIMARY header
% field only. No scanning, no correction-block logic — just a direct read.
%
% Usage:
%   debug_print_session_field('E:\2026\E02_AGP\_TeamData\01_T8R\<file>.ld')

    SESSION_OFFSET = 0x5E4;
    SESSION_LEN    = 32;

    if ~exist(filepath, 'file')
        error('File not found: %s', filepath);
    end

    fid = fopen(filepath, 'rb');
    if fid < 0
        error('Could not open: %s', filepath);
    end
    c = onCleanup(@() fclose(fid));

    fseek(fid, SESSION_OFFSET, 'bof');
    raw = fread(fid, SESSION_LEN, 'uint8=>double')';

    fprintf('\n=== %s ===\n', filepath);
    fprintf('Offset: 0x%X (%d)   Length: %d bytes\n\n', SESSION_OFFSET, SESSION_OFFSET, SESSION_LEN);

    fprintf('Raw bytes (hex): ');
    fprintf('%02X ', raw);
    fprintf('\n');

    fprintf('Raw bytes (dec): ');
    fprintf('%d ', raw);
    fprintf('\n\n');

    nul = find(raw == 0, 1);
    seg = raw;
    if ~isempty(nul), seg = raw(1:nul-1); end
    if isempty(seg) || any(seg < 32 | seg > 126)
        str = '(non-printable / empty)';
    else
        str = strtrim(char(seg));
    end

    fprintf('Interpreted string: "%s"\n\n', str);
end


% ======================================================================= %
function ld_set_session_all(filepath, new_session, opts)
% LD_SET_SESSION_ALL  Overwrite the session name everywhere it lives in
% a MoTeC .ld file — both the primary header field AND the secondary
% "correction" block — so every reader (motec_ld_info, i2 Pro, etc.)
% agrees on the same value.
%
% Fields patched:
%   Primary header   0x5E4          char[32]   (fixed offset)
%   Correction block session field  char[64]   (located via signature
%                                                search — offset drifts
%                                                slightly between files)
%
% Usage:
%   ld_set_session_all(filepath, 'Qualifying 22')
%   ld_set_session_all(filepath, 'Qualifying 22', opts)
%
% Options (opts struct):
%   .new_venue   char      also overwrite the correction-block venue field
%                          (default: '' = leave venue alone)
%   .backup      logical   copy filepath -> filepath.bak first (default: true)
%   .verbose     logical   print progress                      (default: true)
%   .require_correction_block  logical
%                          if true, error out when no correction block is
%                          found rather than silently patching only the
%                          primary field (default: false)
%
% Safety:
%   - Both fields are fixed-width, null-padded ASCII slots. Overwriting
%     in place does not change file length or shift any other bytes, so
%     no pointers/lengths elsewhere in the file need updating.
%   - A backup is written to "<filepath>.bak" (overwritten if it already
%     exists) unless opts.backup = false.
%   - Every write is read back and verified before returning.

    PRIMARY_OFFSET = 0x5E4;
    PRIMARY_LEN    = 32;

    SIG            = uint8(typecast(uint32([100 56 4 1]), 'uint8'));
    VENUE_REL      = 48;
    SESSION_REL    = 112;
    CORR_FIELD_LEN = 64;
    SCAN_CAP       = 4 * 1024 * 1024;

    if nargin < 3 || isempty(opts), opts = struct(); end
    new_venue        = get_opt(opts, 'new_venue',       '');
    backup_it        = get_opt(opts, 'backup',          true);
    verbose          = get_opt(opts, 'verbose',         true);
    require_corr_blk = get_opt(opts, 'require_correction_block', false);

    if ~exist(filepath, 'file')
        error('File not found: %s', filepath);
    end

    if verbose
        fprintf('\n=== ld_set_session_all ===\n');
        fprintf('File: %s\n', filepath);
    end

    % ---- Locate the correction block (if any) --------------------------
    d = dir(filepath);
    file_sz = d.bytes;
    scan_len = min(file_sz, SCAN_CAP);

    fid = fopen(filepath, 'rb');
    if fid < 0, error('Could not open: %s', filepath); end
    raw = fread(fid, scan_len, 'uint8=>uint8')';
    fclose(fid);

    hit = strfind(raw, SIG);
    have_corr_block = ~isempty(hit);
    sig_off = [];
    if have_corr_block
        sig_off = hit(1) - 1;  % 0-based
        if verbose
            fprintf('Correction block found @ offset %d (0x%X)\n', sig_off, sig_off);
        end
    else
        msg = 'No correction block signature found.';
        if require_corr_blk
            error('%s Aborting (require_correction_block = true).', msg);
        elseif verbose
            fprintf('%s Patching primary header field only.\n', msg);
        end
    end

    % ---- Report current values ------------------------------------------
    old_primary = read_field(filepath, PRIMARY_OFFSET, PRIMARY_LEN);
    if verbose
        fprintf('Primary header session (0x5E4): "%s"\n', old_primary);
    end
    if have_corr_block
        old_corr_session = read_field(filepath, sig_off + SESSION_REL, CORR_FIELD_LEN);
        old_corr_venue   = read_field(filepath, sig_off + VENUE_REL,   CORR_FIELD_LEN);
        if verbose
            fprintf('Correction block session:        "%s"\n', old_corr_session);
            fprintf('Correction block venue:          "%s"\n', old_corr_venue);
        end
    end
    if verbose
        fprintf('New session -> "%s"\n', new_session);
        if ~isempty(new_venue)
            fprintf('New venue   -> "%s"\n', new_venue);
        end
    end

    % ---- Backup ----------------------------------------------------------
    if backup_it
        bak_path = [filepath '.bak'];
        [ok, msg] = copyfile(filepath, bak_path, 'f');
        if ~ok
            error('Backup failed, aborting write: %s', msg);
        end
        if verbose
            fprintf('Backup: %s\n', bak_path);
        end
    end

    % ---- Patch primary header field --------------------------------------
    write_field(filepath, PRIMARY_OFFSET, PRIMARY_LEN, new_session);

    % ---- Patch correction block (session, and venue if requested) --------
    if have_corr_block
        write_field(filepath, sig_off + SESSION_REL, CORR_FIELD_LEN, new_session);
        if ~isempty(new_venue)
            write_field(filepath, sig_off + VENUE_REL, CORR_FIELD_LEN, new_venue);
        end
    end

    % ---- Verify ------------------------------------------------------------
    check_primary = read_field(filepath, PRIMARY_OFFSET, PRIMARY_LEN);
    if ~strcmp(check_primary, strtrim(new_session(1:min(end,PRIMARY_LEN-1))))
        error('Verification FAILED on primary header field: got "%s"', check_primary);
    end

    if have_corr_block
        check_corr_session = read_field(filepath, sig_off + SESSION_REL, CORR_FIELD_LEN);
        if ~strcmp(check_corr_session, strtrim(new_session(1:min(end,CORR_FIELD_LEN-1))))
            error('Verification FAILED on correction-block session field: got "%s"', check_corr_session);
        end
        if ~isempty(new_venue)
            check_corr_venue = read_field(filepath, sig_off + VENUE_REL, CORR_FIELD_LEN);
            if ~strcmp(check_corr_venue, strtrim(new_venue(1:min(end,CORR_FIELD_LEN-1))))
                error('Verification FAILED on correction-block venue field: got "%s"', check_corr_venue);
            end
        end
    end

    if verbose
        fprintf('Verified OK.\n\n');
    end
end


% ======================================================================= %
function val = get_opt(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end

function str = read_field(filepath, offset, len)
    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));
    fseek(fid, offset, 'bof');
    seg = fread(fid, len, 'uint8=>double')';
    nul = find(seg == 0, 1);
    if ~isempty(nul), seg = seg(1:nul-1); end
    if isempty(seg) || any(seg < 32 | seg > 126)
        str = '';
    else
        str = strtrim(char(seg));
    end
end

function write_field(filepath, offset, len, new_str)
    if numel(new_str) > len - 1
        warning('"%s" exceeds %d chars — truncating to fit field at offset %d.', ...
            new_str, len - 1, offset);
        new_str = new_str(1:len - 1);
    end
    bytes = zeros(1, len, 'uint8');
    raw   = uint8(new_str);
    bytes(1:numel(raw)) = raw;

    fid = fopen(filepath, 'r+b');
    if fid < 0
        error('Could not open for writing: %s', filepath);
    end
    c = onCleanup(@() fclose(fid));
    fseek(fid, offset, 'bof');
    n_written = fwrite(fid, bytes, 'uint8');
    if n_written ~= len
        error('Write incomplete at offset %d: wrote %d of %d bytes', offset, n_written, len);
    end
end