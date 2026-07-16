function motec_ld_trace(filepath)
% MOTEC_LD_TRACE  Walk first 10 channel metadata blocks and print everything
% to debug why channels aren't loading.

    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fprintf('File size: 0x%X\n\n', file_sz);

    fseek(fid, 0x0008, 'bof');
    current_ptr = fread(fid, 1, 'uint32', 0, 'l');
    fprintf('Starting at: 0x%X\n\n', current_ptr);

    for i = 1:10
        if current_ptr == 0 || current_ptr >= file_sz
            fprintf('Block %d: ptr=0x%X — stopping (zero or out of range)\n', i, current_ptr);
            break;
        end

        fprintf('=== Block %d at 0x%X ===\n', i, current_ptr);

        % Dump raw 96 bytes of this block
        fseek(fid, current_ptr, 'bof');
        raw = fread(fid, 96, 'uint8')';
        for row = 0:16:numel(raw)-1
            seg  = raw(row+1 : min(row+16, end));
            hexs = sprintf('%02X ', seg);
            hexs = [hexs, repmat('   ', 1, 16-numel(seg))]; %#ok
            asc  = seg; asc(asc<32|asc>126) = uint8('.');
            fprintf('  +0x%02X  %s | %s\n', row, hexs, char(asc));
        end

        % Parse fields
        fseek(fid, current_ptr, 'bof');
        prev_ptr    = fread(fid, 1, 'uint32', 0, 'l');
        next_ptr    = fread(fid, 1, 'uint32', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32', 0, 'l');
        data_len    = fread(fid, 1, 'uint32', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16', 0, 'l');
        unk1        = fread(fid, 1, 'uint16', 0, 'l');
        datatype    = fread(fid, 1, 'uint16', 0, 'l');
        unk2        = fread(fid, 1, 'uint16', 0, 'l');
        ch_offset   = fread(fid, 1, 'int16',  0, 'l');
        ch_mul      = fread(fid, 1, 'int16',  0, 'l');
        ch_scale    = fread(fid, 1, 'int16',  0, 'l');
        dec_places  = fread(fid, 1, 'int16',  0, 'l');

        fseek(fid, current_ptr + 0x20, 'bof');
        name_raw = fread(fid, 32, 'uint8')';
        null_pos = find(name_raw == 0, 1);
        if ~isempty(null_pos), name_raw = name_raw(1:null_pos-1); end
        name_str = char(name_raw);

        fseek(fid, current_ptr + 0x50, 'bof');
        units_raw = fread(fid, 12, 'uint8')';
        null_pos  = find(units_raw == 0, 1);
        if ~isempty(null_pos), units_raw = units_raw(1:null_pos-1); end
        units_str = char(units_raw);

        fprintf('  prev_ptr    = 0x%08X\n', prev_ptr);
        fprintf('  next_ptr    = 0x%08X\n', next_ptr);
        fprintf('  data_ptr    = 0x%08X  (in range: %d)\n', data_ptr, data_ptr > 0 && data_ptr < file_sz);
        fprintf('  data_len    = %d\n', data_len);
        fprintf('  sample_rate = %d Hz\n', sample_rate);
        fprintf('  unk1        = %d\n', unk1);
        fprintf('  datatype    = %d\n', datatype);
        fprintf('  unk2        = %d\n', unk2);
        fprintf('  offset      = %d\n', ch_offset);
        fprintf('  mul         = %d\n', ch_mul);
        fprintf('  scale       = %d\n', ch_scale);
        fprintf('  dec_places  = %d\n', dec_places);
        fprintf('  name        = "%s"\n', name_str);
        fprintf('  units       = "%s"\n', units_str);

        % Check conditions
        fprintf('  >> data_ptr > 0: %d\n', data_ptr > 0);
        fprintf('  >> data_ptr < file_sz: %d\n', data_ptr < file_sz);
        fprintf('  >> data_len > 0: %d\n', data_len > 0);

        % If data looks valid, read first 5 samples
        if data_ptr > 0 && data_ptr < file_sz && data_len > 0
            fseek(fid, data_ptr, 'bof');
            n_preview = min(5, data_len);
            switch datatype
                case 1, preview = fread(fid, n_preview, 'uint16', 0, 'l');
                case 2, preview = fread(fid, n_preview, 'int16',  0, 'l');
                case 3, preview = fread(fid, n_preview, 'int32',  0, 'l');
                case 4, preview = fread(fid, n_preview, 'single', 0, 'l');
                otherwise, preview = [];
            end
            fprintf('  >> First %d raw samples: ', n_preview);
            fprintf('%g ', preview); fprintf('\n');
        end

        fprintf('\n');
        current_ptr = next_ptr;
    end
end
