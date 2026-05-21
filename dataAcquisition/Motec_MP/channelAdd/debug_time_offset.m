%% debug_time_offset.m
% Diagnoses the time-offset / truncation issue for custom channels.
% Run this and paste the full output back for analysis.

clear; clc;

%% ===== CONFIG — edit these two paths =====
SOURCE_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890005.ld';
OUTPUT_FILE = 'E:\2026\T01_QLR\COM\run_metadata_all.ld';
%% =========================================

%% ----  0. stale .ldx check  -----------------------------------------
fprintf('============================================================\n');
fprintf('  .LDX CACHE CHECK\n');
fprintf('============================================================\n');
[out_dir, out_base] = fileparts(OUTPUT_FILE);
ldx_file = fullfile(out_dir, [out_base '.ldx']);
if exist(ldx_file, 'file')
    dld  = dir(OUTPUT_FILE);
    dldx = dir(ldx_file);
    fprintf('  *** STALE .ldx FOUND: %s\n', ldx_file);
    fprintf('      .ld  modified : %s\n', dld.date);
    fprintf('      .ldx modified : %s\n', dldx.date);
    fprintf('  Deleting now...\n');
    delete(ldx_file);
    if ~exist(ldx_file, 'file')
        fprintf('  DELETED OK\n\n');
    else
        fprintf('  *** DELETE FAILED — close i2 Pro and retry\n\n');
    end
else
    fprintf('  No stale .ldx found — OK\n\n');
end

fprintf('============================================================\n');
fprintf('  SOURCE : %s\n', SOURCE_FILE);
fprintf('  OUTPUT : %s\n', OUTPUT_FILE);
fprintf('============================================================\n\n');

%% ----  1. SOURCE walk + donor map  ----------------------------------
[src, n_src, src_sz] = walk_ld(SOURCE_FILE);
src_dur = max([src.n] ./ max([src.sr], 1));

fprintf('SOURCE: %d channels   dur=%.4f s   file_size=%d bytes\n\n', n_src, src_dur, src_sz);

% Donor map: best n per Hz (prefer unk1=3)
donor = containers.Map('KeyType','double','ValueType','any');
for i = 1:n_src
    hz = src(i).sr;  ni = src(i).n;
    if hz == 0 || ni == 0, continue; end
    if ~isKey(donor, hz)
        donor(hz) = src(i);
    else
        d = donor(hz);
        better = (ni > d.n) || (ni == d.n && src(i).unk1 == 3 && d.unk1 ~= 3);
        if better, donor(hz) = src(i); end
    end
end

fprintf('Donor map (best n per Hz, prefer unk1=3):\n');
fprintf('  %-6s  %8s  %8s  %6s  %6s  %-28s\n', 'Hz', 'n', 'dur(s)', 'unk1', 'sr_raw', 'name');
for hz = sort(cell2mat(keys(donor)))
    d = donor(hz);
    fprintf('  %-6d  %8d  %8.2f  0x%04X  %6d  %-28s\n', hz, d.n, d.n/hz, d.unk1, d.sr_raw, d.name);
end

%% ----  2. OUTPUT walk — custom channels only  -----------------------
fprintf('\n============================================================\n');
[out, n_out, out_sz] = walk_ld(OUTPUT_FILE);
out_dur = max([out.n] ./ max([out.sr], 1));
fprintf('OUTPUT: %d channels   dur=%.4f s   file_size=%d bytes\n\n', n_out, out_dur, out_sz);

src_lc = lower({src.name});

fprintf('Custom channels (not in source):\n');
fprintf('  %-30s  %5s  %8s  %8s  %6s  %6s  %8s  %9s  %s\n', ...
    'name', 'Hz', 'n', 'exp_n', 'delta', 'sr_raw', 'data_ptr', 'data_end', 'OK?');
fprintf('  %s\n', repmat('-', 1, 100));

n_cust = 0;
for i = 1:n_out
    if ismember(lower(out(i).name), src_lc), continue; end
    n_cust = n_cust + 1;
    o   = out(i);
    exp_n = 0;
    if isKey(donor, double(o.sr)), exp_n = donor(double(o.sr)).n; end
    bps  = bytes_per(o.datatype);
    dend = o.data_ptr + o.n * bps;
    ok   = iif(dend <= out_sz && o.n == exp_n, 'YES', '*** NO');
    fprintf('  %-30s  %5d  %8d  %8d  %6d  %6d  %8d  %9d  %s\n', ...
        o.name, o.sr, o.n, exp_n, o.n - exp_n, o.sr_raw, o.data_ptr, dend, ok);
end
if n_cust == 0
    fprintf('  (none found — all names match source)\n');
end

%% ----  3. Decoded sample data  -------------------------------------
fprintf('\nDecoded sample values (first 3 / last 3):\n');
fid2 = fopen(OUTPUT_FILE, 'rb');
c2   = onCleanup(@() fclose(fid2));
for i = 1:n_out
    if ismember(lower(out(i).name), src_lc), continue; end
    o = out(i);
    if o.n == 0 || o.data_ptr == 0, continue; end
    nh = min(3, o.n); nt = min(3, o.n);
    bps = bytes_per(o.datatype);
    fseek(fid2, o.data_ptr, 'bof');
    rh = rd_raw(fid2, nh, o.datatype);
    fseek(fid2, o.data_ptr + (o.n - nt) * bps, 'bof');
    rt = rd_raw(fid2, nt, o.datatype);
    ph = dec_phys(rh, o.mul, o.scale, o.dec, o.offset);
    pt = dec_phys(rt, o.mul, o.scale, o.dec, o.offset);
    fprintf('  "%s"  first=[%s]  last=[%s]\n', o.name, ...
        num2str(ph(:)', '%.4f '), num2str(pt(:)', '%.4f '));
end

%% ----  4. File header event_ptr comparison  -------------------------
fprintf('\n============================================================\n');
fprintf('  FILE HEADER comparison\n');
fprintf('============================================================\n');
for lbl = {'SOURCE', 'OUTPUT'}
    fp = iif(strcmp(lbl{1}, 'SOURCE'), SOURCE_FILE, OUTPUT_FILE);
    fh = fopen(fp, 'rb');
    if fh < 0, fprintf('  [%s] cannot open\n', lbl{1}); continue; end
    fseek(fh, 0x0004, 'bof'); ep = fread(fh, 1, 'uint32=>double', 0, 'l');
    fseek(fh, 0x0008, 'bof'); cp = fread(fh, 1, 'uint32=>double', 0, 'l');
    fprintf('  [%s]  event_ptr=0x%X  first_ch_ptr=0x%X\n', lbl{1}, ep, cp);
    if ep > 0
        fseek(fh, ep + 16, 'bof');
        ss = fread(fh, 64, 'uint8=>uint8')';
        nul = find(ss == 0, 1);
        if ~isempty(nul) && nul > 1
            fprintf('    session string: "%s"\n', char(ss(1:nul-1)));
        end
        % Dump first 32 bytes of event block raw
        fseek(fh, ep, 'bof');
        eb = fread(fh, 32, 'uint8=>uint8')';
        fprintf('    event block hex: %s\n', sprintf('%02X ', eb));
    end
    fclose(fh);
end

%% ----  5. Header scan — find uint32 fields that encode file sizes  ---
fprintf('\n============================================================\n');
fprintf('  HEADER SCAN — first 256 bytes of SOURCE file\n');
fprintf('  (looking for uint32 values == source file size or channel data boundary)\n');
fprintf('============================================================\n');

fhs = fopen(SOURCE_FILE, 'rb');
hdr = fread(fhs, 256, 'uint8=>uint8')';
fclose(fhs);

% Print hex dump
fprintf('  Offset  +0 +1 +2 +3  +4 +5 +6 +7  +8 +9 +A +B  +C +D +E +F\n');
for row = 0:15
    base = row*16 + 1;
    if base > numel(hdr), break; end
    chunk = hdr(base:min(base+15, end));
    hex_str = sprintf('%02X ', chunk);
    fprintf('  0x%04X  %s\n', (row*16), hex_str);
end

% Scan all uint32 LE values for interesting large numbers
fprintf('\n  All uint32 LE values in header (offset, hex_value, decimal):\n');
fprintf('  %-8s  %-12s  %-12s  %s\n', 'offset', 'hex', 'decimal', 'note');
for k = 1:4:numel(hdr)-3
    v = double(typecast(uint8(hdr(k:k+3)), 'uint32'));
    if v > 1000  % only show values > 1000 (likely pointers or sizes)
        note = '';
        if v == src_sz,                       note = '<-- SOURCE file size !'; end
        if v == out_sz,                       note = '<-- OUTPUT file size';   end
        if abs(v - src_sz) < 100,             note = sprintf('<-- near src_sz (diff=%+d)', v-src_sz); end
        fprintf('  0x%04X    0x%08X    %-12d  %s\n', k-1, v, v, note);
    end
end

%% ----  6. First native channel data_ptr  ----------------------------
fprintf('\n============================================================\n');
fprintf('  NATIVE CHANNEL DATA_PTR SAMPLE (first 5 channels)\n');
fprintf('  (shows whether native data lives before or after metadata list)\n');
fprintf('============================================================\n');
fprintf('  %-30s  %8s  %8s\n', 'name', 'data_ptr', 'data_end');
for i = 1:min(5, n_src)
    s = src(i);
    bps = bytes_per(s.datatype);
    fprintf('  %-30s  %8d  %8d\n', s.name, s.data_ptr, s.data_ptr + s.n*bps);
end

fprintf('\n============================================================\n');
fprintf('  DONE — paste this output back\n');
fprintf('============================================================\n');

%% ===== local helpers =====

function [ch, nc, fsz] = walk_ld(fp)
    f = fopen(fp, 'rb');
    if f < 0, error('Cannot open: %s', fp); end
    fseek(f, 0, 'eof'); fsz = ftell(f);
    fseek(f, 0x0008, 'bof');
    ptr = fread(f, 1, 'uint32=>double', 0, 'l');
    fclose(f);
    f = fopen(fp, 'rb');
    c = onCleanup(@() fclose(f));
    ch = struct([]); nc = 0;
    while ptr ~= 0 && ptr < fsz
        fseek(f, ptr, 'bof');
        rec = fread(f, 84, 'uint8=>uint8')';
        if numel(rec) < 84, break; end
        next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
        nb  = rec(33:64); nul = find(nb == 0, 1);
        if ~isempty(nul), nb = nb(1:nul-1); end
        nc = nc + 1;
        ch(nc).name     = strtrim(char(nb));
        ch(nc).sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
        ch(nc).n        = double(typecast(uint8(rec(13:16)), 'uint32'));
        ch(nc).sr_raw   = double(typecast(uint8(rec(17:18)), 'uint16'));
        ch(nc).unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
        ch(nc).datatype = double(typecast(uint8(rec(21:22)), 'uint16'));
        ch(nc).offset   = double(typecast(uint8(rec(25:26)), 'int16'));
        ch(nc).mul      = double(typecast(uint8(rec(27:28)), 'int16'));
        ch(nc).scale    = double(typecast(uint8(rec(29:30)), 'int16'));
        ch(nc).dec      = double(typecast(uint8(rec(31:32)), 'int16'));
        ch(nc).data_ptr = double(typecast(uint8(rec(9:12)),  'uint32'));
        ptr = next_ptr;
        if nc > 5000, warning('5000-ch limit hit'); break; end
    end
end

function raw = rd_raw(fid, n, dtype)
    switch dtype
        case 1;     raw = fread(fid, n, 'uint16=>double', 0, 'l');
        case 2;     raw = fread(fid, n, 'int16=>double',  0, 'l');
        case 3;     raw = fread(fid, n, 'int32=>double',  0, 'l');
        case 4;     raw = fread(fid, n, 'int16=>double',  2, 'l');  % 2-byte pad
        otherwise;  raw = zeros(n, 1);
    end
end

function b = bytes_per(dtype)
    switch dtype
        case {1, 2}; b = 2;
        case 3;      b = 4;
        case 4;      b = 4;   % int16 + 2-byte pad = 4 bytes/sample
        otherwise;   b = 2;
    end
end

function phys = dec_phys(raw, mul, sc, dec, off)
    if sc ~= 0 && mul ~= 0
        phys = raw .* (mul / sc) ./ (10^dec) + off;
    else
        phys = raw ./ (10^dec) + off;
    end
end

function v = iif(cond, a, b)
    if cond, v = a; else, v = b; end
end
