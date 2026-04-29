% DIAGNOSE_CHANNELS
% Reads every channel and prints first 3 physical values.
% Run: diagnose_channels(SMP.XMP.meta.Path{end})
% Output: C:\temp\channel_diagnose.txt

function diagnose_channels(filepath)

    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);

    fseek(fid, 0x0008, 'bof');
    current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    fout = fopen('C:\temp\channel_diagnose.txt', 'w');
    fprintf(fout, 'File: %s\n', filepath);
    fprintf(fout, 'File size: 0x%X\n\n', file_sz);

    % ---------------------------------------------------------------
    % First: scan the FIRST channel block to find where the name lives
    % ---------------------------------------------------------------
    fprintf(fout, '=== NAME OFFSET SCAN (first channel block at 0x%X) ===\n', current_ptr);
    fseek(fid, current_ptr, 'bof');
    block = fread(fid, 128, 'uint8=>double')';

    for off = 0:2:124
        seg = block(off+1 : min(off+32, end));
        run = 0;
        for k = 1:numel(seg)
            if seg(k) >= 32 && seg(k) <= 126, run = run + 1;
            else, break;
            end
        end
        if run >= 4
            fprintf(fout, '  +0x%02X: "%s"\n', off, char(seg(1:run)));
        end
    end
    fprintf(fout, '\n');

    % Raw hex dump of first block
    fprintf(fout, '=== RAW HEX: first channel block ===\n');
    fprintf(fout, 'Offset   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | ASCII\n');
    fprintf(fout, '%s\n', repmat('-',1,75));
    for row = 0:16:numel(block)-1
        seg  = block(row+1:min(row+16,end));
        hexs = sprintf('%02X ', seg);
        hexs = [hexs, repmat('   ',1,16-numel(seg))]; %#ok
        asc  = seg; asc(asc<32|asc>126) = double('.');
        fprintf(fout, '+0x%03X   %s | %s\n', row, hexs, char(asc));
    end
    fprintf(fout, '\n\n');

    % ---------------------------------------------------------------
    % Main channel table
    % ---------------------------------------------------------------
    fprintf(fout, '%-35s  %-6s %-5s %-7s %-7s %-7s %-7s %-4s  0xdata_ptr  %-10s %-10s %-10s  %s\n', ...
        'Channel', 'Hz', 'type', 'dlen', 'offset', 'mul', 'scale', 'dec', 'val1', 'val2', 'val3', 'units');
    fprintf(fout, '%s\n', repmat('-', 1, 140));

    % Name offsets to try in order
    NAME_OFFSETS = [0x20, 0x24, 0x18, 0x1C, 0x28, 0x2C, 0x30];

    ch_count = 0;
    while current_ptr ~= 0 && current_ptr < file_sz

        fseek(fid, current_ptr, 'bof');
        prev_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); %#ok
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
        sr_raw      = fread(fid, 1, 'uint16=>double', 0, 'l'); %#ok
        unk1        = fread(fid, 1, 'uint16=>double', 0, 'l'); %#ok
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l'); % unk2 = true Hz
        ch_offset   = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_mul      = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_scale    = fread(fid, 1, 'int16=>double',  0, 'l');
        dec_places  = fread(fid, 1, 'int16=>double',  0, 'l');

        % Try each name offset until we find printable string
        name_str = '';
        for noi = 1:numel(NAME_OFFSETS)
            fseek(fid, current_ptr + NAME_OFFSETS(noi), 'bof');
            raw = fread(fid, 32, 'uint8=>double')';
            nul = find(raw == 0, 1);
            if ~isempty(nul) && nul > 1
                cand = strtrim(char(raw(1:nul-1)));
            else
                cand = strtrim(char(raw));
            end
            if numel(cand) >= 3 && all(cand >= ' ' & cand <= '~')
                name_str = cand;
                break;
            end
        end
        if isempty(name_str)
            name_str = sprintf('(ch_%d)', ch_count+1);
        end

        % Units
        units_str = '';
        for uoff = [0x50, 0x58, 0x48, 0x60]
            fseek(fid, current_ptr + uoff, 'bof');
            raw = fread(fid, 12, 'uint8=>double')';
            nul = find(raw == 0, 1);
            if ~isempty(nul) && nul > 1
                cand = strtrim(char(raw(1:nul-1)));
            else
                cand = strtrim(char(raw));
            end
            if numel(cand) >= 1 && all(cand >= ' ' & cand <= '~')
                units_str = cand;
                break;
            end
        end

        % Read first 3 values
        v1 = NaN; v2 = NaN; v3 = NaN;
        if data_ptr > 0 && data_ptr < file_sz && data_len > 0
            fseek(fid, data_ptr, 'bof');
            n_read = min(3, data_len);
            try
                switch datatype
                    case 1
                        raw_u16  = fread(fid, n_read, 'uint16=>double', 0, 'l');
                        phys = float16_to_double(raw_u16);
                    case 2
                        raw_vals = fread(fid, n_read, 'int16=>double', 0, 'l');
                        if ch_scale ~= 0 && ch_mul ~= 0
                            phys = raw_vals .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
                        else
                            phys = raw_vals ./ (10^dec_places) + ch_offset;
                        end
                    case 3
                        raw_vals = fread(fid, n_read, 'int32=>double', 0, 'l');
                        if ch_scale ~= 0 && ch_mul ~= 0
                            phys = raw_vals .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
                        else
                            phys = raw_vals ./ (10^dec_places) + ch_offset;
                        end
                    case 4
                        phys = fread(fid, n_read, 'float32=>double', 0, 'l');
                    otherwise
                        phys = [NaN NaN NaN];
                end
                if numel(phys) >= 1, v1 = phys(1); end
                if numel(phys) >= 2, v2 = phys(2); end
                if numel(phys) >= 3, v3 = phys(3); end
            catch
            end
        end

        fprintf(fout, '%-35s  %-6g %-5d %-7d %-7d %-7d %-7d %-4d  0x%08X  %-10.3f %-10.3f %-10.3f  %s\n', ...
            name_str, sample_rate, datatype, data_len, ...
            ch_offset, ch_mul, ch_scale, dec_places, ...
            data_ptr, v1, v2, v3, units_str);

        ch_count = ch_count + 1;
        current_ptr = next_ptr;
        if ch_count > 2000, break; end
    end

    fclose(fout);
    fprintf('Done. %d channels. Open C:\\temp\\channel_diagnose.txt\n', ch_count);
end


function out = float16_to_double(u16)
    sign = bitshift(bitand(u16, 32768), -15);
    exp  = bitshift(bitand(u16, 31744), -10);
    frac = bitand(u16, 1023);
    out  = zeros(size(u16));
    nm = (exp > 0) & (exp < 31);
    out(nm) = (-1).^sign(nm) .* 2.^(exp(nm)-15) .* (1 + frac(nm)/1024);
    sn = (exp == 0) & (frac ~= 0);
    out(sn) = (-1).^sign(sn) .* 2^-14 .* (frac(sn)/1024);
    out(exp==31 & frac==0) = Inf;
    out(exp==31 & frac~=0) = NaN;
end