FILE = 'E:\2026\T01_QLR\COM\20260505-156890014_rh_offset_test.ld';

fid = fopen(FILE, 'rb');
fseek(fid, 0, 'eof'); fsz = ftell(fid);
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

WANT = [1373, 1394];   % ECU.Engine.Speed, Laser Ride Height Rear Offset
recs = {}; names = {}; cnt = 0;
while ptr ~= 0 && ptr < fsz
    cnt = cnt + 1;
    fseek(fid, ptr, 'bof');
    rec = fread(fid, 84, 'uint8=>uint8')';
    if ismember(cnt, WANT)
        nm = strtrim(char(rec(33:64)')); nul=find(nm==char(0),1); if ~isempty(nul), nm=nm(1:nul-1); end
        recs{end+1}  = rec;
        names{end+1} = sprintf('[%d] %s', cnt, nm);
    end
    ptr = double(typecast(uint8(rec(5:8)),'uint32'));
    if cnt > 1500, break; end
end
fclose(fid);

fprintf('Found %d records\n', numel(recs));
for i = 1:numel(recs)
    r = recs{i};
    fprintf('\n=== %s ===\n', names{i});
    fprintf('  sr_raw=%-6d unk1=%-4d datatype=%d Hz=%d\n', ...
        typecast(uint8(r(17:18)),'uint16'), typecast(uint8(r(19:20)),'uint16'), ...
        typecast(uint8(r(21:22)),'uint16'), typecast(uint8(r(23:24)),'uint16'));
    fprintf('  mul=%-5d scale=%-5d dec=%-3d offset=%d\n', ...
        typecast(uint8(r(27:28)),'int16'), typecast(uint8(r(29:30)),'int16'), ...
        typecast(uint8(r(31:32)),'int16'), typecast(uint8(r(25:26)),'int16'));
    fprintf('  short="%s"  units="%s"\n', strtrim(char(r(65:72)')), strtrim(char(r(73:84)')));
    fprintf('  Hex:\n  ');
    for b=1:84, fprintf('%02X ',r(b)); if mod(b,16)==0, fprintf('\n  '); end; end
    fprintf('\n');
end

if numel(recs)==2
    diff_idx = find(recs{1}~=recs{2});
    fprintf('\n=== Diff (%d bytes different, ignoring ptrs/data_ptr) ===\n',numel(diff_idx));
    for b=diff_idx
        if b>=13  % skip prev/next/data ptrs
            fprintf('  byte %-3d  %s: 0x%02X  vs  %s: 0x%02X\n', b, names{1}(1:8), recs{1}(b), names{2}(1:8), recs{2}(b));
        end
    end
end