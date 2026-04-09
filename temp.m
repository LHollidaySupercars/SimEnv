ch = SMP.XMP.channels{end}.Trip_Distance;
fprintf('Samples: %d\n', numel(ch.data));
fprintf('Sample rate: %g Hz\n', ch.sample_rate);
fprintf('Duration implied: %.1f s\n', numel(ch.data) / ch.sample_rate);

%%

fid = fopen(SMP.XMP.meta.Path{end}, 'rb');
fseek(fid, 0x00258F69, 'bof');
raw_i16 = fread(fid, 765/2, 'int16=>double', 0, 'l');  % half the samples
phys = raw_i16 ./ 10;
fprintf('First 5: '); disp(phys(1:5)')
fclose(fid);
%%

fid = fopen(SMP.XMP.meta.Path{end}, 'rb');
fseek(fid, 0x00258F69, 'bof');
% Read as int16 but skip 2 bytes after each sample
raw_i16 = fread(fid, 765/2, 'int16=>double', 2, 'l');  % 2 = skip bytes
phys = raw_i16 ./ 10;
fprintf('First 5: '); disp(phys(1:5)')
fclose(fid);
%%



fid = fopen(SMP.XMP.meta.Path{end}, 'rb');

data_ptr = 0x00258F69;  % paste data_ptr from diagnose for Trip Distance
data_len = 765;         % paste dlen

fseek(fid, data_ptr, 'bof');
raw_i16 = fread(fid, data_len, 'int16=>double', 0, 'l');

% With dec=1: divide by 10
phys = raw_i16 ./ 10;

fprintf('First 5 values: '); disp(phys(1:5)')
fclose(fid);

%%

fid = fopen(SMP.XMP.meta.Path{end}, 'rb');

% Get data_ptr for Trip Distance from your diagnose output
data_ptr = 0x00258F69;  % paste the 0xdata_ptr value from diagnose output

% Try reading float32 at data_ptr and nearby offsets
for offset = [0, 4, 8, 12, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
    fseek(fid, data_ptr + offset, 'bof');
    val = fread(fid, 3, 'float32=>double', 0, 'l');
    fprintf('data_ptr + %3d: %.4f  %.4f  %.4f\n', offset, val(1), val(2), val(3));
end

fclose(fid);
%%


raw_val = cursor_info;  % what diagnose shows
ch_offset  = 0;   % from diagnose
ch_mul     = 1;   % from diagnose  
ch_scale   = 1;   % from diagnose
dec_places = 1;   % from diagnose

%%

fid = fopen(SMP.XMP.meta.Path{end}, 'rb');
fseek(fid, 0, 'eof'); file_sz = ftell(fid);
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    fread(fid, 1, 'uint32=>double', 0, 'l');
    next_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    data_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    data_len = fread(fid, 1, 'uint32=>double', 0, 'l');
    fread(fid, 4, 'uint16=>double', 0, 'l');
    fread(fid, 4, 'int16=>double',  0, 'l');
    name_raw = fread(fid, 32, 'uint8=>double')';
    nul = find(name_raw==0,1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end
    name = strtrim(char(name_raw));

    if contains(lower(name), 'trip') || contains(lower(name), 'dist')
        fprintf('data_ptr : 0x%X\n', data_ptr);

        % Raw hex — 772.2 as float32 = 0x44410CCD
        fseek(fid, data_ptr, 'bof');
        raw = fread(fid, 40, 'uint8=>double')';
        fprintf('Raw hex  : %s\n', sprintf('%02X ', raw));

        % Try reading with offset applied
        fseek(fid, data_ptr, 'bof');
        v32 = fread(fid, 10, 'float32=>double', 0, 'l');
        fprintf('float32  : %s\n', sprintf('%.3f ', v32));

        fseek(fid, data_ptr, 'bof');
        vi16 = fread(fid, 10, 'int16=>double', 0, 'l');
        fprintf('int16    : %s\n', sprintf('%g ', vi16));
        break;
    end
    ptr = next_ptr;
end
fclose(fid);

%%
fid = fopen(SMP.XMP.meta.Path{end}, 'rb');  % last file
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

% Dump first 96 bytes of the first channel header
fseek(fid, ptr, 'bof');
raw = fread(fid, 4096*2, 'uint8=>double')';

fprintf('Offset   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\n');
fprintf('%s\n', repmat('-',1,60));
for row = 0:16:numel(raw)-1
    seg  = raw(row+1 : min(row+16, end));
    hexs = sprintf('%02X ', seg);
    asc  = seg; asc(asc<32|asc>126) = double('.');
    fprintf('+0x%02X   %s | %s\n', row, hexs, char(asc));
end
fclose(fid);