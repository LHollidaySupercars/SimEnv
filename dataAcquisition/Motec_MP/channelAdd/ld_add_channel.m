% function ld_add_channel(source_ld_file, output_ld_file, new_channels)
% % LD_ADD_CHANNEL  Append new channels to a MoTeC .ld file.
% %
% % Finds a donor channel at the same Hz, copies its 84-byte metadata record
% % verbatim, patches only the fields we own, then stitches it into the
% % linked list. Three separate fopen/fclose passes per channel to avoid
% % Windows r+b seek-then-append reliability issues:
% %
% %   Pass A  patch prev channel's next_ptr        (r+b)  → verified immediately
% %   Pass B  append new metadata record + data    (ab)
% %   Pass C  read back and verify data            (rb)
% %
% % Usage
% % -----
% %   ch.name        = 'Brake Balance VCH';
% %   ch.short_name  = 'BB VCH';   % optional, auto-truncated from name
% %   ch.units       = '%';        % optional
% %   ch.value       = 60;         % scalar (static) or vector (n_samples long)
% %   ch.sample_rate = 5;          % Hz — must match an existing channel in file
% %   ld_add_channel('master.ld', 'output.ld', ch)
% 
%     META_BYTES = 84;
%     FLOAT_TOL  = 1e-3;
% 
%     if isstruct(new_channels)
%         ch_list = num2cell(new_channels);
%     else
%         ch_list = new_channels;
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  1. Copy master → output (byte-exact baseline)
%     % ------------------------------------------------------------------ %
%     fprintf('\n[LD_ADD_CHANNEL] Copying master → output...\n');
%     [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
%     if ~ok, error('copyfile failed: %s', msg); end
%     fprintf('  %s\n\n', output_ld_file);
% 
%     % ------------------------------------------------------------------ %
%     %  2. Walk binary: find last_meta_ptr + build donor map
%     % ------------------------------------------------------------------ %
%     d = dir(output_ld_file);
%     file_sz = d.bytes;
% 
%     [last_meta_ptr, donor_map] = walk_and_collect(output_ld_file, file_sz, META_BYTES);
% 
%     fprintf('  Last channel meta_ptr : 0x%X\n', last_meta_ptr);
%     fprintf('  Donor rates available : %s\n\n', ...
%         strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), 'UniformOutput', false), ', '));
% 
%     % ------------------------------------------------------------------ %
%     %  3. Append each new channel
%     % ------------------------------------------------------------------ %
%     prev_meta_ptr   = last_meta_ptr;
%     current_file_sz = file_sz;
% 
%     for ci = 1:numel(ch_list)
% 
%         ch = ch_list{ci};
%         if ~isfield(ch, 'short_name') || isempty(ch.short_name)
%             ch.short_name = ch.name(1:min(end,7));
%         end
%         if ~isfield(ch, 'units') || isempty(ch.units)
%             ch.units = '';
%         end
% 
%         fprintf('[%d/%d] "%s"  @ %d Hz\n', ci, numel(ch_list), ch.name, ch.sample_rate);
% 
%         % ---- A. Get donor record for this sample rate ----------------
%         if ~isKey(donor_map, ch.sample_rate)
%             error('No donor channel at %d Hz. Available: %s', ch.sample_rate, ...
%                 strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), ...
%                 'UniformOutput', false), ', '));
%         end
%         donor_rec = donor_map(ch.sample_rate);
% 
%         % Extract donor scaling params (for encoding + readback)
%         donor_datatype = double(typecast(uint8(donor_rec(21:22)), 'uint16'));  % +0x14
%         donor_sr       = double(typecast(uint8(donor_rec(23:24)), 'uint16'));  % +0x16
%         donor_offset   = double(typecast(uint8(donor_rec(25:26)), 'int16'));   % +0x18
%         donor_mul      = double(typecast(uint8(donor_rec(27:28)), 'int16'));   % +0x1A
%         donor_scale    = double(typecast(uint8(donor_rec(29:30)), 'int16'));   % +0x1C
%         donor_dec      = double(typecast(uint8(donor_rec(31:32)), 'int16'));   % +0x1E
%         donor_n        = double(typecast(uint8(donor_rec(13:16)), 'uint32'));  % +0x0C
% 
%         fprintf('   Donor: datatype=%d  Hz=%d  mul=%d  scale=%d  dec=%d  offset=%d  n=%d\n', ...
%             donor_datatype, donor_sr, donor_mul, donor_scale, donor_dec, donor_offset, donor_n);
% 
%         % ---- B. Build phys data + encode ----------------------------
%         n = donor_n;
%         if isscalar(ch.value)
%             phys = repmat(double(ch.value), n, 1);
%         else
%             phys = double(ch.value(:));
%             if numel(phys) ~= n
%                 error('value length %d != donor n_samples %d', numel(phys), n);
%             end
%         end
% 
%         raw_bytes = encode_phys(phys, donor_datatype, donor_offset, ...
%                                  donor_mul, donor_scale, donor_dec);
%         fprintf('   Encoded: %d samples  %d bytes\n', n, numel(raw_bytes));
% 
%         % ---- C. Compute pointer positions ---------------------------
%         new_meta_ptr = current_file_sz;
%         new_data_ptr = new_meta_ptr + META_BYTES;
%         fprintf('   new_meta_ptr=0x%X  new_data_ptr=0x%X\n', new_meta_ptr, new_data_ptr);
% 
%         % ---- D. Build metadata record from donor template -----------
%         %  Copy donor verbatim, patch only the 6 fields we own
%         rec = donor_rec;
%         rec(1:4)   = typecast(uint32(prev_meta_ptr), 'uint8');  % prev_ptr
%         rec(5:8)   = typecast(uint32(0),             'uint8');  % next_ptr = 0
%         rec(9:12)  = typecast(uint32(new_data_ptr),  'uint8');  % data_ptr
%         rec(13:16) = typecast(uint32(n),             'uint8');  % data_len
%         rec(33:64) = str_to_bytes(ch.name,       32);           % name
%         rec(65:72) = str_to_bytes(ch.short_name, 8);            % short_name
%         rec(73:84) = str_to_bytes(ch.units,      12);           % units
% 
%         % ---- PASS A: patch prev channel's next_ptr ------------------
%         fid_p = fopen(output_ld_file, 'r+b');
%         if fid_p < 0, error('Cannot open for patch: %s', output_ld_file); end
%         fseek(fid_p, prev_meta_ptr + 4, 'bof');
%         fwrite(fid_p, uint32(new_meta_ptr), 'uint32', 0, 'l');
%         fclose(fid_p);
% 
%         % Verify the patch immediately
%         fid_v = fopen(output_ld_file, 'rb');
%         fseek(fid_v, prev_meta_ptr + 4, 'bof');
%         check = fread(fid_v, 1, 'uint32=>double', 0, 'l');
%         fclose(fid_v);
%         if check ~= new_meta_ptr
%             error('next_ptr patch FAILED: wrote 0x%X but read back 0x%X', new_meta_ptr, check);
%         end
%         fprintf('   Pass A: next_ptr @ 0x%X → 0x%X  [verified]\n', ...
%             prev_meta_ptr + 4, new_meta_ptr);
% 
%         % ---- PASS B: append metadata record + data block ------------
%         fid_a = fopen(output_ld_file, 'ab');
%         if fid_a < 0, error('Cannot open for append: %s', output_ld_file); end
%         nw = fwrite(fid_a, rec, 'uint8');
%         if nw ~= META_BYTES
%             fclose(fid_a);
%             error('Metadata write: %d / %d bytes', nw, META_BYTES);
%         end
%         nw = fwrite(fid_a, raw_bytes, 'uint8');
%         if nw ~= numel(raw_bytes)
%             fclose(fid_a);
%             error('Data write: %d / %d bytes', nw, numel(raw_bytes));
%         end
%         fclose(fid_a);
% 
%         current_file_sz = new_data_ptr + numel(raw_bytes);
%         prev_meta_ptr   = new_meta_ptr;
%         fprintf('   Pass B: appended meta+data  new_file_sz=0x%X\n', current_file_sz);
% 
%         % ---- PASS C: read back and verify data ----------------------
%         [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, ...
%             new_data_ptr, n, donor_datatype, donor_offset, ...
%             donor_mul, donor_scale, donor_dec);
% 
%         if ~rb_ok
%             fprintf('   Pass C: [FAIL] %s\n\n', rb_err);
%         else
%             max_err = max(abs(rb_phys - phys));
%             if max_err > FLOAT_TOL
%                 fprintf('   Pass C: [FAIL] max_err=%.6f\n\n', max_err);
%             else
%                 fprintf('   Pass C: [PASS] max_err=%.2e  value=%.4g\n\n', max_err, rb_phys(1));
%             end
%         end
% 
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  4. Summary
%     % ------------------------------------------------------------------ %
%     d2 = dir(output_ld_file);
%     fprintf('============================================================\n');
%     fprintf('  COMPLETE\n');
%     fprintf('  Channels added : %d\n',   numel(ch_list));
%     fprintf('  Original size  : %d bytes\n', file_sz);
%     fprintf('  New size       : %d bytes\n', d2.bytes);
%     fprintf('  Output         : %s\n',   output_ld_file);
%     fprintf('============================================================\n');
% end
% 
% 
% % ======================================================================= %
% %  WALK AND COLLECT
% % ======================================================================= %
% function [last_meta_ptr, donor_map] = walk_and_collect(filepath, file_sz, META_BYTES) %#ok
% 
%     fid = fopen(filepath, 'rb');
%     if fid < 0, error('Cannot open: %s', filepath); end
%     c = onCleanup(@() fclose(fid));
% 
%     fseek(fid, 0x0008, 'bof');
%     current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
%     if current_ptr == 0 || current_ptr >= file_sz
%         error('Invalid first_meta_ptr: 0x%X', current_ptr);
%     end
% 
%     donor_map     = containers.Map('KeyType', 'double', 'ValueType', 'any');
%     last_meta_ptr = current_ptr;
%     count         = 0;
% 
%     while current_ptr ~= 0 && current_ptr < file_sz
%         fseek(fid, current_ptr, 'bof');
%         rec      = fread(fid, 84, 'uint8=>uint8');
%         next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
%         sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
%         unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
% 
%         % Prefer unk1=0x0003 donors — i2 Pro expects this on standard channels
%         if ~isKey(donor_map, sr)
%             donor_map(sr) = rec;        % first seen = fallback
%         elseif unk1 == 3
%             donor_map(sr) = rec;        % upgrade to unk1=0x0003 if found
%         end
% 
%         last_meta_ptr = current_ptr;
%         current_ptr   = next_ptr;
%         count = count + 1;
%         if count > 5000, warning('5000 channel limit'); break; end
%     end
% 
%     % Report which donor was selected for each Hz
%     hz_list = cell2mat(keys(donor_map));
%     for i = 1:numel(hz_list)
%         d      = donor_map(hz_list(i));
%         d_unk1 = double(typecast(uint8(d(19:20)), 'uint16'));
%         d_name = strtrim(char(d(33:64)'));
%         nul    = find(d_name==0,1);
%         if ~isempty(nul), d_name = d_name(1:nul-1); end
%         fprintf('  Donor Hz=%-4d  unk1=0x%04X  name=%s\n', hz_list(i), d_unk1, d_name);
%     end
% 
%     fprintf('  Walked %d channels.\n', count);
% end
% 
% 
% % ======================================================================= %
% %  ENCODE PHYS → RAW BYTES
% % ======================================================================= %
% function raw_bytes = encode_phys(phys, datatype, offset, mul, scale, dec)
%     phys_d = double(phys(:));
%     switch datatype
%         case 1
%             u16       = double_to_float16(phys_d);
%             raw_bytes = typecast(uint16(u16(:)), 'uint8');
%         case 2
%             if scale ~= 0 && mul ~= 0
%                 raw_d = (phys_d - offset) .* (10^dec) .* (scale / mul);
%             else
%                 raw_d = (phys_d - offset) .* (10^dec);
%             end
%             raw_bytes = typecast(int16(round(raw_d)), 'uint8');
%         case 3
%             if scale ~= 0 && mul ~= 0
%                 raw_d = (phys_d - offset) .* (10^dec) .* (scale / mul);
%             else
%                 raw_d = (phys_d - offset) .* (10^dec);
%             end
%             raw_bytes = typecast(int32(round(raw_d)), 'uint8');
%         case 4
%             raw_d     = round((phys_d - offset) .* (10^dec));
%             i16       = int16(raw_d);
%             n         = numel(i16);
%             i16_b     = reshape(typecast(i16, 'uint8'), 2, n);
%             pad_b     = zeros(2, n, 'uint8');
%             raw_bytes = [i16_b; pad_b];
%         otherwise
%             error('Unsupported datatype %d', datatype);
%     end
%     raw_bytes = raw_bytes(:);
% end
% 
% 
% % ======================================================================= %
% %  READ BACK ONE CHANNEL
% % ======================================================================= %
% function [phys, ok, err] = readback_channel(filepath, data_ptr, n, ...
%         datatype, offset, mul, scale, dec)
%     phys = []; ok = false; err = '';
%     try
%         fid = fopen(filepath, 'rb');
%         if fid < 0, err = 'cannot open'; return; end
%         c = onCleanup(@() fclose(fid));
%         fseek(fid, data_ptr, 'bof');
%         switch datatype
%             case 1
%                 u16  = fread(fid, n, 'uint16=>double', 0, 'l');
%                 phys = float16_to_double(u16);
%             case 2
%                 raw  = fread(fid, n, 'int16=>double', 0, 'l');
%                 if scale ~= 0 && mul ~= 0
%                     phys = raw .* (mul/scale) ./ (10^dec) + offset;
%                 else
%                     phys = raw ./ (10^dec) + offset;
%                 end
%             case 3
%                 raw  = fread(fid, n, 'int32=>double', 0, 'l');
%                 if scale ~= 0 && mul ~= 0
%                     phys = raw .* (mul/scale) ./ (10^dec) + offset;
%                 else
%                     phys = raw ./ (10^dec) + offset;
%                 end
%             case 4
%                 raw  = fread(fid, n, 'int16=>double', 2, 'l');
%                 phys = raw ./ (10^dec) + offset;
%             otherwise
%                 err = sprintf('unknown datatype %d', datatype); return;
%         end
%         ok = true;
%     catch ME
%         err = ME.message;
%     end
% end
% 
% 
% % ======================================================================= %
% %  HELPERS
% % ======================================================================= %
% 
% function b = str_to_bytes(str, n)
%     b = zeros(1, n, 'uint8');
%     bytes = uint8(str(1:min(end, n)));
%     b(1:numel(bytes)) = bytes;
% end
% 
% function u16 = double_to_float16(x)
%     x=double(x(:)); u16=zeros(size(x),'uint16'); sgn=uint16(x<0); ax=abs(x);
%     nm=isnan(ax); u16(nm)=uint16(32767);
%     im=isinf(ax); u16(im)=bitor(bitshift(sgn(im),15),uint16(31744));
%     zm=(ax==0)&~nm&~im; u16(zm)=bitshift(sgn(zm),15);
%     fin=~nm&~im&~zm;
%     if any(fin)
%         xf=ax(fin); sf=sgn(fin); e=floor(log2(xf)); eb=e+15;
%         u=zeros(sum(fin),1,'uint16');
%         ov=eb>=31; u(ov)=bitor(bitshift(sf(ov),15),uint16(31744));
%         uv=(eb<=0)&~ov;
%         if any(uv)
%             fs=uint16(min(max(round(xf(uv)./2^(-14).*1024),0),1023));
%             u(uv)=bitor(bitshift(sf(uv),15),fs);
%         end
%         nr=~ov&~uv;
%         if any(nr)
%             en=eb(nr);
%             fn=uint16(min(max(round((xf(nr)./2.^e(nr)-1).*1024),0),1023));
%             u(nr)=bitor(bitor(bitshift(sf(nr),15),bitshift(uint16(en),10)),fn);
%         end
%         u16(fin)=u;
%     end
% end
% 
% function out = float16_to_double(u16)
%     sign=bitshift(bitand(u16,32768),-15); ex=bitshift(bitand(u16,31744),-10);
%     frac=bitand(u16,1023); out=zeros(size(u16));
%     nm=(ex>0)&(ex<31); out(nm)=(-1).^sign(nm).*2.^(ex(nm)-15).*(1+frac(nm)/1024);
%     sn=(ex==0)&(frac~=0); out(sn)=(-1).^sign(sn).*2^-14.*(frac(sn)/1024);
%     out(ex==31&frac==0)=Inf.*(-1).^sign(ex==31&frac==0);
%     out(ex==31&frac~=0)=NaN;
% end

% function ld_add_channel(source_ld_file, output_ld_file, new_channels)
% % LD_ADD_CHANNEL  Append new channels to a MoTeC .ld file.
% %
% % Finds a donor channel at the same Hz, copies its 84-byte metadata record
% % verbatim, patches only the fields we own, then stitches it into the
% % linked list. Three separate fopen/fclose passes per channel to avoid
% % Windows r+b seek-then-append reliability issues:
% %
% %   Pass A  patch prev channel's next_ptr        (r+b)  → verified immediately
% %   Pass B  append new metadata record + data    (ab)
% %   Pass C  read back and verify data            (rb)
% %
% % Usage
% % -----
% %   ch.name        = 'Brake Balance VCH';
% %   ch.short_name  = 'BB VCH';   % optional, auto-truncated from name
% %   ch.units       = '%';        % optional
% %   ch.value       = 60;         % scalar (static) or vector (n_samples long)
% %   ch.sample_rate = 5;          % Hz — must match an existing channel in file
% %   ld_add_channel('master.ld', 'output.ld', ch)
% 
%     META_BYTES = 84;
%     FLOAT_TOL  = 1e-3;
% 
%     if isstruct(new_channels)
%         ch_list = num2cell(new_channels);
%     else
%         ch_list = new_channels;
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  1. Copy master → output (byte-exact baseline)
%     % ------------------------------------------------------------------ %
%     fprintf('\n[LD_ADD_CHANNEL] Copying master → output...\n');
%     [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
%     if ~ok, error('copyfile failed: %s', msg); end
%     fprintf('  %s\n\n', output_ld_file);
% 
%     % ------------------------------------------------------------------ %
%     %  2. Walk binary: find last_meta_ptr + build donor map
%     % ------------------------------------------------------------------ %
%     d = dir(output_ld_file);
%     file_sz = d.bytes;
% 
%     [last_meta_ptr, donor_map, session_dur] = walk_and_collect(output_ld_file, file_sz, META_BYTES);
%     fprintf('  Session duration  : %.1f s\n', session_dur);
% 
%     fprintf('  Last channel meta_ptr : 0x%X\n', last_meta_ptr);
%     fprintf('  Donor rates available : %s\n\n', ...
%         strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), 'UniformOutput', false), ', '));
% 
%     % ------------------------------------------------------------------ %
%     %  3. Append each new channel
%     % ------------------------------------------------------------------ %
%     prev_meta_ptr   = last_meta_ptr;
%     current_file_sz = file_sz;
% 
%     for ci = 1:numel(ch_list)
% 
%         ch = ch_list{ci};
%         if ~isfield(ch, 'short_name') || isempty(ch.short_name)
%             ch.short_name = ch.name(1:min(end,7));
%         end
%         if ~isfield(ch, 'units') || isempty(ch.units)
%             ch.units = '';
%         end
% 
%         fprintf('[%d/%d] "%s"  @ %d Hz\n', ci, numel(ch_list), ch.name, ch.sample_rate);
% 
%         % ---- A. Get donor record for this sample rate ----------------
%         if ~isKey(donor_map, ch.sample_rate)
%             fprintf('   No donor at %d Hz — building synthetic record.\n', ch.sample_rate);
%             donor_rec = build_synthetic_donor(ch.sample_rate, session_dur);
%         else
%             donor_rec = donor_map(ch.sample_rate);
%         end
% 
%         % Extract donor scaling params (for encoding + readback)
%         donor_datatype = double(typecast(uint8(donor_rec(21:22)), 'uint16'));  % +0x14
%         donor_sr       = double(typecast(uint8(donor_rec(23:24)), 'uint16'));  % +0x16
%         donor_offset   = double(typecast(uint8(donor_rec(25:26)), 'int16'));   % +0x18
%         donor_mul      = double(typecast(uint8(donor_rec(27:28)), 'int16'));   % +0x1A
%         donor_scale    = double(typecast(uint8(donor_rec(29:30)), 'int16'));   % +0x1C
%         donor_dec      = double(typecast(uint8(donor_rec(31:32)), 'int16'));   % +0x1E
%         donor_n        = double(typecast(uint8(donor_rec(13:16)), 'uint32'));  % +0x0C
% 
%         fprintf('   Donor: datatype=%d  Hz=%d  mul=%d  scale=%d  dec=%d  offset=%d  n=%d\n', ...
%             donor_datatype, donor_sr, donor_mul, donor_scale, donor_dec, donor_offset, donor_n);
% 
%         % ---- B. Build phys data + encode ----------------------------
%         n = donor_n;
%         if isscalar(ch.value)
%             phys = repmat(double(ch.value), n, 1);
%         else
%             phys = double(ch.value(:));
%             if numel(phys) ~= n
%                 error('value length %d != donor n_samples %d', numel(phys), n);
%             end
%         end
% 
%         raw_bytes = encode_phys(phys, donor_datatype, donor_offset, ...
%                                  donor_mul, donor_scale, donor_dec);
%         fprintf('   Encoded: %d samples  %d bytes\n', n, numel(raw_bytes));
% 
%         % ---- C. Compute pointer positions ---------------------------
%         new_meta_ptr = current_file_sz;
%         new_data_ptr = new_meta_ptr + META_BYTES;
%         fprintf('   new_meta_ptr=0x%X  new_data_ptr=0x%X\n', new_meta_ptr, new_data_ptr);
% 
%         % ---- D. Build metadata record from donor template -----------
%         %  Copy donor verbatim, patch only the 6 fields we own
%         rec = donor_rec;
%         rec(1:4)   = typecast(uint32(prev_meta_ptr), 'uint8');  % prev_ptr
%         rec(5:8)   = typecast(uint32(0),             'uint8');  % next_ptr = 0
%         rec(9:12)  = typecast(uint32(new_data_ptr),  'uint8');  % data_ptr
%         rec(13:16) = typecast(uint32(n),             'uint8');  % data_len
%         rec(33:64) = str_to_bytes(ch.name,       32);           % name
%         rec(65:72) = str_to_bytes(ch.short_name, 8);            % short_name
%         rec(73:84) = str_to_bytes(ch.units,      12);           % units
% 
%         % ---- PASS A: patch prev channel's next_ptr ------------------
%         fid_p = fopen(output_ld_file, 'r+b');
%         if fid_p < 0, error('Cannot open for patch: %s', output_ld_file); end
%         fseek(fid_p, prev_meta_ptr + 4, 'bof');
%         fwrite(fid_p, uint32(new_meta_ptr), 'uint32', 0, 'l');
%         fclose(fid_p);
% 
%         % Verify the patch immediately
%         fid_v = fopen(output_ld_file, 'rb');
%         fseek(fid_v, prev_meta_ptr + 4, 'bof');
%         check = fread(fid_v, 1, 'uint32=>double', 0, 'l');
%         fclose(fid_v);
%         if check ~= new_meta_ptr
%             error('next_ptr patch FAILED: wrote 0x%X but read back 0x%X', new_meta_ptr, check);
%         end
%         fprintf('   Pass A: next_ptr @ 0x%X → 0x%X  [verified]\n', ...
%             prev_meta_ptr + 4, new_meta_ptr);
% 
%         % ---- PASS B: append metadata record + data block ------------
%         fid_a = fopen(output_ld_file, 'ab');
%         if fid_a < 0, error('Cannot open for append: %s', output_ld_file); end
%         nw = fwrite(fid_a, rec, 'uint8');
%         if nw ~= META_BYTES
%             fclose(fid_a);
%             error('Metadata write: %d / %d bytes', nw, META_BYTES);
%         end
%         nw = fwrite(fid_a, raw_bytes, 'uint8');
%         if nw ~= numel(raw_bytes)
%             fclose(fid_a);
%             error('Data write: %d / %d bytes', nw, numel(raw_bytes));
%         end
%         fclose(fid_a);
% 
%         current_file_sz = new_data_ptr + numel(raw_bytes);
%         prev_meta_ptr   = new_meta_ptr;
%         fprintf('   Pass B: appended meta+data  new_file_sz=0x%X\n', current_file_sz);
% 
%         % ---- PASS C: read back and verify data ----------------------
%         [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, ...
%             new_data_ptr, n, donor_datatype, donor_offset, ...
%             donor_mul, donor_scale, donor_dec);
% 
%         if ~rb_ok
%             fprintf('   Pass C: [FAIL] %s\n\n', rb_err);
%         else
%             max_err = max(abs(rb_phys - phys));
%             if max_err > FLOAT_TOL
%                 fprintf('   Pass C: [FAIL] max_err=%.6f\n\n', max_err);
%             else
%                 fprintf('   Pass C: [PASS] max_err=%.2e  value=%.4g\n\n', max_err, rb_phys(1));
%             end
%         end
% 
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  4. Summary
%     % ------------------------------------------------------------------ %
%     d2 = dir(output_ld_file);
%     fprintf('============================================================\n');
%     fprintf('  COMPLETE\n');
%     fprintf('  Channels added : %d\n',   numel(ch_list));
%     fprintf('  Original size  : %d bytes\n', file_sz);
%     fprintf('  New size       : %d bytes\n', d2.bytes);
%     fprintf('  Output         : %s\n',   output_ld_file);
%     fprintf('============================================================\n');
% end
% 
% 
% % ======================================================================= %
% %  WALK AND COLLECT
% % ======================================================================= %
% function [last_meta_ptr, donor_map, session_dur] = walk_and_collect(filepath, file_sz, META_BYTES) %#ok
% 
%     fid = fopen(filepath, 'rb');
%     if fid < 0, error('Cannot open: %s', filepath); end
%     c = onCleanup(@() fclose(fid));
% 
%     fseek(fid, 0x0008, 'bof');
%     current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
%     if current_ptr == 0 || current_ptr >= file_sz
%         error('Invalid first_meta_ptr: 0x%X', current_ptr);
%     end
% 
%     donor_map     = containers.Map('KeyType', 'double', 'ValueType', 'any');
%     last_meta_ptr = current_ptr;
%     session_dur   = 0;   % seconds, computed from first channel
%     count         = 0;
% 
%     while current_ptr ~= 0 && current_ptr < file_sz
%         fseek(fid, current_ptr, 'bof');
%         rec      = fread(fid, 84, 'uint8=>uint8');
%         next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
%         sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
%         unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
% 
%         % Compute session duration from first channel seen
%         if session_dur == 0 && sr > 0
%             ch_n        = double(typecast(uint8(rec(13:16)), 'uint32'));
%             session_dur = ch_n / sr;
%         end
% 
%         % Prefer unk1=0x0003 donors — i2 Pro expects this on standard channels
%         if ~isKey(donor_map, sr)
%             donor_map(sr) = rec;        % first seen = fallback
%         elseif unk1 == 3
%             donor_map(sr) = rec;        % upgrade to unk1=0x0003 if found
%         end
% 
%         last_meta_ptr = current_ptr;
%         current_ptr   = next_ptr;
%         count = count + 1;
%         if count > 5000, warning('5000 channel limit'); break; end
%     end
% 
%     % Report which donor was selected for each Hz
%     hz_list = cell2mat(keys(donor_map));
%     for i = 1:numel(hz_list)
%         d      = donor_map(hz_list(i));
%         d_unk1 = double(typecast(uint8(d(19:20)), 'uint16'));
%         d_name = strtrim(char(d(33:64)'));
%         nul    = find(d_name==0,1);
%         if ~isempty(nul), d_name = d_name(1:nul-1); end
%         fprintf('  Donor Hz=%-4d  unk1=0x%04X  name=%s\n', hz_list(i), d_unk1, d_name);
%     end
% 
%     fprintf('  Walked %d channels.\n', count);
% end
% 
% 
% % ======================================================================= %
% %  BUILD SYNTHETIC DONOR
% %  Constructs an 84-byte metadata record for a Hz value not in the file.
% %  Uses confirmed field values from MoTeC export analysis:
% %    unk1     = 0x0003  (standard channel flag)
% %    datatype = 2       (int16)
% %    mul=1  scale=1  dec=0  offset=0  (integer physical values)
% %    sr_raw   = 0       (unknown formula — i2 appears to tolerate 0)
% %    short_name = zeros (confirmed from MoTeC export)
% % ======================================================================= %
% function rec = build_synthetic_donor(sample_rate, session_dur)
%     n_samples = round(session_dur * sample_rate);
%     rec = zeros(1, 84, 'uint8');
%     % prev_ptr, next_ptr, data_ptr = 0 (will be overwritten by caller)
%     rec(13:16) = typecast(uint32(n_samples), 'uint8');   % data_len
%     rec(17:18) = typecast(uint16(0),         'uint8');   % sr_raw = 0
%     rec(19:20) = typecast(uint16(3),         'uint8');   % unk1   = 0x0003
%     rec(21:22) = typecast(uint16(2),         'uint8');   % datatype = int16
%     rec(23:24) = typecast(uint16(sample_rate),'uint8');  % sample_rate
%     rec(25:26) = typecast(int16(0),          'uint8');   % offset = 0
%     rec(27:28) = typecast(int16(1),          'uint8');   % mul    = 1
%     rec(29:30) = typecast(int16(1),          'uint8');   % scale  = 1
%     rec(31:32) = typecast(int16(0),          'uint8');   % dec    = 0
%     % name/short/units left as zeros — caller will overwrite
%     fprintf('   Synthetic donor: Hz=%d  n_samples=%d\n', sample_rate, n_samples);
% end
% 
% 
% % ======================================================================= %
% %  ENCODE PHYS → RAW BYTES
% % ======================================================================= %
% function raw_bytes = encode_phys(phys, datatype, offset, mul, scale, dec)
%     phys_d = double(phys(:));
%     switch datatype
%         case 1
%             u16       = double_to_float16(phys_d);
%             raw_bytes = typecast(uint16(u16(:)), 'uint8');
%         case 2
%             if scale ~= 0 && mul ~= 0
%                 raw_d = (phys_d - offset) .* (10^dec) .* (scale / mul);
%             else
%                 raw_d = (phys_d - offset) .* (10^dec);
%             end
%             raw_bytes = typecast(int16(round(raw_d)), 'uint8');
%         case 3
%             if scale ~= 0 && mul ~= 0
%                 raw_d = (phys_d - offset) .* (10^dec) .* (scale / mul);
%             else
%                 raw_d = (phys_d - offset) .* (10^dec);
%             end
%             raw_bytes = typecast(int32(round(raw_d)), 'uint8');
%         case 4
%             raw_d     = round((phys_d - offset) .* (10^dec));
%             i16       = int16(raw_d);
%             n         = numel(i16);
%             i16_b     = reshape(typecast(i16, 'uint8'), 2, n);
%             pad_b     = zeros(2, n, 'uint8');
%             raw_bytes = [i16_b; pad_b];
%         otherwise
%             error('Unsupported datatype %d', datatype);
%     end
%     raw_bytes = raw_bytes(:);
% end
% 
% 
% % ======================================================================= %
% %  READ BACK ONE CHANNEL
% % ======================================================================= %
% function [phys, ok, err] = readback_channel(filepath, data_ptr, n, ...
%         datatype, offset, mul, scale, dec)
%     phys = []; ok = false; err = '';
%     try
%         fid = fopen(filepath, 'rb');
%         if fid < 0, err = 'cannot open'; return; end
%         c = onCleanup(@() fclose(fid));
%         fseek(fid, data_ptr, 'bof');
%         switch datatype
%             case 1
%                 u16  = fread(fid, n, 'uint16=>double', 0, 'l');
%                 phys = float16_to_double(u16);
%             case 2
%                 raw  = fread(fid, n, 'int16=>double', 0, 'l');
%                 if scale ~= 0 && mul ~= 0
%                     phys = raw .* (mul/scale) ./ (10^dec) + offset;
%                 else
%                     phys = raw ./ (10^dec) + offset;
%                 end
%             case 3
%                 raw  = fread(fid, n, 'int32=>double', 0, 'l');
%                 if scale ~= 0 && mul ~= 0
%                     phys = raw .* (mul/scale) ./ (10^dec) + offset;
%                 else
%                     phys = raw ./ (10^dec) + offset;
%                 end
%             case 4
%                 raw  = fread(fid, n, 'int16=>double', 2, 'l');
%                 phys = raw ./ (10^dec) + offset;
%             otherwise
%                 err = sprintf('unknown datatype %d', datatype); return;
%         end
%         ok = true;
%     catch ME
%         err = ME.message;
%     end
% end
% 
% 
% % ======================================================================= %
% %  HELPERS
% % ======================================================================= %
% 
% function b = str_to_bytes(str, n)
%     b = zeros(1, n, 'uint8');
%     bytes = uint8(str(1:min(end, n)));
%     b(1:numel(bytes)) = bytes;
% end
% 
% function u16 = double_to_float16(x)
%     x=double(x(:)); u16=zeros(size(x),'uint16'); sgn=uint16(x<0); ax=abs(x);
%     nm=isnan(ax); u16(nm)=uint16(32767);
%     im=isinf(ax); u16(im)=bitor(bitshift(sgn(im),15),uint16(31744));
%     zm=(ax==0)&~nm&~im; u16(zm)=bitshift(sgn(zm),15);
%     fin=~nm&~im&~zm;
%     if any(fin)
%         xf=ax(fin); sf=sgn(fin); e=floor(log2(xf)); eb=e+15;
%         u=zeros(sum(fin),1,'uint16');
%         ov=eb>=31; u(ov)=bitor(bitshift(sf(ov),15),uint16(31744));
%         uv=(eb<=0)&~ov;
%         if any(uv)
%             fs=uint16(min(max(round(xf(uv)./2^(-14).*1024),0),1023));
%             u(uv)=bitor(bitshift(sf(uv),15),fs);
%         end
%         nr=~ov&~uv;
%         if any(nr)
%             en=eb(nr);
%             fn=uint16(min(max(round((xf(nr)./2.^e(nr)-1).*1024),0),1023));
%             u(nr)=bitor(bitor(bitshift(sf(nr),15),bitshift(uint16(en),10)),fn);
%         end
%         u16(fin)=u;
%     end
% end
% 
% function out = float16_to_double(u16)
%     sign=bitshift(bitand(u16,32768),-15); ex=bitshift(bitand(u16,31744),-10);
%     frac=bitand(u16,1023); out=zeros(size(u16));
%     nm=(ex>0)&(ex<31); out(nm)=(-1).^sign(nm).*2.^(ex(nm)-15).*(1+frac(nm)/1024);
%     sn=(ex==0)&(frac~=0); out(sn)=(-1).^sign(sn).*2^-14.*(frac(sn)/1024);
%     out(ex==31&frac==0)=Inf.*(-1).^sign(ex==31&frac==0);
%     out(ex==31&frac~=0)=NaN;
% end

function ld_add_channel(source_ld_file, output_ld_file, new_channels)
% LD_ADD_CHANNEL  Append new channels to a MoTeC .ld file.
%
% Finds a donor channel at the same Hz, copies its 84-byte metadata record
% verbatim, patches only the fields we own, then stitches into the linked list.
%
% If no donor exists at the requested Hz, a synthetic record is built using
% the nearest known donor's sr_raw value (required by i2 Pro).
%
% Three separate fopen/fclose passes per channel (Windows r+b reliability):
%   Pass A  patch prev channel's next_ptr   (r+b) — verified immediately
%   Pass B  append metadata record + data   (ab)
%   Pass C  read back and verify            (rb)
%
% Usage
% -----
%   ch.name        = 'Brake Balance VCH';
%   ch.short_name  = 'BB VCH';    % optional
%   ch.units       = '%';         % optional
%   ch.value       = 60;          % scalar or vector
%   ch.sample_rate = 5;           % Hz
%   ld_add_channel('master.ld', 'output.ld', ch)

    META_BYTES = 84;
    FLOAT_TOL  = 1e-3;

    if isstruct(new_channels)
        ch_list = num2cell(new_channels);
    else
        ch_list = new_channels;
    end

    % ------------------------------------------------------------------ %
    %  1. Copy master → output
    % ------------------------------------------------------------------ %
    fprintf('\n[LD_ADD_CHANNEL] Copying master → output...\n');
    [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
    if ~ok, error('copyfile failed: %s', msg); end
    fprintf('  %s\n\n', output_ld_file);

    % ------------------------------------------------------------------ %
    %  2. Walk binary — build donor map + get session duration
    % ------------------------------------------------------------------ %
    d = dir(output_ld_file);
    file_sz = d.bytes;

    [last_meta_ptr, donor_map, session_dur] = walk_and_collect(output_ld_file, file_sz, META_BYTES);

    fprintf('  Session duration      : %.1f s\n', session_dur);
    fprintf('  Last channel meta_ptr : 0x%X\n',   last_meta_ptr);
    fprintf('  Donor rates available : %s\n\n', ...
        strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), 'UniformOutput', false), ', '));

    % ------------------------------------------------------------------ %
    %  3. Append each new channel
    % ------------------------------------------------------------------ %
    prev_meta_ptr   = last_meta_ptr;
    current_file_sz = file_sz;

    for ci = 1:numel(ch_list)

        ch = ch_list{ci};
        if ~isfield(ch, 'short_name') || isempty(ch.short_name)
            ch.short_name = ch.name(1:min(end,7));
        end
        if ~isfield(ch, 'units') || isempty(ch.units)
            ch.units = '';
        end

        fprintf('[%d/%d] "%s"  @ %d Hz\n', ci, numel(ch_list), ch.name, ch.sample_rate);

        % ---- A. Get or build donor record ---------------------------
        if isKey(donor_map, ch.sample_rate)
            donor_rec = donor_map(ch.sample_rate);
            fprintf('   Donor: existing channel at %d Hz\n', ch.sample_rate);
        else
            fprintf('   Donor: none at %d Hz — building synthetic\n', ch.sample_rate);
            donor_rec = build_synthetic_donor(ch.sample_rate, session_dur, donor_map);
        end

        % Extract donor fields
        donor_datatype = double(typecast(uint8(donor_rec(21:22)), 'uint16'));
        donor_sr       = double(typecast(uint8(donor_rec(23:24)), 'uint16'));
        donor_offset   = double(typecast(uint8(donor_rec(25:26)), 'int16'));
        donor_mul      = double(typecast(uint8(donor_rec(27:28)), 'int16'));
        donor_scale    = double(typecast(uint8(donor_rec(29:30)), 'int16'));
        donor_dec      = double(typecast(uint8(donor_rec(31:32)), 'int16'));
        donor_n        = double(typecast(uint8(donor_rec(13:16)), 'uint32'));
        donor_sr_raw   = double(typecast(uint8(donor_rec(17:18)), 'uint16'));

        fprintf('   datatype=%d  Hz=%d  sr_raw=%d  mul=%d  scale=%d  dec=%d  offset=%d  n=%d\n', ...
            donor_datatype, donor_sr, donor_sr_raw, donor_mul, donor_scale, ...
            donor_dec, donor_offset, donor_n);

        % ---- B. Build phys data + encode ----------------------------
        n = donor_n;
        if isscalar(ch.value)
            phys = repmat(double(ch.value), n, 1);
        else
            phys = double(ch.value(:));
            if numel(phys) ~= n
                error('value length %d != donor n_samples %d', numel(phys), n);
            end
        end

        raw_bytes = encode_phys(phys, donor_datatype, donor_offset, ...
                                 donor_mul, donor_scale, donor_dec);
        fprintf('   Encoded: %d samples  %d bytes\n', n, numel(raw_bytes));

        % ---- C. Compute pointer positions ---------------------------
        new_meta_ptr = current_file_sz;
        new_data_ptr = new_meta_ptr + META_BYTES;
        fprintf('   new_meta_ptr=0x%X  new_data_ptr=0x%X\n', new_meta_ptr, new_data_ptr);

        % ---- D. Build metadata record from donor template -----------
        rec = donor_rec;
        rec(1:4)   = typecast(uint32(prev_meta_ptr), 'uint8');  % prev_ptr
        rec(5:8)   = typecast(uint32(0),             'uint8');  % next_ptr = 0
        rec(9:12)  = typecast(uint32(new_data_ptr),  'uint8');  % data_ptr
        rec(13:16) = typecast(uint32(n),             'uint8');  % data_len
        rec(23:24) = typecast(uint16(ch.sample_rate),'uint8');  % sample_rate (true Hz)
        rec(33:64) = str_to_bytes(ch.name,       32);
        rec(65:72) = str_to_bytes(ch.short_name, 8);
        rec(73:84) = str_to_bytes(ch.units,      12);

        % ---- PASS A: patch prev channel's next_ptr ------------------
        fid_p = fopen(output_ld_file, 'r+b');
        if fid_p < 0, error('Cannot open for patch: %s', output_ld_file); end
        fseek(fid_p, prev_meta_ptr + 4, 'bof');
        fwrite(fid_p, uint32(new_meta_ptr), 'uint32', 0, 'l');
        fclose(fid_p);

        fid_v = fopen(output_ld_file, 'rb');
        fseek(fid_v, prev_meta_ptr + 4, 'bof');
        check = fread(fid_v, 1, 'uint32=>double', 0, 'l');
        fclose(fid_v);
        if check ~= new_meta_ptr
            error('next_ptr patch FAILED: wrote 0x%X read 0x%X', new_meta_ptr, check);
        end
        fprintf('   Pass A: next_ptr → 0x%X  [verified]\n', new_meta_ptr);

        % ---- PASS B: append metadata record + data ------------------
        fid_a = fopen(output_ld_file, 'ab');
        if fid_a < 0, error('Cannot open for append: %s', output_ld_file); end
        nw = fwrite(fid_a, rec, 'uint8');
        if nw ~= META_BYTES
            fclose(fid_a);
            error('Metadata write: %d / %d bytes', nw, META_BYTES);
        end
        nw = fwrite(fid_a, raw_bytes, 'uint8');
        if nw ~= numel(raw_bytes)
            fclose(fid_a);
            error('Data write: %d / %d bytes', nw, numel(raw_bytes));
        end
        fclose(fid_a);

        current_file_sz = new_data_ptr + numel(raw_bytes);
        prev_meta_ptr   = new_meta_ptr;
        fprintf('   Pass B: appended  new_file_sz=0x%X\n', current_file_sz);

        % ---- PASS C: read back and verify ---------------------------
        [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, ...
            new_data_ptr, n, donor_datatype, donor_offset, ...
            donor_mul, donor_scale, donor_dec);

        if ~rb_ok
            fprintf('   Pass C: [FAIL] %s\n\n', rb_err);
        else
            max_err = max(abs(rb_phys - phys));
            if max_err > FLOAT_TOL
                fprintf('   Pass C: [FAIL] max_err=%.6f\n\n', max_err);
            else
                fprintf('   Pass C: [PASS] max_err=%.2e  value=%.4g\n\n', max_err, rb_phys(1));
            end
        end

    end

    % ------------------------------------------------------------------ %
    %  4. Summary
    % ------------------------------------------------------------------ %
    d2 = dir(output_ld_file);
    fprintf('============================================================\n');
    fprintf('  COMPLETE\n');
    fprintf('  Channels added : %d\n',       numel(ch_list));
    fprintf('  Original size  : %d bytes\n', file_sz);
    fprintf('  New size       : %d bytes\n', d2.bytes);
    fprintf('  Output         : %s\n',       output_ld_file);
    fprintf('============================================================\n');
end


% ======================================================================= %
%  WALK AND COLLECT
% ======================================================================= %
function [last_meta_ptr, donor_map, session_dur] = walk_and_collect(filepath, file_sz, META_BYTES) %#ok

    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if current_ptr == 0 || current_ptr >= file_sz
        error('Invalid first_meta_ptr: 0x%X', current_ptr);
    end

    donor_map     = containers.Map('KeyType', 'double', 'ValueType', 'any');
    last_meta_ptr = current_ptr;
    session_dur   = 0;
    count         = 0;

    while current_ptr ~= 0 && current_ptr < file_sz
        fseek(fid, current_ptr, 'bof');
        rec      = fread(fid, 84, 'uint8=>uint8');
        next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
        sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
        unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
        ch_n     = double(typecast(uint8(rec(13:16)), 'uint32'));

        % Compute session duration from first valid channel
        if session_dur == 0 && sr > 0 && ch_n > 0
            session_dur = ch_n / sr;
        end

        % Prefer unk1=0x0003 donors — i2 Pro standard channel flag
        if ~isKey(donor_map, sr)
            donor_map(sr) = rec;        % first seen = fallback
        elseif unk1 == 3
            donor_map(sr) = rec;        % upgrade to unk1=0x0003 if found
        end

        last_meta_ptr = current_ptr;
        current_ptr   = next_ptr;
        count = count + 1;
        if count > 5000, warning('5000 channel limit'); break; end
    end

    % Report donors selected
    hz_list = cell2mat(keys(donor_map));
    for i = 1:numel(hz_list)
        d      = donor_map(hz_list(i));
        d_unk1 = double(typecast(uint8(d(19:20)), 'uint16'));
        d_name = strtrim(char(d(33:64)'));
        nul    = find(d_name==0,1);
        if ~isempty(nul), d_name = d_name(1:nul-1); end
        fprintf('  Donor Hz=%-4d  unk1=0x%04X  name=%s\n', hz_list(i), d_unk1, d_name);
    end
    fprintf('  Walked %d channels.\n', count);
end


% ======================================================================= %
%  BUILD SYNTHETIC DONOR
%  For Hz values not present in the file.
%  Borrows sr_raw from the nearest known donor — i2 Pro requires non-zero.
% ======================================================================= %
function rec = build_synthetic_donor(sample_rate, session_dur, donor_map)

    % Borrow sr_raw from nearest known Hz donor
    known_hz    = cell2mat(keys(donor_map));
    [~, idx]    = min(abs(known_hz - sample_rate));
    near_donor  = donor_map(known_hz(idx));
    near_sr_raw = double(typecast(uint8(near_donor(17:18)), 'uint16'));

    n_samples = round(session_dur * sample_rate);

    rec = zeros(1, 84, 'uint8');
    % bytes 1-12: prev/next/data ptrs — overwritten by caller
    rec(13:16) = typecast(uint32(n_samples),  'uint8');   % data_len
    rec(17:18) = typecast(uint16(near_sr_raw),'uint8');   % sr_raw from nearest donor
    rec(19:20) = typecast(uint16(3),          'uint8');   % unk1 = 0x0003
    rec(21:22) = typecast(uint16(2),          'uint8');   % datatype = int16
    rec(23:24) = typecast(uint16(sample_rate),'uint8');   % sample_rate
    rec(25:26) = typecast(int16(0),           'uint8');   % offset = 0
    rec(27:28) = typecast(int16(1),           'uint8');   % mul    = 1
    rec(29:30) = typecast(int16(1),           'uint8');   % scale  = 1
    rec(31:32) = typecast(int16(0),           'uint8');   % dec    = 0
    % bytes 33-84: name/short/units — overwritten by caller

    fprintf('   Synthetic: Hz=%d  n=%d  sr_raw=%d (borrowed from %dHz)\n', ...
        sample_rate, n_samples, near_sr_raw, known_hz(idx));
end


% ======================================================================= %
%  ENCODE PHYS → RAW BYTES
% ======================================================================= %
function raw_bytes = encode_phys(phys, datatype, offset, mul, scale, dec)
    phys_d = double(phys(:));
    switch datatype
        case 1
            u16       = double_to_float16(phys_d);
            raw_bytes = typecast(uint16(u16(:)), 'uint8');
        case 2
            if scale ~= 0 && mul ~= 0
                raw_d = (phys_d - offset) .* (10^dec) .* (scale / mul);
            else
                raw_d = (phys_d - offset) .* (10^dec);
            end
            raw_bytes = typecast(int16(round(raw_d)), 'uint8');
        case 3
            if scale ~= 0 && mul ~= 0
                raw_d = (phys_d - offset) .* (10^dec) .* (scale / mul);
            else
                raw_d = (phys_d - offset) .* (10^dec);
            end
            raw_bytes = typecast(int32(round(raw_d)), 'uint8');
        case 4
            raw_d     = round((phys_d - offset) .* (10^dec));
            i16       = int16(raw_d);
            n         = numel(i16);
            i16_b     = reshape(typecast(i16, 'uint8'), 2, n);
            pad_b     = zeros(2, n, 'uint8');
            raw_bytes = [i16_b; pad_b];
        otherwise
            error('Unsupported datatype %d', datatype);
    end
    raw_bytes = raw_bytes(:);
end


% ======================================================================= %
%  READ BACK ONE CHANNEL
% ======================================================================= %
function [phys, ok, err] = readback_channel(filepath, data_ptr, n, ...
        datatype, offset, mul, scale, dec)
    phys = []; ok = false; err = '';
    try
        fid = fopen(filepath, 'rb');
        if fid < 0, err = 'cannot open'; return; end
        c = onCleanup(@() fclose(fid));
        fseek(fid, data_ptr, 'bof');
        switch datatype
            case 1
                u16  = fread(fid, n, 'uint16=>double', 0, 'l');
                phys = float16_to_double(u16);
            case 2
                raw  = fread(fid, n, 'int16=>double', 0, 'l');
                if scale ~= 0 && mul ~= 0
                    phys = raw .* (mul/scale) ./ (10^dec) + offset;
                else
                    phys = raw ./ (10^dec) + offset;
                end
            case 3
                raw  = fread(fid, n, 'int32=>double', 0, 'l');
                if scale ~= 0 && mul ~= 0
                    phys = raw .* (mul/scale) ./ (10^dec) + offset;
                else
                    phys = raw ./ (10^dec) + offset;
                end
            case 4
                raw  = fread(fid, n, 'int16=>double', 2, 'l');
                phys = raw ./ (10^dec) + offset;
            otherwise
                err = sprintf('unknown datatype %d', datatype); return;
        end
        ok = true;
    catch ME
        err = ME.message;
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function b = str_to_bytes(str, n)
    b = zeros(1, n, 'uint8');
    bytes = uint8(str(1:min(end, n)));
    b(1:numel(bytes)) = bytes;
end

function u16 = double_to_float16(x)
    x=double(x(:)); u16=zeros(size(x),'uint16'); sgn=uint16(x<0); ax=abs(x);
    nm=isnan(ax); u16(nm)=uint16(32767);
    im=isinf(ax); u16(im)=bitor(bitshift(sgn(im),15),uint16(31744));
    zm=(ax==0)&~nm&~im; u16(zm)=bitshift(sgn(zm),15);
    fin=~nm&~im&~zm;
    if any(fin)
        xf=ax(fin); sf=sgn(fin); e=floor(log2(xf)); eb=e+15;
        u=zeros(sum(fin),1,'uint16');
        ov=eb>=31; u(ov)=bitor(bitshift(sf(ov),15),uint16(31744));
        uv=(eb<=0)&~ov;
        if any(uv)
            fs=uint16(min(max(round(xf(uv)./2^(-14).*1024),0),1023));
            u(uv)=bitor(bitshift(sf(uv),15),fs);
        end
        nr=~ov&~uv;
        if any(nr)
            en=eb(nr);
            fn=uint16(min(max(round((xf(nr)./2.^e(nr)-1).*1024),0),1023));
            u(nr)=bitor(bitor(bitshift(sf(nr),15),bitshift(uint16(en),10)),fn);
        end
        u16(fin)=u;
    end
end

function out = float16_to_double(u16)
    sign=bitshift(bitand(u16,32768),-15); ex=bitshift(bitand(u16,31744),-10);
    frac=bitand(u16,1023); out=zeros(size(u16));
    nm=(ex>0)&(ex<31); out(nm)=(-1).^sign(nm).*2.^(ex(nm)-15).*(1+frac(nm)/1024);
    sn=(ex==0)&(frac~=0); out(sn)=(-1).^sign(sn).*2^-14.*(frac(sn)/1024);
    out(ex==31&frac==0)=Inf.*(-1).^sign(ex==31&frac==0);
    out(ex==31&frac~=0)=NaN;
end