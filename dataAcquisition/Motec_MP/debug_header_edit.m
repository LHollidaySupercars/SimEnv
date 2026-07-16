% debug_header_edit.m
% Inspect and plan header field edits for a MoTeC .ld file.
%
% Desired changes:
%   Venue      = 'Symmons Plains Raceway'
%   Event      = 'Tasmania Super440 Session Q14_Q15'
%   Vehicle    = 'GEN3 Toyota'
%
% Run this FIRST to confirm current values and locate the Event field
% in the event block before writing.

filepath = 'E:\2026\E05_TAS\ECU\Q14_Q15\S1_#26484_20260523_113509.ld';

%% 1. Current fixed-header values via motec_ld_info
fprintf('\n=== motec_ld_info (current values) ===\n');
info = motec_ld_info(filepath, true);

%% 2. Read and print event_ptr
fid = fopen(filepath, 'rb');
if fid == -1, error('Cannot open: %s', filepath); end
fseek(fid, 0x0004, 'bof');
event_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
fclose(fid);
fprintf('\nevent_ptr (from 0x0004) = 0x%X  (%d decimal)\n', event_ptr, event_ptr);

%% 3. Dump the event block — find where "Event" string lives
% Look for 'Tasmania' / 'Symmons' / current venue/event strings in output.
% The reader currently reads event_ptr+0x10 (64 bytes) and calls it "Session".
fprintf('\n=== motec_ld_meta_dump (event block, first 512 bytes) ===\n');
motec_ld_meta_dump(filepath, 512);

%% 4. Targeted hex dump of the 3 fixed-offset fields we want to change
fields = {
    0x00DE, 64, 'vehicle  (0x00DE)';
    0x015E, 64, 'venue    (0x015E)';
    0x05E4, 32, 'session  (0x05E4)';
};

fprintf('\n=== Targeted field hex dump ===\n');
fid = fopen(filepath, 'rb');
if fid == -1, error('Cannot open: %s', filepath); end

for k = 1:size(fields, 1)
    off  = fields{k,1};
    len  = fields{k,2};
    lbl  = fields{k,3};
    fseek(fid, off, 'bof');
    raw = fread(fid, len, 'uint8=>double')';
    nul = find(raw == 0, 1);
    if ~isempty(nul)
        str = char(raw(1:nul-1));
    else
        str = char(raw);
    end
    fprintf('\n  %s\n', lbl);
    fprintf('    String : "%s"\n', str);
    fprintf('    Length : %d / %d bytes\n', numel(str), len);
    seg = raw(1:min(32, numel(raw)));
    fprintf('    Hex    : %s\n', sprintf('%02X ', seg));
end

fclose(fid);

%% 5. Also dump event_ptr+0x10 (64 bytes) — what the reader reads as "Session"
if event_ptr > 0
    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    fseek(fid, event_ptr + 0x10, 'bof');
    raw = fread(fid, 64, 'uint8=>double')';
    fclose(fid);
    nul = find(raw == 0, 1);
    if ~isempty(nul)
        str = char(raw(1:nul-1));
    else
        str = char(raw);
    end
    fprintf('\n  event_ptr+0x10 (reader "Session" field, 64 bytes)\n');
    fprintf('    String : "%s"\n', str);
    fprintf('    Hex    : %s\n', sprintf('%02X ', raw(1:min(32, numel(raw)))));
end

fprintf('\n=== Summary ===\n');
fprintf('  venue   (0x015E, 64B) : "%s"\n', info.venue);
fprintf('  vehicle (0x00DE, 64B) : "%s"\n', info.vehicle);
fprintf('  session (0x05E4, 32B) : "%s"\n', info.session);
fprintf('  run     (0x0624, 32B) : "%s"\n', info.run);
fprintf('\nDesired writes:\n');
fprintf('  venue      -> "Symmons Plains Raceway"              (%d chars / 64B max)\n', ...
    numel('Symmons Plains Raceway'));
fprintf('  vehicle    -> "GEN3 Toyota"                         (%d chars / 64B max)\n', ...
    numel('GEN3 Toyota'));
fprintf('  event      -> "Tasmania Super440 Session Q14_Q15"   (%d chars / ?? max)\n', ...
    numel('Tasmania Super440 Session Q14_Q15'));
fprintf('\nCheck the meta_dump above to confirm event field offset and size.\n');
fprintf('Then call:  old = motec_ld_header_write(filepath, overrides, true)  [dry run]\n');
fprintf('            old = motec_ld_header_write(filepath, overrides, false) [write]\n');
