    % function ld_add_channel(source_ld_file, output_ld_file, new_channels)
% % LD_ADD_CHANNEL  Append new channels to a MoTeC .ld file.
% %
% % Channel metadata records are 124 bytes (proven: gap / n_channels = 124).
% % Finds a donor channel at the same Hz, copies its full 124-byte metadata
% % record (including the 40-byte timing tail, bytes 85-124), patches only the
% % fields we own, then stitches into the linked list.
% %
% % If no donor exists at the requested Hz, a synthetic record is built from
% % the nearest donor — inheriting its timing tail for correct i2 Pro placement.
% %
% % Three separate fopen/fclose passes per channel (Windows r+b reliability):
% %   Pass A  patch prev channel's next_ptr   (r+b) — verified immediately
% %   Pass B  append metadata record + data   (ab)
% %   Pass C  read back and verify            (rb)
% %
% % Usage
% % -----
% %   ch.name        = 'Brake Balance VCH';
% %   ch.short_name  = 'BB VCH';    % optional ([] keeps donor, '' clears)
% %   ch.units       = '%';         % optional ([] keeps donor, '' clears)
% %   ch.value       = 60;          % scalar (repeated) or vector; absent = raw clone
% %   ch.sample_rate = 5;           % Hz
% %   ch.mul         = 1;           % optional scaling override
% %   ch.scale       = 1;           % optional scaling override
% %   ch.dec_places  = 2;           % optional — decimal places shown in i2 Pro
% %   ch.offset      = 0;           % optional
% %   ch.donor_name  = 'Engine Speed'; % optional — explicit named donor
% %   ld_add_channel('master.ld', 'output.ld', ch)
% 
%     META_BYTES = 124;
%     FLOAT_TOL  = 1e-3;
% 
%     if isstruct(new_channels)
%         ch_list = num2cell(new_channels);
%     else
%         ch_list = new_channels;
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  1. Copy master → output
%     % ------------------------------------------------------------------ %
%     fprintf('\n[LD_ADD_CHANNEL] Copying master → output...\n');
%     [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
%     if ~ok, error('copyfile failed: %s', msg); end
%     fprintf('  %s\n\n', output_ld_file);
% 
%     % ------------------------------------------------------------------ %
%     %  2. Walk binary — build donor map + get session duration
%     % ------------------------------------------------------------------ %
%     d = dir(output_ld_file);
%     file_sz = d.bytes;
% 
%     [last_meta_ptr, donor_map, session_dur, used_sr_raw] = walk_and_collect(output_ld_file, file_sz, META_BYTES);
% 
%     fprintf('  Session duration      : %.1f s\n', session_dur);
%     fprintf('  Last channel meta_ptr : 0x%X\n',   last_meta_ptr);
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
%         % short_name/units: keep [] if not provided — donor bytes inherited at record-write time
%         if ~isfield(ch, 'short_name'), ch.short_name = []; end
%         if ~isfield(ch, 'units'),      ch.units      = []; end
% 
%         fprintf('[%d/%d] "%s"  @ %d Hz\n', ci, numel(ch_list), ch.name, ch.sample_rate);
% 
%         % ---- A. Get or build donor record ---------------------------
%         if isfield(ch, 'donor_name') && ~isempty(ch.donor_name)
%             % Named donor: find by channel name in the file (authoritative sr_raw etc.)
%             donor_rec = find_named_donor(output_ld_file, ch.donor_name, file_sz, META_BYTES);
%             if isempty(donor_rec)
%                 error('donor_name "%s" not found in %s', ch.donor_name, output_ld_file);
%             end
%             d_str = strtrim(char(donor_rec(33:64)'));
%             d_nul = find(d_str == char(0), 1);
%             if ~isempty(d_nul), d_str = d_str(1:d_nul-1); end
%             fprintf('   Donor (named): "%s"\n', d_str);
%         elseif isKey(donor_map, ch.sample_rate)
%             donor_rec = donor_map(ch.sample_rate);
%             donor_name_raw = donor_rec(33:64);
%             donor_nul = find(donor_name_raw == 0, 1);
%             if ~isempty(donor_nul), donor_name_raw = donor_name_raw(1:donor_nul-1); end
%             donor_name_str = strtrim(char(donor_name_raw));
%             fprintf('   Donor: "%s" at %d Hz\n', donor_name_str, ch.sample_rate);
%         else
%             fprintf('   Donor: none at %d Hz — building synthetic\n', ch.sample_rate);
%             donor_rec = build_synthetic_donor(ch.sample_rate, session_dur, donor_map);
%         end
% 
%         % Extract donor fields
%         donor_datatype = double(typecast(uint8(donor_rec(21:22)), 'uint16'));
%         donor_sr       = double(typecast(uint8(donor_rec(23:24)), 'uint16'));
%         donor_offset   = double(typecast(uint8(donor_rec(25:26)), 'int16'));
%         donor_mul      = double(typecast(uint8(donor_rec(27:28)), 'int16'));
%         donor_scale    = double(typecast(uint8(donor_rec(29:30)), 'int16'));
%         donor_dec      = double(typecast(uint8(donor_rec(31:32)), 'int16'));
%         donor_n        = double(typecast(uint8(donor_rec(13:16)), 'uint32'));
%         donor_sr_raw   = double(typecast(uint8(donor_rec(17:18)), 'uint16'));
% 
%         % sr_raw is a sample clock group ID in i2 Pro.
%         % i2 anchors every channel in a group relative to the FIRST channel
%         % with that sr_raw by data_ptr:
%         %   time_offset = (new_data_ptr - first_data_ptr) / (bytes_per_sample * Hz)
%         % Borrowing ANY existing sr_raw causes a ~1450s offset because all native
%         % data is near the start of the file and our append is at the end.
%         % Fix: use an sr_raw value not present anywhere in the file so i2 Pro
%         % has no reference point and anchors the channel at session t=0.
%         % dec/scale/mul/offset are kept from the named donor for correct encoding.
%         if isfield(ch, 'donor_name') && ~isempty(ch.donor_name)
%             unique_sr_raw = find_unique_sr_raw(used_sr_raw);
%             fprintf('   sr_raw: %d -> %d (unique — not in file, anchors at t=0)\n', donor_sr_raw, unique_sr_raw);
%             donor_sr_raw       = unique_sr_raw;
%             used_sr_raw(end+1) = unique_sr_raw; %#ok<AGROW>
%         end
% 
%         % Allow direct sr_raw override (for testing/DOE)
%         if isfield(ch, 'sr_raw_override')
%             fprintf('   sr_raw: override -> %d\n', ch.sr_raw_override);
%             donor_sr_raw = double(ch.sr_raw_override);
%         end
% 
%         % Allow channel struct to override scaling fields.
%         % Track whether dec_places was explicitly set by caller — only then
%         % do we absorb it into scale (donor's proven dec/scale must not change).
%         explicit_dec = isfield(ch, 'dec_places') && ~isempty(ch.dec_places);
%         if explicit_dec
%             donor_dec = ch.dec_places;
%         end
%         if isfield(ch, 'offset') && ~isempty(ch.offset)
%             donor_offset = ch.offset;
%         end
%         if isfield(ch, 'mul') && ~isempty(ch.mul)
%             donor_mul = ch.mul;
%         end
%         if isfield(ch, 'scale') && ~isempty(ch.scale)
%             donor_scale = ch.scale;
%         end
% 
%         % --- Absorb dec_places into scale (only when caller explicitly set dec_places) ---
%         % i2 Pro does not commute dec_places and scale freely — the donor's native
%         % dec/scale pair must be preserved unless the caller is overriding precision.
%         % When the caller sets ch.dec_places (e.g. session constants with scale=1),
%         % absorb dec into scale so dec=0 is written: prevents i2 Pro sample truncation.
% %         if explicit_dec && donor_dec ~= 0 && donor_mul ~= 0
% %             effective_scale = donor_scale * round(10^donor_dec);
% %             if effective_scale > 0 && effective_scale <= 32767
% %                 fprintf('   Absorbing dec=%d into scale: %d -> %d (dec -> 0)\n', ...
% %                     donor_dec, donor_scale, effective_scale);
% %                 donor_scale = effective_scale;
% %                 donor_dec   = 0;
% %             else
% %                 fprintf('   [WARN] Cannot absorb dec=%d into scale=%d (would overflow int16) — keeping dec\n', ...
% %                     donor_dec, donor_scale * round(10^donor_dec));
% %             end
% %         end
% 
%         fprintf('   datatype=%d  Hz=%d  sr_raw=%d  mul=%d  scale=%d  dec=%d  offset=%d  n=%d\n', ...
%             donor_datatype, donor_sr, donor_sr_raw, donor_mul, donor_scale, ...
%             donor_dec, donor_offset, donor_n);
% 
%         % ---- B. Build raw bytes for new channel ----------------------
%         % If ch.value is absent: raw copy — read donor bytes verbatim.
%         % If ch.value is scalar or vector: encode via phys→raw formula.
%         raw_copy_mode = ~isfield(ch, 'value') || isempty(ch.value);
% 
%         if raw_copy_mode
%             % Pure clone: copy donor data bytes directly, no encode/decode.
%             donor_data_ptr   = double(typecast(uint8(donor_rec(9:12)),  'uint32'));
%             bps = bytes_per_sample_local(donor_datatype);
%             n   = donor_n;
%             fid_rc = fopen(output_ld_file, 'rb');
%             if fid_rc < 0, error('Cannot open for raw copy: %s', output_ld_file); end
%             fseek(fid_rc, donor_data_ptr, 'bof');
%             raw_bytes = fread(fid_rc, n * bps, 'uint8=>uint8');
%             fclose(fid_rc);
%             fprintf('   Raw copy: %d samples  %d bytes (from 0x%X)\n', n, numel(raw_bytes), donor_data_ptr);
%         else
%             % Allow datatype override (default: inherit from donor)
%             if isfield(ch, 'datatype') && ~isempty(ch.datatype)
%                 donor_datatype = ch.datatype;
%             end
%             % Scalars: use donor_n so the channel is time-aligned with natives.
%             % Vectors: caller owns sample count.
%             if isscalar(ch.value)
%                 n    = donor_n;
%                 phys = repmat(double(ch.value), n, 1);
%                 fprintf('   n from donor_n=%d (%.1f s @ %d Hz)\n', n, n/ch.sample_rate, ch.sample_rate);
%             else
%                 n    = numel(ch.value);
%                 phys = double(ch.value(:));
%             end
%             % Auto-shift negative channels so raw values are always non-negative.
%             % i2 applies header offset on read: physical = raw_uint16 / 10^dec + offset.
%             if donor_offset == 0
%                 finite_phys = phys(isfinite(phys));
%                 if ~isempty(finite_phys) && min(finite_phys) < 0
%                     donor_offset = max(floor(min(finite_phys)) - 1, -32767);
%                     if (max(finite_phys) - donor_offset) * 10^donor_dec > 65535
%                         warning('ld_add_channel:rawOverflow', ...
%                             '"%s": raw overflow — reduce dec_places', ch.name);
%                     end
%                 end
%             end
%             raw_bytes = encode_phys(phys, donor_datatype, donor_offset, ...
%                                      donor_mul, donor_scale, donor_dec);
%             fprintf('   Encoded: %d samples  %d bytes\n', n, numel(raw_bytes));
%         end
% 
%         % ---- C. Compute pointer positions ---------------------------
%         new_meta_ptr = current_file_sz;
% 
%         % TIMING DIAGNOSTIC: in raw_copy_mode we can optionally point data_ptr
%         % back to the donor's original data instead of the appended copy.
%         % If i2 Pro uses data_ptr for timing, this will make the clone perfectly
%         % time-aligned. Set ch.use_donor_data_ptr = true to enable.
%         use_donor_ptr = raw_copy_mode && isfield(ch, 'use_donor_data_ptr') && ch.use_donor_data_ptr;
%         if use_donor_ptr
%             new_data_ptr = double(typecast(uint8(donor_rec(9:12)), 'uint32'));
%             fprintf('   data_ptr: using donor ptr 0x%X (timing test)\n', new_data_ptr);
%         else
%             new_data_ptr = new_meta_ptr + META_BYTES;
%         end
%         fprintf('   new_meta_ptr=0x%X  new_data_ptr=0x%X\n', new_meta_ptr, new_data_ptr);
% 
%         % ---- D. Build metadata record from donor template -----------
%         rec = donor_rec;
%         rec(1:4)   = typecast(uint32(prev_meta_ptr),  'uint8');  % prev_ptr
%         rec(5:8)   = typecast(uint32(0),              'uint8');  % next_ptr = 0
%         rec(9:12)  = typecast(uint32(new_data_ptr),   'uint8');  % data_ptr
%         rec(13:16) = typecast(uint32(n),              'uint8');  % data_len
%         rec(17:18) = typecast(uint16(donor_sr_raw),   'uint8');  % sr_raw (may be collision-replaced above)
%         rec(21:22) = typecast(uint16(donor_datatype), 'uint8');  % datatype
%         rec(23:24) = typecast(uint16(ch.sample_rate), 'uint8');  % sample_rate (true Hz)
%         rec(25:26) = typecast(int16(donor_offset),    'uint8');  % ch_offset
%         rec(27:28) = typecast(int16(donor_mul),       'uint8');  % ch_mul
%         rec(29:30) = typecast(int16(donor_scale),     'uint8');  % ch_scale
%         rec(31:32) = typecast(int16(donor_dec),       'uint8');  % dec_places
%         rec(33:64) = str_to_bytes(ch.name, 32);
% %         if ~isempty(ch.short_name)
% if ischar(ch.short_name)   % [] = keep donor; '' = write zeros (clears donor)
%             rec(65:72) = str_to_bytes(ch.short_name, 8);
%         end
% %         if ~isempty(ch.units)
% if ischar(ch.units)        % [] = keep donor; '' = write zeros (clears donor)
%             rec(73:84) = str_to_bytes(ch.units, 12);
%         end
%         fprintf('   sr_raw written: %d  (Hz=%d)\n', donor_sr_raw, ch.sample_rate);
% 
%         % ---- PASS A: patch prev channel's next_ptr ------------------
%         fid_p = fopen(output_ld_file, 'r+b');
%         if fid_p < 0, error('Cannot open for patch: %s', output_ld_file); end
%         fseek(fid_p, prev_meta_ptr + 4, 'bof');
%         fwrite(fid_p, uint32(new_meta_ptr), 'uint32', 0, 'l');
%         fclose(fid_p);
% 
%         fid_v = fopen(output_ld_file, 'rb');
%         fseek(fid_v, prev_meta_ptr + 4, 'bof');
%         check = fread(fid_v, 1, 'uint32=>double', 0, 'l');
%         fclose(fid_v);
%         if check ~= new_meta_ptr
%             error('next_ptr patch FAILED: wrote 0x%X read 0x%X', new_meta_ptr, check);
%         end
%         fprintf('   Pass A: next_ptr → 0x%X  [verified]\n', new_meta_ptr);
% 
%         % ---- PASS B: append metadata record + data ------------------
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
%         fprintf('   Pass B: appended  new_file_sz=0x%X\n', current_file_sz);
% 
%         % ---- PASS C: read back and verify ---------------------------
%         if raw_copy_mode
%             % Raw copy: verify byte-for-byte match.
%             fid_rc2 = fopen(output_ld_file, 'rb');
%             fseek(fid_rc2, new_data_ptr, 'bof');
%             rb_raw = fread(fid_rc2, numel(raw_bytes), 'uint8=>uint8');
%             fclose(fid_rc2);
%             if isequal(raw_bytes(:), rb_raw(:))
%                 fprintf('   Pass C: [PASS] raw copy verified  (%d bytes)\n\n', numel(raw_bytes));
%             else
%                 fprintf('   Pass C: [FAIL] raw copy mismatch\n\n');
%             end
%         else
%             % Encoded: tolerance = half a stored unit + epsilon guard.
%             % (0.05 is not exactly representable in IEEE 754 — without epsilon
%             %  max_err > tol can be true when they are nominally equal.)
%             if donor_dec >= 0 && donor_scale > 0
%                 pass_c_tol = max(0.5 * donor_mul / donor_scale / (10^donor_dec), 1e-9);
%                 pass_c_tol = pass_c_tol * (1 + 1e-6);
%             else
%                 pass_c_tol = FLOAT_TOL;
%             end
%             [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, ...
%                 new_data_ptr, n, donor_datatype, donor_offset, ...
%                 donor_mul, donor_scale, donor_dec);
%             if ~rb_ok
%                 fprintf('   Pass C: [FAIL] %s\n\n', rb_err);
%             else
%                 max_err = max(abs(rb_phys - phys));
%                 if max_err > pass_c_tol
%                     fprintf('   Pass C: [FAIL] max_err=%.6f  (tol=%.6f)\n\n', max_err, pass_c_tol);
%                 else
%                     fprintf('   Pass C: [PASS] max_err=%.2e  value=%.4g\n\n', max_err, rb_phys(1));
%                 end
%             end
%         end
% 
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  4. Delete stale .ldx cache (if present)
%     % ------------------------------------------------------------------ %
%     [ldx_dir, ldx_base] = fileparts(output_ld_file);
%     ldx_path = fullfile(ldx_dir, [ldx_base '.ldx']);
%     if exist(ldx_path, 'file')
%         delete(ldx_path);
%         if ~exist(ldx_path, 'file')
%             fprintf('  Deleted stale .ldx: %s\n', ldx_path);
%         else
%             fprintf('  WARNING: could not delete .ldx (close i2 Pro): %s\n', ldx_path);
%         end
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  5. Summary
%     % ------------------------------------------------------------------ %
%     d2 = dir(output_ld_file);
%     fprintf('============================================================\n');
%     fprintf('  COMPLETE\n');
%     fprintf('  Channels added : %d\n',       numel(ch_list));
%     fprintf('  Original size  : %d bytes\n', file_sz);
%     fprintf('  New size       : %d bytes\n', d2.bytes);
%     fprintf('  Output         : %s\n',       output_ld_file);
%     fprintf('============================================================\n');
% end
% 
% 
% % ======================================================================= %
% %  WALK AND COLLECT
% % ======================================================================= %
% function [last_meta_ptr, donor_map, session_dur, used_sr_raw] = walk_and_collect(filepath, file_sz, META_BYTES) %#ok
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
%     donor_n_map   = containers.Map('KeyType', 'double', 'ValueType', 'double');  % track best ch_n per Hz
%     last_meta_ptr = current_ptr;
%     session_dur   = 0;
%     used_sr_raw   = zeros(1, 2000, 'double');  % pre-alloc for speed
%     sr_raw_count  = 0;
%     count         = 0;
% 
%     while current_ptr ~= 0 && current_ptr < file_sz
%         fseek(fid, current_ptr, 'bof');
%         rec      = fread(fid, META_BYTES, 'uint8=>uint8');
%         next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
%         sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
%         unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
%         sr_raw_val           = double(typecast(uint8(rec(17:18)), 'uint16'));
%         sr_raw_count         = sr_raw_count + 1;
%         used_sr_raw(sr_raw_count) = sr_raw_val;
%         ch_n     = double(typecast(uint8(rec(13:16)), 'uint32'));
% 
%         % Compute session duration from ALL channels — use maximum
%         if sr > 0 && ch_n > 0
%             dur_this = ch_n / sr;
%             if dur_this > session_dur
%                 session_dur = dur_this;
%             end
%         end
% 
%         % Select donor at each Hz: prefer highest ch_n (longest coverage),
%         % with secondary preference for unk1=0x0003
%         if sr > 0 && ch_n > 0
%             best_n = 0;
%             if isKey(donor_n_map, sr), best_n = donor_n_map(sr); end
%             existing_unk1 = 0;
%             if isKey(donor_map, sr)
%                 existing_rec  = donor_map(sr);
%                 existing_unk1 = double(typecast(uint8(existing_rec(19:20)), 'uint16'));
%             end
%             if ch_n > best_n || (ch_n == best_n && unk1 == 3 && isKey(donor_map, sr) && ...
%                     existing_unk1 ~= 3)
%                 donor_map(sr)   = rec;
%                 donor_n_map(sr) = ch_n;
%             end
%         end
% 
%         last_meta_ptr = current_ptr;
%         current_ptr   = next_ptr;
%         count = count + 1;
%         if count > 5000, warning('5000 channel limit'); break; end
%     end
% 
%     % Report donors selected
%     hz_list = cell2mat(keys(donor_map));
%     for i = 1:numel(hz_list)
%         d      = donor_map(hz_list(i));
%         d_unk1 = double(typecast(uint8(d(19:20)), 'uint16'));
%         d_name = strtrim(char(d(33:64)'));
%         nul    = find(d_name==0,1);
%         if ~isempty(nul), d_name = d_name(1:nul-1); end
%         fprintf('  Donor Hz=%-4d  unk1=0x%04X  name=%s\n', hz_list(i), d_unk1, d_name);
%     end
%     fprintf('  Walked %d channels.\n', count);
%     used_sr_raw = used_sr_raw(1:sr_raw_count);
% end
% 
% 
% % ======================================================================= %
% %  BUILD SYNTHETIC DONOR
% %  For Hz values not present in the file.
% %  Borrows sr_raw from the nearest known donor — i2 Pro requires non-zero.
% % ======================================================================= %
% function rec = build_synthetic_donor(sample_rate, session_dur, donor_map)
% 
%     known_hz    = cell2mat(keys(donor_map));
%     [~, idx]    = min(abs(known_hz - sample_rate));
%     near_donor  = donor_map(known_hz(idx));
%     near_sr_raw = double(typecast(uint8(near_donor(17:18)), 'uint16'));
% 
%     % Derive n_samples from nearest donor's ch_n scaled by Hz ratio.
%     % Avoids the session_dur overestimate that causes time-shift in i2 Pro.
%     near_n  = double(typecast(uint8(near_donor(13:16)), 'uint32'));
%     near_hz = known_hz(idx);
%     n_samples = round(near_n * sample_rate / near_hz);
% 
%     rec = near_donor;  % full 124-byte template — inherits tail (bytes 85-124) for correct i2 Pro timing
%     % bytes 1-12: prev/next/data ptrs — overwritten by caller
%     rec(13:16) = typecast(uint32(n_samples),    'uint8');   % data_len
%     rec(17:18) = typecast(uint16(near_sr_raw),  'uint8');   % sr_raw = catalog ID from nearest donor
%     rec(19:20) = typecast(uint16(3),            'uint8');   % unk1 = 0x0003
%     rec(21:22) = typecast(uint16(2),          'uint8');   % datatype = int16
%     rec(23:24) = typecast(uint16(sample_rate),'uint8');   % sample_rate
%     rec(25:26) = typecast(int16(0),           'uint8');   % offset = 0
%     rec(27:28) = typecast(int16(1),           'uint8');   % mul    = 1
%     rec(29:30) = typecast(int16(1),           'uint8');   % scale  = 1
%     rec(31:32) = typecast(int16(0),           'uint8');   % dec    = 0
%     % bytes 33-84: name/short/units — overwritten by caller
% 
%     fprintf('   Synthetic: Hz=%d  n=%d  sr_raw=%d (nearest donor %dHz)\n', ...
%         sample_rate, n_samples, near_sr_raw, known_hz(idx));
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
%             n_neg  = sum(raw_d < 0 & isfinite(raw_d));
%             n_over = sum(raw_d > 32767 & isfinite(raw_d));
%             if n_neg > 0
%                 warning('ld_add_channel:negativeRaw', ...
%                     '%d samples have negative raw — offset (%.3g) must be <= min(phys) (%.3g). Set ch.offset = floor(min(phys)).', ...
%                     n_neg, offset, min(phys_d(isfinite(phys_d))));
%             end
%             if n_over > 0
%                 warning('ld_add_channel:rawOverflow', ...
%                     '%d samples exceed raw limit 32767 — dec=%d, max raw=%.0f. Reduce dec_places.', ...
%                     n_over, dec, max(raw_d(isfinite(raw_d))));
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
% %  FIND NAMED DONOR
% %  Walk the linked list and return the 84-byte record whose name field
% %  matches donor_name (case-insensitive). Returns [] if not found.
% % ======================================================================= %
% function rec = find_named_donor(filepath, donor_name, file_sz, META_BYTES)
%     rec = [];
%     fid = fopen(filepath, 'rb');
%     if fid < 0, error('Cannot open: %s', filepath); end
%     c = onCleanup(@() fclose(fid));
% 
%     fseek(fid, 0x0008, 'bof');
%     ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
%     target = lower(strtrim(donor_name));
%     count = 0;
%     while ptr ~= 0 && ptr < file_sz
%         fseek(fid, ptr, 'bof');
%         r = fread(fid, META_BYTES, 'uint8=>uint8')';
%         name_raw = strtrim(char(r(33:64)));
%         nul = find(name_raw == char(0), 1);
%         if ~isempty(nul), name_raw = name_raw(1:nul-1); end
%         if strcmpi(strtrim(name_raw), target)
%             rec = r;
%             return;
%         end
%         ptr = double(typecast(uint8(r(5:8)), 'uint32'));
%         count = count + 1;
%         if count > 5000, break; end
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
% function sr_raw = find_unique_sr_raw(used_sr_raw)
%     % Find the smallest value >= 30000 not already used in the file.
%     % Range 30000-65535 is outside all known MoTeC catalog IDs (max observed ~11600).
%     candidate = uint32(30000);
%     while any(used_sr_raw == candidate)
%         candidate = candidate + 1;
%     end
%     sr_raw = double(candidate);
% end
% 
% function n = bytes_per_sample_local(datatype)
%     switch datatype
%         case {1, 2}, n = 2;
%         case {3, 4}, n = 4;
%         otherwise,   n = 2;
%     end
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
% 
% 
% function ld_add_channel(source_ld_file, output_ld_file, new_channels)
% % LD_ADD_CHANNEL  Append new channels to a MoTeC .ld file.
% %
% % Channel metadata records are 124 bytes (proven: gap / n_channels = 124).
% % Finds a donor channel at the same Hz, copies its full 124-byte metadata
% % record (including the 40-byte timing tail, bytes 85-124), patches only the
% % fields we own, then stitches into the linked list.
% %
% % If no donor exists at the requested Hz, a synthetic record is built from
% % the nearest donor — inheriting its timing tail for correct i2 Pro placement.
% %
% % Three separate fopen/fclose passes per channel (Windows r+b reliability):
% %   Pass A  patch prev channel's next_ptr   (r+b) — verified immediately
% %   Pass B  append metadata record + data   (ab)
% %   Pass C  read back and verify            (rb)
% %
% % Usage
% % -----
% %   ch.name        = 'Brake Balance VCH';
% %   ch.short_name  = 'BB VCH';    % optional ([] keeps donor, '' clears)
% %   ch.units       = '%';         % optional ([] keeps donor, '' clears)
% %   ch.value       = 60;          % scalar (repeated) or vector; absent = raw clone
% %   ch.sample_rate = 5;           % Hz
% %   ch.mul         = 1;           % optional scaling override
% %   ch.scale       = 1;           % optional scaling override
% %   ch.dec_places  = 2;           % optional — decimal places shown in i2 Pro
% %   ch.offset      = 0;           % optional
% %   ch.donor_name  = 'Engine Speed'; % optional — explicit named donor
% %   ch.overwrite   = true;        % optional — if a channel named ch.name
% %                                 % already exists in the file, unlink it
% %                                 % and append this one in its place.
% %                                 % Omitted/false = ERROR on name collision
% %                                 % (protects against silent duplicates).
% %                                 % Only channels present in ch_list are ever
% %                                 % eligible for replacement — nothing else
% %                                 % in the file is touched.
% %   ld_add_channel('master.ld', 'output.ld', ch)
% 
%     META_BYTES = 124;
%     FLOAT_TOL  = 1e-3;
% 
%     if isstruct(new_channels)
%         ch_list = num2cell(new_channels);
%     else
%         ch_list = new_channels;
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  1. Copy master → output
%     % ------------------------------------------------------------------ %
%     fprintf('\n[LD_ADD_CHANNEL] Copying master → output...\n');
%     [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
%     if ~ok, error('copyfile failed: %s', msg); end
%     fprintf('  %s\n\n', output_ld_file);
% 
%     % ------------------------------------------------------------------ %
%     %  2. Walk binary — build donor map + get session duration
%     % ------------------------------------------------------------------ %
%     d = dir(output_ld_file);
%     file_sz = d.bytes;
% 
%     [last_meta_ptr, donor_map, session_dur, used_sr_raw] = walk_and_collect(output_ld_file, file_sz, META_BYTES);
% 
%     fprintf('  Session duration      : %.1f s\n', session_dur);
%     fprintf('  Last channel meta_ptr : 0x%X\n',   last_meta_ptr);
%     fprintf('  Donor rates available : %s\n\n', ...
%         strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), 'UniformOutput', false), ', '));
% 
%     % ------------------------------------------------------------------ %
%     %  2.5 Overwrite protection — unlink any ch_list channel that already
%     %      exists in the file, but ONLY channels named in ch_list.
%     %      A channel is replaced iff ch.overwrite == true; otherwise a
%     %      pre-existing name is a hard error (no silent duplication, no
%     %      silent overwrite).
%     % ------------------------------------------------------------------ %
%     name_index = build_name_index(output_ld_file, file_sz, META_BYTES);
% 
%     for ci = 1:numel(ch_list)
%         ch = ch_list{ci};
%         key = lower(strtrim(ch.name));
%         if ~isKey(name_index, key)
%             continue;   % no collision — nothing to protect against
%         end
% 
%         want_overwrite = isfield(ch, 'overwrite') && ~isempty(ch.overwrite) && logical(ch.overwrite(1));
%         if ~want_overwrite
%             warning('ld_add_channel:nameCollision', ...
%                 ['Channel "%s" already exists in %s — SKIPPING.\n' ...
%                  'Set ch.overwrite = true on this channel struct to replace it ' ...
%                  '(only channels you explicitly name are ever touched).'], ...
%                  ch.name, output_ld_file);
%             ch_list{ci} = [];   % mark for removal, doesn't stop the rest of the batch
%             continue;
%         end
% 
%         entry = name_index(key);
%         fprintf('[overwrite] "%s" exists (meta_ptr=0x%X) — unlinking old record\n', ...
%             ch.name, entry.meta_ptr);
% 
%         fid_u = fopen(output_ld_file, 'r+b');
%         if fid_u < 0, error('Cannot open for unlink: %s', output_ld_file); end
%         if entry.prev_ptr == 0
%             % Removed node was the list head — patch the file header pointer.
%             fseek(fid_u, 0x0008, 'bof');
%             fwrite(fid_u, uint32(entry.next_ptr), 'uint32', 0, 'l');
%         else
%             % Patch the removed node's predecessor to skip over it.
%             fseek(fid_u, entry.prev_ptr + 4, 'bof');
%             fwrite(fid_u, uint32(entry.next_ptr), 'uint32', 0, 'l');
%         end
%         fclose(fid_u);
% 
%         % If the removed node was the current tail, the tail is now its
%         % predecessor (or, if it had no predecessor, the list is empty —
%         % that should never happen for a real .ld file, so just error).
%         if entry.meta_ptr == last_meta_ptr
%             if entry.prev_ptr == 0
%                 error('ld_add_channel:emptyList', ...
%                     'Removing "%s" would empty the channel list — aborting.', ch.name);
%             end
%             last_meta_ptr = entry.prev_ptr;
%         end
% 
%         remove(name_index, key);  % this name slot is now free
% 
%         % Propagate: any OTHER pending entry whose recorded prev_ptr pointed
%         % at the node we just removed must be updated to point at ITS
%         % predecessor instead — otherwise unlinking that entry next would
%         % patch dead/orphaned space instead of the real list, and silently
%         % fail to actually unlink it (leaving stale data live in the file
%         % and any newly-appended replacement channel unreachable).
%         remaining_keys = keys(name_index);
%         for kk = 1:numel(remaining_keys)
%             other = name_index(remaining_keys{kk});
%             if other.prev_ptr == entry.meta_ptr
%                 other.prev_ptr = entry.prev_ptr;
%                 name_index(remaining_keys{kk}) = other;
%             end
%         end
% 
%         fprintf('   Unlinked. (old data bytes left in place as dead space)\n\n');
%     end
% 
%     % Drop any channels skipped above due to an unresolved name collision.
%     ch_list = ch_list(~cellfun(@isempty, ch_list));
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
%         % short_name/units: keep [] if not provided — donor bytes inherited at record-write time
%         if ~isfield(ch, 'short_name'), ch.short_name = []; end
%         if ~isfield(ch, 'units'),      ch.units      = []; end
% 
%         fprintf('[%d/%d] "%s"  @ %d Hz\n', ci, numel(ch_list), ch.name, ch.sample_rate);
% 
%         % ---- A. Get or build donor record ---------------------------
%         if isfield(ch, 'donor_name') && ~isempty(ch.donor_name)
%             % Named donor: find by channel name in the file (authoritative sr_raw etc.)
%             donor_rec = find_named_donor(output_ld_file, ch.donor_name, file_sz, META_BYTES);
%             if isempty(donor_rec)
%                 error('donor_name "%s" not found in %s', ch.donor_name, output_ld_file);
%             end
%             d_str = strtrim(char(donor_rec(33:64)'));
%             d_nul = find(d_str == char(0), 1);
%             if ~isempty(d_nul), d_str = d_str(1:d_nul-1); end
%             fprintf('   Donor (named): "%s"\n', d_str);
%         elseif isKey(donor_map, ch.sample_rate)
%             donor_rec = donor_map(ch.sample_rate);
%             donor_name_raw = donor_rec(33:64);
%             donor_nul = find(donor_name_raw == 0, 1);
%             if ~isempty(donor_nul), donor_name_raw = donor_name_raw(1:donor_nul-1); end
%             donor_name_str = strtrim(char(donor_name_raw));
%             fprintf('   Donor: "%s" at %d Hz\n', donor_name_str, ch.sample_rate);
%         else
%             fprintf('   Donor: none at %d Hz — building synthetic\n', ch.sample_rate);
%             donor_rec = build_synthetic_donor(ch.sample_rate, session_dur, donor_map);
%         end
% 
%         % Extract donor fields
%         donor_datatype = double(typecast(uint8(donor_rec(21:22)), 'uint16'));
%         donor_sr       = double(typecast(uint8(donor_rec(23:24)), 'uint16'));
%         donor_offset   = double(typecast(uint8(donor_rec(25:26)), 'int16'));
%         donor_mul      = double(typecast(uint8(donor_rec(27:28)), 'int16'));
%         donor_scale    = double(typecast(uint8(donor_rec(29:30)), 'int16'));
%         donor_dec      = double(typecast(uint8(donor_rec(31:32)), 'int16'));
%         donor_n        = double(typecast(uint8(donor_rec(13:16)), 'uint32'));
%         donor_sr_raw   = double(typecast(uint8(donor_rec(17:18)), 'uint16'));
% 
%         % sr_raw is a sample clock group ID in i2 Pro.
%         % i2 anchors every channel in a group relative to the FIRST channel
%         % with that sr_raw by data_ptr:
%         %   time_offset = (new_data_ptr - first_data_ptr) / (bytes_per_sample * Hz)
%         % Borrowing ANY existing sr_raw causes a ~1450s offset because all native
%         % data is near the start of the file and our append is at the end.
%         % Fix: use an sr_raw value not present anywhere in the file so i2 Pro
%         % has no reference point and anchors the channel at session t=0.
%         % dec/scale/mul/offset are kept from the named donor for correct encoding.
%         if isfield(ch, 'donor_name') && ~isempty(ch.donor_name)
%             unique_sr_raw = find_unique_sr_raw(used_sr_raw);
%             fprintf('   sr_raw: %d -> %d (unique — not in file, anchors at t=0)\n', donor_sr_raw, unique_sr_raw);
%             donor_sr_raw       = unique_sr_raw;
%             used_sr_raw(end+1) = unique_sr_raw; %#ok<AGROW>
%         end
% 
%         % Allow direct sr_raw override (for testing/DOE)
%         if isfield(ch, 'sr_raw_override')
%             fprintf('   sr_raw: override -> %d\n', ch.sr_raw_override);
%             donor_sr_raw = double(ch.sr_raw_override);
%         end
% 
%         % Allow channel struct to override scaling fields.
%         % Track whether dec_places was explicitly set by caller — only then
%         % do we absorb it into scale (donor's proven dec/scale must not change).
%         explicit_dec = isfield(ch, 'dec_places') && ~isempty(ch.dec_places);
%         if explicit_dec
%             donor_dec = ch.dec_places;
%         end
%         if isfield(ch, 'offset') && ~isempty(ch.offset)
%             donor_offset = ch.offset;
%         end
%         if isfield(ch, 'mul') && ~isempty(ch.mul)
%             donor_mul = ch.mul;
%         end
%         if isfield(ch, 'scale') && ~isempty(ch.scale)
%             donor_scale = ch.scale;
%         end
% 
%         % --- Absorb dec_places into scale (only when caller explicitly set dec_places) ---
%         % i2 Pro does not commute dec_places and scale freely — the donor's native
%         % dec/scale pair must be preserved unless the caller is overriding precision.
%         % When the caller sets ch.dec_places (e.g. session constants with scale=1),
%         % absorb dec into scale so dec=0 is written: prevents i2 Pro sample truncation.
% %         if explicit_dec && donor_dec ~= 0 && donor_mul ~= 0
% %             effective_scale = donor_scale * round(10^donor_dec);
% %             if effective_scale > 0 && effective_scale <= 32767
% %                 fprintf('   Absorbing dec=%d into scale: %d -> %d (dec -> 0)\n', ...
% %                     donor_dec, donor_scale, effective_scale);
% %                 donor_scale = effective_scale;
% %                 donor_dec   = 0;
% %             else
% %                 fprintf('   [WARN] Cannot absorb dec=%d into scale=%d (would overflow int16) — keeping dec\n', ...
% %                     donor_dec, donor_scale * round(10^donor_dec));
% %             end
% %         end
% 
%         fprintf('   datatype=%d  Hz=%d  sr_raw=%d  mul=%d  scale=%d  dec=%d  offset=%d  n=%d\n', ...
%             donor_datatype, donor_sr, donor_sr_raw, donor_mul, donor_scale, ...
%             donor_dec, donor_offset, donor_n);
% 
%         % ---- B. Build raw bytes for new channel ----------------------
%         % If ch.value is absent: raw copy — read donor bytes verbatim.
%         % If ch.value is scalar or vector: encode via phys→raw formula.
%         raw_copy_mode = ~isfield(ch, 'value') || isempty(ch.value);
% 
%         if raw_copy_mode
%             % Pure clone: copy donor data bytes directly, no encode/decode.
%             donor_data_ptr   = double(typecast(uint8(donor_rec(9:12)),  'uint32'));
%             bps = bytes_per_sample_local(donor_datatype);
%             n   = donor_n;
%             fid_rc = fopen(output_ld_file, 'rb');
%             if fid_rc < 0, error('Cannot open for raw copy: %s', output_ld_file); end
%             fseek(fid_rc, donor_data_ptr, 'bof');
%             raw_bytes = fread(fid_rc, n * bps, 'uint8=>uint8');
%             fclose(fid_rc);
%             fprintf('   Raw copy: %d samples  %d bytes (from 0x%X)\n', n, numel(raw_bytes), donor_data_ptr);
%         else
%             % Allow datatype override (default: inherit from donor)
%             if isfield(ch, 'datatype') && ~isempty(ch.datatype)
%                 donor_datatype = ch.datatype;
%             end
%             % Scalars: use donor_n so the channel is time-aligned with natives.
%             % Vectors: caller owns sample count.
%             if isscalar(ch.value)
%                 n    = donor_n;
%                 phys = repmat(double(ch.value), n, 1);
%                 fprintf('   n from donor_n=%d (%.1f s @ %d Hz)\n', n, n/ch.sample_rate, ch.sample_rate);
%             else
%                 n    = numel(ch.value);
%                 phys = double(ch.value(:));
%             end
%             % Auto-shift negative channels so raw values are always non-negative.
%             % i2 applies header offset on read: physical = raw_uint16 / 10^dec + offset.
%             if donor_offset == 0
%                 finite_phys = phys(isfinite(phys));
%                 if ~isempty(finite_phys) && min(finite_phys) < 0
%                     donor_offset = max(floor(min(finite_phys)) - 1, -32767);
%                     if (max(finite_phys) - donor_offset) * 10^donor_dec > 65535
%                         warning('ld_add_channel:rawOverflow', ...
%                             '"%s": raw overflow — reduce dec_places', ch.name);
%                     end
%                 end
%             end
%             raw_bytes = encode_phys(phys, donor_datatype, donor_offset, ...
%                                      donor_mul, donor_scale, donor_dec);
%             fprintf('   Encoded: %d samples  %d bytes\n', n, numel(raw_bytes));
%         end
% 
%         % ---- C. Compute pointer positions ---------------------------
%         new_meta_ptr = current_file_sz;
% 
%         % TIMING DIAGNOSTIC: in raw_copy_mode we can optionally point data_ptr
%         % back to the donor's original data instead of the appended copy.
%         % If i2 Pro uses data_ptr for timing, this will make the clone perfectly
%         % time-aligned. Set ch.use_donor_data_ptr = true to enable.
%         use_donor_ptr = raw_copy_mode && isfield(ch, 'use_donor_data_ptr') && ch.use_donor_data_ptr;
%         if use_donor_ptr
%             new_data_ptr = double(typecast(uint8(donor_rec(9:12)), 'uint32'));
%             fprintf('   data_ptr: using donor ptr 0x%X (timing test)\n', new_data_ptr);
%         else
%             new_data_ptr = new_meta_ptr + META_BYTES;
%         end
%         fprintf('   new_meta_ptr=0x%X  new_data_ptr=0x%X\n', new_meta_ptr, new_data_ptr);
% 
%         % ---- D. Build metadata record from donor template -----------
%         rec = donor_rec;
%         rec(1:4)   = typecast(uint32(prev_meta_ptr),  'uint8');  % prev_ptr
%         rec(5:8)   = typecast(uint32(0),              'uint8');  % next_ptr = 0
%         rec(9:12)  = typecast(uint32(new_data_ptr),   'uint8');  % data_ptr
%         rec(13:16) = typecast(uint32(n),              'uint8');  % data_len
%         rec(17:18) = typecast(uint16(donor_sr_raw),   'uint8');  % sr_raw (may be collision-replaced above)
%         rec(21:22) = typecast(uint16(donor_datatype), 'uint8');  % datatype
%         rec(23:24) = typecast(uint16(ch.sample_rate), 'uint8');  % sample_rate (true Hz)
%         rec(25:26) = typecast(int16(donor_offset),    'uint8');  % ch_offset
%         rec(27:28) = typecast(int16(donor_mul),       'uint8');  % ch_mul
%         rec(29:30) = typecast(int16(donor_scale),     'uint8');  % ch_scale
%         rec(31:32) = typecast(int16(donor_dec),       'uint8');  % dec_places
%         rec(33:64) = str_to_bytes(ch.name, 32);
% %         if ~isempty(ch.short_name)
% if ischar(ch.short_name)   % [] = keep donor; '' = write zeros (clears donor)
%             rec(65:72) = str_to_bytes(ch.short_name, 8);
%         end
% %         if ~isempty(ch.units)
% if ischar(ch.units)        % [] = keep donor; '' = write zeros (clears donor)
%             rec(73:84) = str_to_bytes(ch.units, 12);
%         end
%         fprintf('   sr_raw written: %d  (Hz=%d)\n', donor_sr_raw, ch.sample_rate);
% 
%         % ---- PASS A: patch prev channel's next_ptr ------------------
%         fid_p = fopen(output_ld_file, 'r+b');
%         if fid_p < 0, error('Cannot open for patch: %s', output_ld_file); end
%         fseek(fid_p, prev_meta_ptr + 4, 'bof');
%         fwrite(fid_p, uint32(new_meta_ptr), 'uint32', 0, 'l');
%         fclose(fid_p);
% 
%         fid_v = fopen(output_ld_file, 'rb');
%         fseek(fid_v, prev_meta_ptr + 4, 'bof');
%         check = fread(fid_v, 1, 'uint32=>double', 0, 'l');
%         fclose(fid_v);
%         if check ~= new_meta_ptr
%             error('next_ptr patch FAILED: wrote 0x%X read 0x%X', new_meta_ptr, check);
%         end
%         fprintf('   Pass A: next_ptr → 0x%X  [verified]\n', new_meta_ptr);
% 
%         % ---- PASS B: append metadata record + data ------------------
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
%         fprintf('   Pass B: appended  new_file_sz=0x%X\n', current_file_sz);
% 
%         % ---- PASS C: read back and verify ---------------------------
%         if raw_copy_mode
%             % Raw copy: verify byte-for-byte match.
%             fid_rc2 = fopen(output_ld_file, 'rb');
%             fseek(fid_rc2, new_data_ptr, 'bof');
%             rb_raw = fread(fid_rc2, numel(raw_bytes), 'uint8=>uint8');
%             fclose(fid_rc2);
%             if isequal(raw_bytes(:), rb_raw(:))
%                 fprintf('   Pass C: [PASS] raw copy verified  (%d bytes)\n\n', numel(raw_bytes));
%             else
%                 fprintf('   Pass C: [FAIL] raw copy mismatch\n\n');
%             end
%         else
%             % Encoded: tolerance = half a stored unit + epsilon guard.
%             % (0.05 is not exactly representable in IEEE 754 — without epsilon
%             %  max_err > tol can be true when they are nominally equal.)
%             if donor_dec >= 0 && donor_scale > 0
%                 pass_c_tol = max(0.5 * donor_mul / donor_scale / (10^donor_dec), 1e-9);
%                 pass_c_tol = pass_c_tol * (1 + 1e-6);
%             else
%                 pass_c_tol = FLOAT_TOL;
%             end
%             [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, ...
%                 new_data_ptr, n, donor_datatype, donor_offset, ...
%                 donor_mul, donor_scale, donor_dec);
%             if ~rb_ok
%                 fprintf('   Pass C: [FAIL] %s\n\n', rb_err);
%             else
%                 max_err = max(abs(rb_phys - phys));
%                 if max_err > pass_c_tol
%                     fprintf('   Pass C: [FAIL] max_err=%.6f  (tol=%.6f)\n\n', max_err, pass_c_tol);
%                 else
%                     fprintf('   Pass C: [PASS] max_err=%.2e  value=%.4g\n\n', max_err, rb_phys(1));
%                 end
%             end
%         end
% 
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  4. Delete stale .ldx cache (if present)
%     % ------------------------------------------------------------------ %
%     [ldx_dir, ldx_base] = fileparts(output_ld_file);
%     ldx_path = fullfile(ldx_dir, [ldx_base '.ldx']);
%     if exist(ldx_path, 'file')
%         delete(ldx_path);
%         if ~exist(ldx_path, 'file')
%             fprintf('  Deleted stale .ldx: %s\n', ldx_path);
%         else
%             fprintf('  WARNING: could not delete .ldx (close i2 Pro): %s\n', ldx_path);
%         end
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  5. Summary
%     % ------------------------------------------------------------------ %
%     d2 = dir(output_ld_file);
%     fprintf('============================================================\n');
%     fprintf('  COMPLETE\n');
%     fprintf('  Channels added : %d\n',       numel(ch_list));
%     fprintf('  Original size  : %d bytes\n', file_sz);
%     fprintf('  New size       : %d bytes\n', d2.bytes);
%     fprintf('  Output         : %s\n',       output_ld_file);
%     fprintf('============================================================\n');
% end
% 
% 
% % ======================================================================= %
% %  WALK AND COLLECT
% % ======================================================================= %
% function [last_meta_ptr, donor_map, session_dur, used_sr_raw] = walk_and_collect(filepath, file_sz, META_BYTES) %#ok
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
%     donor_n_map   = containers.Map('KeyType', 'double', 'ValueType', 'double');  % track best ch_n per Hz
%     last_meta_ptr = current_ptr;
%     session_dur   = 0;
%     used_sr_raw   = zeros(1, 2000, 'double');  % pre-alloc for speed
%     sr_raw_count  = 0;
%     count         = 0;
% 
%     while current_ptr ~= 0 && current_ptr < file_sz
%         fseek(fid, current_ptr, 'bof');
%         rec      = fread(fid, META_BYTES, 'uint8=>uint8');
%         next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
%         sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
%         unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
%         sr_raw_val           = double(typecast(uint8(rec(17:18)), 'uint16'));
%         sr_raw_count         = sr_raw_count + 1;
%         used_sr_raw(sr_raw_count) = sr_raw_val;
%         ch_n     = double(typecast(uint8(rec(13:16)), 'uint32'));
% 
%         % Compute session duration from ALL channels — use maximum
%         if sr > 0 && ch_n > 0
%             dur_this = ch_n / sr;
%             if dur_this > session_dur
%                 session_dur = dur_this;
%             end
%         end
% 
%         % Select donor at each Hz: prefer highest ch_n (longest coverage),
%         % with secondary preference for unk1=0x0003
%         if sr > 0 && ch_n > 0
%             best_n = 0;
%             if isKey(donor_n_map, sr), best_n = donor_n_map(sr); end
%             existing_unk1 = 0;
%             if isKey(donor_map, sr)
%                 existing_rec  = donor_map(sr);
%                 existing_unk1 = double(typecast(uint8(existing_rec(19:20)), 'uint16'));
%             end
%             if ch_n > best_n || (ch_n == best_n && unk1 == 3 && isKey(donor_map, sr) && ...
%                     existing_unk1 ~= 3)
%                 donor_map(sr)   = rec;
%                 donor_n_map(sr) = ch_n;
%             end
%         end
% 
%         last_meta_ptr = current_ptr;
%         current_ptr   = next_ptr;
%         count = count + 1;
%         if count > 5000, warning('5000 channel limit'); break; end
%     end
% 
%     % Report donors selected
%     hz_list = cell2mat(keys(donor_map));
%     for i = 1:numel(hz_list)
%         d      = donor_map(hz_list(i));
%         d_unk1 = double(typecast(uint8(d(19:20)), 'uint16'));
%         d_name = strtrim(char(d(33:64)'));
%         nul    = find(d_name==0,1);
%         if ~isempty(nul), d_name = d_name(1:nul-1); end
%         fprintf('  Donor Hz=%-4d  unk1=0x%04X  name=%s\n', hz_list(i), d_unk1, d_name);
%     end
%     fprintf('  Walked %d channels.\n', count);
%     used_sr_raw = used_sr_raw(1:sr_raw_count);
% end
% 
% 
% % ======================================================================= %
% %  BUILD SYNTHETIC DONOR
% %  For Hz values not present in the file.
% %  Borrows sr_raw from the nearest known donor — i2 Pro requires non-zero.
% % ======================================================================= %
% function rec = build_synthetic_donor(sample_rate, session_dur, donor_map)
% 
%     known_hz    = cell2mat(keys(donor_map));
%     [~, idx]    = min(abs(known_hz - sample_rate));
%     near_donor  = donor_map(known_hz(idx));
%     near_sr_raw = double(typecast(uint8(near_donor(17:18)), 'uint16'));
% 
%     % Derive n_samples from nearest donor's ch_n scaled by Hz ratio.
%     % Avoids the session_dur overestimate that causes time-shift in i2 Pro.
%     near_n  = double(typecast(uint8(near_donor(13:16)), 'uint32'));
%     near_hz = known_hz(idx);
%     n_samples = round(near_n * sample_rate / near_hz);
% 
%     rec = near_donor;  % full 124-byte template — inherits tail (bytes 85-124) for correct i2 Pro timing
%     % bytes 1-12: prev/next/data ptrs — overwritten by caller
%     rec(13:16) = typecast(uint32(n_samples),    'uint8');   % data_len
%     rec(17:18) = typecast(uint16(near_sr_raw),  'uint8');   % sr_raw = catalog ID from nearest donor
%     rec(19:20) = typecast(uint16(3),            'uint8');   % unk1 = 0x0003
%     rec(21:22) = typecast(uint16(2),          'uint8');   % datatype = int16
%     rec(23:24) = typecast(uint16(sample_rate),'uint8');   % sample_rate
%     rec(25:26) = typecast(int16(0),           'uint8');   % offset = 0
%     rec(27:28) = typecast(int16(1),           'uint8');   % mul    = 1
%     rec(29:30) = typecast(int16(1),           'uint8');   % scale  = 1
%     rec(31:32) = typecast(int16(0),           'uint8');   % dec    = 0
%     % bytes 33-84: name/short/units — overwritten by caller
% 
%     fprintf('   Synthetic: Hz=%d  n=%d  sr_raw=%d (nearest donor %dHz)\n', ...
%         sample_rate, n_samples, near_sr_raw, known_hz(idx));
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
%             n_neg  = sum(raw_d < 0 & isfinite(raw_d));
%             n_over = sum(raw_d > 32767 & isfinite(raw_d));
%             if n_neg > 0
%                 warning('ld_add_channel:negativeRaw', ...
%                     '%d samples have negative raw — offset (%.3g) must be <= min(phys) (%.3g). Set ch.offset = floor(min(phys)).', ...
%                     n_neg, offset, min(phys_d(isfinite(phys_d))));
%             end
%             if n_over > 0
%                 warning('ld_add_channel:rawOverflow', ...
%                     '%d samples exceed raw limit 32767 — dec=%d, max raw=%.0f. Reduce dec_places.', ...
%                     n_over, dec, max(raw_d(isfinite(raw_d))));
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
% %  BUILD NAME INDEX
% %  Walk the linked list once, recording meta_ptr / prev_ptr / next_ptr for
% %  every channel keyed by lowercase-trimmed name. Used purely to detect and
% %  safely unlink name collisions with ch_list — never mutates anything.
% %  Last-writer-wins if duplicate names already exist in the file.
% % ======================================================================= %
% function idx = build_name_index(filepath, file_sz, META_BYTES)
%     idx = containers.Map('KeyType', 'char', 'ValueType', 'any');
%     fid = fopen(filepath, 'rb');
%     if fid < 0, error('Cannot open: %s', filepath); end
%     c = onCleanup(@() fclose(fid));
% 
%     fseek(fid, 0x0008, 'bof');
%     ptr  = fread(fid, 1, 'uint32=>double', 0, 'l');
%     prev = 0;
%     count = 0;
%     while ptr ~= 0 && ptr < file_sz
%         fseek(fid, ptr, 'bof');
%         r = fread(fid, META_BYTES, 'uint8=>uint8')';
%         next_ptr = double(typecast(uint8(r(5:8)), 'uint32'));
%         name_raw = strtrim(char(r(33:64)));
%         nul = find(name_raw == char(0), 1);
%         if ~isempty(nul), name_raw = name_raw(1:nul-1); end
%         key = lower(strtrim(name_raw));
%         if ~isempty(key)
%             idx(key) = struct('meta_ptr', ptr, 'prev_ptr', prev, 'next_ptr', next_ptr);
%         end
%         prev = ptr;
%         ptr  = next_ptr;
%         count = count + 1;
%         if count > 5000, break; end
%     end
% end
% 
% 
% % ======================================================================= %
% %  FIND NAMED DONOR
% %  Walk the linked list and return the 84-byte record whose name field
% %  matches donor_name (case-insensitive). Returns [] if not found.
% % ======================================================================= %
% function rec = find_named_donor(filepath, donor_name, file_sz, META_BYTES)
%     rec = [];
%     fid = fopen(filepath, 'rb');
%     if fid < 0, error('Cannot open: %s', filepath); end
%     c = onCleanup(@() fclose(fid));
% 
%     fseek(fid, 0x0008, 'bof');
%     ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
%     target = lower(strtrim(donor_name));
%     count = 0;
%     while ptr ~= 0 && ptr < file_sz
%         fseek(fid, ptr, 'bof');
%         r = fread(fid, META_BYTES, 'uint8=>uint8')';
%         name_raw = strtrim(char(r(33:64)));
%         nul = find(name_raw == char(0), 1);
%         if ~isempty(nul), name_raw = name_raw(1:nul-1); end
%         if strcmpi(strtrim(name_raw), target)
%             rec = r;
%             return;
%         end
%         ptr = double(typecast(uint8(r(5:8)), 'uint32'));
%         count = count + 1;
%         if count > 5000, break; end
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
% function sr_raw = find_unique_sr_raw(used_sr_raw)
%     % Find the smallest value >= 30000 not already used in the file.
%     % Range 30000-65535 is outside all known MoTeC catalog IDs (max observed ~11600).
%     candidate = uint32(30000);
%     while any(used_sr_raw == candidate)
%         candidate = candidate + 1;
%     end
%     sr_raw = double(candidate);
% end
% 
% function n = bytes_per_sample_local(datatype)
%     switch datatype
%         case {1, 2}, n = 2;
%         case {3, 4}, n = 4;
%         otherwise,   n = 2;
%     end
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
% Channel metadata records are 124 bytes (proven: gap / n_channels = 124).
% Finds a donor channel at the same Hz, copies its full 124-byte metadata
% record (including the 40-byte timing tail, bytes 85-124), patches only the
% fields we own, then stitches into the linked list.
%
% If no donor exists at the requested Hz, a synthetic record is built from
% the nearest donor — inheriting its timing tail for correct i2 Pro placement.
%
% Three separate fopen/fclose passes per channel (Windows r+b reliability):
%   Pass A  patch prev channel's next_ptr   (r+b) — verified immediately
%   Pass B  append metadata record + data   (ab)
%   Pass C  read back and verify            (rb)
%
% Usage
% -----
%   ch.name        = 'Brake Balance VCH';
%   ch.short_name  = 'BB VCH';    % optional ([] keeps donor, '' clears)
%   ch.units       = '%';         % optional ([] keeps donor, '' clears)
%   ch.value       = 60;          % scalar (repeated) or vector; absent = raw clone
%   ch.sample_rate = 5;           % Hz
%   ch.mul         = 1;           % optional scaling override
%   ch.scale       = 1;           % optional scaling override
%   ch.dec_places  = 2;           % optional — decimal places shown in i2 Pro
%   ch.offset      = 0;           % optional
%   ch.donor_name  = 'Engine Speed'; % optional — explicit named donor
%   ch.overwrite   = true;        % optional — if a channel named ch.name
%                                 % already exists in the file, unlink it
%                                 % and append this one in its place.
%                                 % Omitted/false = ERROR on name collision
%                                 % (protects against silent duplicates).
%                                 % Only channels present in ch_list are ever
%                                 % eligible for replacement — nothing else
%                                 % in the file is touched.
%   ld_add_channel('master.ld', 'output.ld', ch)

    META_BYTES = 124;
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

    [last_meta_ptr, donor_map, session_dur, used_sr_raw] = walk_and_collect(output_ld_file, file_sz, META_BYTES);

    fprintf('  Session duration      : %.1f s\n', session_dur);
    fprintf('  Last channel meta_ptr : 0x%X\n',   last_meta_ptr);
    fprintf('  Donor rates available : %s\n\n', ...
        strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), 'UniformOutput', false), ', '));

    % ------------------------------------------------------------------ %
    %  2.5 Overwrite protection — unlink any ch_list channel that already
    %      exists in the file, but ONLY channels named in ch_list.
    %      A channel is replaced iff ch.overwrite == true; otherwise a
    %      pre-existing name is a hard error (no silent duplication, no
    %      silent overwrite).
    % ------------------------------------------------------------------ %
    name_index = build_name_index(output_ld_file, file_sz, META_BYTES);

    for ci = 1:numel(ch_list)
        ch = ch_list{ci};
        key = lower(strtrim(ch.name));
        if ~isKey(name_index, key)
            continue;   % no collision — nothing to protect against
        end

        want_overwrite = isfield(ch, 'overwrite') && ~isempty(ch.overwrite) && logical(ch.overwrite(1));
        if ~want_overwrite
            warning('ld_add_channel:nameCollision', ...
                ['Channel "%s" already exists in %s — SKIPPING.\n' ...
                 'Set ch.overwrite = true on this channel struct to replace it ' ...
                 '(only channels you explicitly name are ever touched).'], ...
                 ch.name, output_ld_file);
            ch_list{ci} = [];   % mark for removal, doesn't stop the rest of the batch
            continue;
        end

        entry = name_index(key);
        fprintf('[overwrite] "%s" exists (meta_ptr=0x%X) — unlinking old record\n', ...
            ch.name, entry.meta_ptr);

        fid_u = fopen(output_ld_file, 'r+b');
        if fid_u < 0, error('Cannot open for unlink: %s', output_ld_file); end
        if entry.prev_ptr == 0
            % Removed node was the list head — patch the file header pointer.
            fseek(fid_u, 0x0008, 'bof');
            fwrite(fid_u, uint32(entry.next_ptr), 'uint32', 0, 'l');
        else
            % Patch the removed node's predecessor to skip over it.
            fseek(fid_u, entry.prev_ptr + 4, 'bof');
            fwrite(fid_u, uint32(entry.next_ptr), 'uint32', 0, 'l');
        end
        fclose(fid_u);

        % If the removed node was the current tail, the tail is now its
        % predecessor (or, if it had no predecessor, the list is empty —
        % that should never happen for a real .ld file, so just error).
        if entry.meta_ptr == last_meta_ptr
            if entry.prev_ptr == 0
                error('ld_add_channel:emptyList', ...
                    'Removing "%s" would empty the channel list — aborting.', ch.name);
            end
            last_meta_ptr = entry.prev_ptr;
        end

        remove(name_index, key);  % this name slot is now free

        % Propagate: any OTHER pending entry whose recorded prev_ptr pointed
        % at the node we just removed must be updated to point at ITS
        % predecessor instead — otherwise unlinking that entry next would
        % patch dead/orphaned space instead of the real list, and silently
        % fail to actually unlink it (leaving stale data live in the file
        % and any newly-appended replacement channel unreachable).
        remaining_keys = keys(name_index);
        for kk = 1:numel(remaining_keys)
            other = name_index(remaining_keys{kk});
            if other.prev_ptr == entry.meta_ptr
                other.prev_ptr = entry.prev_ptr;
                name_index(remaining_keys{kk}) = other;
            end
        end

        fprintf('   Unlinked. (old data bytes left in place as dead space)\n\n');
    end

    % Drop any channels skipped above due to an unresolved name collision.
    ch_list = ch_list(~cellfun(@isempty, ch_list));

    % ------------------------------------------------------------------ %
    %  3. Append each new channel
    % ------------------------------------------------------------------ %
    prev_meta_ptr   = last_meta_ptr;
    current_file_sz = file_sz;

    for ci = 1:numel(ch_list)

        ch = ch_list{ci};
        % short_name/units: keep [] if not provided — donor bytes inherited at record-write time
        if ~isfield(ch, 'short_name'), ch.short_name = []; end
        if ~isfield(ch, 'units'),      ch.units      = []; end

        fprintf('[%d/%d] "%s"  @ %d Hz\n', ci, numel(ch_list), ch.name, ch.sample_rate);

        % ---- A. Get or build donor record ---------------------------
        if isfield(ch, 'donor_name') && ~isempty(ch.donor_name)
            % Named donor: find by channel name in the file (authoritative sr_raw etc.)
            donor_rec = find_named_donor(output_ld_file, ch.donor_name, file_sz, META_BYTES);
            if isempty(donor_rec)
                error('donor_name "%s" not found in %s', ch.donor_name, output_ld_file);
            end
            d_str = strtrim(char(donor_rec(33:64)'));
            d_nul = find(d_str == char(0), 1);
            if ~isempty(d_nul), d_str = d_str(1:d_nul-1); end
            fprintf('   Donor (named): "%s"\n', d_str);
        elseif isKey(donor_map, ch.sample_rate)
            donor_rec = donor_map(ch.sample_rate);
            donor_name_raw = donor_rec(33:64);
            donor_nul = find(donor_name_raw == 0, 1);
            if ~isempty(donor_nul), donor_name_raw = donor_name_raw(1:donor_nul-1); end
            donor_name_str = strtrim(char(donor_name_raw));
            fprintf('   Donor: "%s" at %d Hz\n', donor_name_str, ch.sample_rate);
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

        % sr_raw is a sample clock group ID in i2 Pro.
        % i2 anchors every channel in a group relative to the FIRST channel
        % with that sr_raw by data_ptr:
        %   time_offset = (new_data_ptr - first_data_ptr) / (bytes_per_sample * Hz)
        % Borrowing ANY existing sr_raw causes a ~1450s offset because all native
        % data is near the start of the file and our append is at the end.
        % Fix: use an sr_raw value not present anywhere in the file so i2 Pro
        % has no reference point and anchors the channel at session t=0.
        % dec/scale/mul/offset are kept from the named donor for correct encoding.
        if isfield(ch, 'donor_name') && ~isempty(ch.donor_name)
            unique_sr_raw = find_unique_sr_raw(used_sr_raw);
            fprintf('   sr_raw: %d -> %d (unique — not in file, anchors at t=0)\n', donor_sr_raw, unique_sr_raw);
            donor_sr_raw       = unique_sr_raw;
            used_sr_raw(end+1) = unique_sr_raw; %#ok<AGROW>
        end

        % Allow direct sr_raw override (for testing/DOE)
        if isfield(ch, 'sr_raw_override')
            fprintf('   sr_raw: override -> %d\n', ch.sr_raw_override);
            donor_sr_raw = double(ch.sr_raw_override);
        end

        % Allow channel struct to override scaling fields.
        % Track whether dec_places was explicitly set by caller — only then
        % do we absorb it into scale (donor's proven dec/scale must not change).
        explicit_dec = isfield(ch, 'dec_places') && ~isempty(ch.dec_places);
        if explicit_dec
            donor_dec = ch.dec_places;
        end
        explicit_offset = isfield(ch, 'offset') && ~isempty(ch.offset);
        if explicit_offset
            donor_offset = ch.offset;
        end
        if isfield(ch, 'mul') && ~isempty(ch.mul)
            donor_mul = ch.mul;
        end
        if isfield(ch, 'scale') && ~isempty(ch.scale)
            donor_scale = ch.scale;
        end

        % --- Absorb dec_places into scale (only when caller explicitly set dec_places) ---
        % i2 Pro does not commute dec_places and scale freely — the donor's native
        % dec/scale pair must be preserved unless the caller is overriding precision.
        % When the caller sets ch.dec_places (e.g. session constants with scale=1),
        % absorb dec into scale so dec=0 is written: prevents i2 Pro sample truncation.
%         if explicit_dec && donor_dec ~= 0 && donor_mul ~= 0
%             effective_scale = donor_scale * round(10^donor_dec);
%             if effective_scale > 0 && effective_scale <= 32767
%                 fprintf('   Absorbing dec=%d into scale: %d -> %d (dec -> 0)\n', ...
%                     donor_dec, donor_scale, effective_scale);
%                 donor_scale = effective_scale;
%                 donor_dec   = 0;
%             else
%                 fprintf('   [WARN] Cannot absorb dec=%d into scale=%d (would overflow int16) — keeping dec\n', ...
%                     donor_dec, donor_scale * round(10^donor_dec));
%             end
%         end

        fprintf('   datatype=%d  Hz=%d  sr_raw=%d  mul=%d  scale=%d  dec=%d  offset=%d  n=%d\n', ...
            donor_datatype, donor_sr, donor_sr_raw, donor_mul, donor_scale, ...
            donor_dec, donor_offset, donor_n);

        % ---- B. Build raw bytes for new channel ----------------------
        % If ch.value is absent: raw copy — read donor bytes verbatim.
        % If ch.value is scalar or vector: encode via phys→raw formula.
        raw_copy_mode = ~isfield(ch, 'value') || isempty(ch.value);

        if raw_copy_mode
            % Pure clone: copy donor data bytes directly, no encode/decode.
            donor_data_ptr   = double(typecast(uint8(donor_rec(9:12)),  'uint32'));
            bps = bytes_per_sample_local(donor_datatype);
            n   = donor_n;
            fid_rc = fopen(output_ld_file, 'rb');
            if fid_rc < 0, error('Cannot open for raw copy: %s', output_ld_file); end
            fseek(fid_rc, donor_data_ptr, 'bof');
            raw_bytes = fread(fid_rc, n * bps, 'uint8=>uint8');
            fclose(fid_rc);
            fprintf('   Raw copy: %d samples  %d bytes (from 0x%X)\n', n, numel(raw_bytes), donor_data_ptr);
        else
            % Allow datatype override (default: inherit from donor)
            if isfield(ch, 'datatype') && ~isempty(ch.datatype)
                donor_datatype = ch.datatype;
            end
            % Scalars: use donor_n so the channel is time-aligned with natives.
            % Vectors: caller owns sample count.
            if isscalar(ch.value)
                n    = donor_n;
                phys = repmat(double(ch.value), n, 1);
                fprintf('   n from donor_n=%d (%.1f s @ %d Hz)\n', n, n/ch.sample_rate, ch.sample_rate);
            else
                n    = numel(ch.value);
                phys = double(ch.value(:));
            end
            % Auto-shift so raw values are always non-negative and fit int16,
            % UNLESS the caller explicitly set ch.offset — a borrowed donor's
            % offset (from an unrelated channel at the same Hz) is never a
            % reliable signal that "this was already handled".
            % i2 applies header offset on read: physical = raw_uint16 / 10^dec + offset.
            if ~explicit_offset
                finite_phys = phys(isfinite(phys));
                if ~isempty(finite_phys)
                    lo = min(finite_phys);
                    hi = max(finite_phys);
                    needs_fix = lo < 0 || (hi - donor_offset) * 10^donor_dec > 32767;
                    if needs_fix
                        donor_offset = max(floor(lo) - 1, -32767);
                        if (hi - donor_offset) * 10^donor_dec > 32767
                            warning('ld_add_channel:rawOverflow', ...
                                '"%s": raw overflow — reduce dec_places', ch.name);
                        end
                    end
                end
            end
            raw_bytes = encode_phys(phys, donor_datatype, donor_offset, ...
                                     donor_mul, donor_scale, donor_dec);
            fprintf('   Encoded: %d samples  %d bytes\n', n, numel(raw_bytes));
        end

        % ---- C. Compute pointer positions ---------------------------
        new_meta_ptr = current_file_sz;

        % TIMING DIAGNOSTIC: in raw_copy_mode we can optionally point data_ptr
        % back to the donor's original data instead of the appended copy.
        % If i2 Pro uses data_ptr for timing, this will make the clone perfectly
        % time-aligned. Set ch.use_donor_data_ptr = true to enable.
        use_donor_ptr = raw_copy_mode && isfield(ch, 'use_donor_data_ptr') && ch.use_donor_data_ptr;
        if use_donor_ptr
            new_data_ptr = double(typecast(uint8(donor_rec(9:12)), 'uint32'));
            fprintf('   data_ptr: using donor ptr 0x%X (timing test)\n', new_data_ptr);
        else
            new_data_ptr = new_meta_ptr + META_BYTES;
        end
        fprintf('   new_meta_ptr=0x%X  new_data_ptr=0x%X\n', new_meta_ptr, new_data_ptr);

        % ---- D. Build metadata record from donor template -----------
        rec = donor_rec;
        rec(1:4)   = typecast(uint32(prev_meta_ptr),  'uint8');  % prev_ptr
        rec(5:8)   = typecast(uint32(0),              'uint8');  % next_ptr = 0
        rec(9:12)  = typecast(uint32(new_data_ptr),   'uint8');  % data_ptr
        rec(13:16) = typecast(uint32(n),              'uint8');  % data_len
        rec(17:18) = typecast(uint16(donor_sr_raw),   'uint8');  % sr_raw (may be collision-replaced above)
        rec(21:22) = typecast(uint16(donor_datatype), 'uint8');  % datatype
        rec(23:24) = typecast(uint16(ch.sample_rate), 'uint8');  % sample_rate (true Hz)
        rec(25:26) = typecast(int16(donor_offset),    'uint8');  % ch_offset
        rec(27:28) = typecast(int16(donor_mul),       'uint8');  % ch_mul
        rec(29:30) = typecast(int16(donor_scale),     'uint8');  % ch_scale
        rec(31:32) = typecast(int16(donor_dec),       'uint8');  % dec_places
        rec(33:64) = str_to_bytes(ch.name, 32);
%         if ~isempty(ch.short_name)
if ischar(ch.short_name)   % [] = keep donor; '' = write zeros (clears donor)
            rec(65:72) = str_to_bytes(ch.short_name, 8);
        end
%         if ~isempty(ch.units)
if ischar(ch.units)        % [] = keep donor; '' = write zeros (clears donor)
            rec(73:84) = str_to_bytes(ch.units, 12);
        end
        fprintf('   sr_raw written: %d  (Hz=%d)\n', donor_sr_raw, ch.sample_rate);

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
        if raw_copy_mode
            % Raw copy: verify byte-for-byte match.
            fid_rc2 = fopen(output_ld_file, 'rb');
            fseek(fid_rc2, new_data_ptr, 'bof');
            rb_raw = fread(fid_rc2, numel(raw_bytes), 'uint8=>uint8');
            fclose(fid_rc2);
            if isequal(raw_bytes(:), rb_raw(:))
                fprintf('   Pass C: [PASS] raw copy verified  (%d bytes)\n\n', numel(raw_bytes));
            else
                fprintf('   Pass C: [FAIL] raw copy mismatch\n\n');
            end
        else
            % Encoded: tolerance = half a stored unit + epsilon guard.
            % (0.05 is not exactly representable in IEEE 754 — without epsilon
            %  max_err > tol can be true when they are nominally equal.)
            if donor_dec >= 0 && donor_scale > 0
                pass_c_tol = max(0.5 * donor_mul / donor_scale / (10^donor_dec), 1e-9);
                pass_c_tol = pass_c_tol * (1 + 1e-6);
            else
                pass_c_tol = FLOAT_TOL;
            end
            [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, ...
                new_data_ptr, n, donor_datatype, donor_offset, ...
                donor_mul, donor_scale, donor_dec);
            if ~rb_ok
                fprintf('   Pass C: [FAIL] %s\n\n', rb_err);
            else
                max_err = max(abs(rb_phys - phys));
                if max_err > pass_c_tol
                    fprintf('   Pass C: [FAIL] max_err=%.6f  (tol=%.6f)\n\n', max_err, pass_c_tol);
                else
                    fprintf('   Pass C: [PASS] max_err=%.2e  value=%.4g\n\n', max_err, rb_phys(1));
                end
            end
        end

    end

    % ------------------------------------------------------------------ %
    %  4. Delete stale .ldx cache (if present)
    % ------------------------------------------------------------------ %
    [ldx_dir, ldx_base] = fileparts(output_ld_file);
    ldx_path = fullfile(ldx_dir, [ldx_base '.ldx']);
    if exist(ldx_path, 'file')
        delete(ldx_path);
        if ~exist(ldx_path, 'file')
            fprintf('  Deleted stale .ldx: %s\n', ldx_path);
        else
            fprintf('  WARNING: could not delete .ldx (close i2 Pro): %s\n', ldx_path);
        end
    end

    % ------------------------------------------------------------------ %
    %  5. Summary
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
function [last_meta_ptr, donor_map, session_dur, used_sr_raw] = walk_and_collect(filepath, file_sz, META_BYTES) %#ok

    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if current_ptr == 0 || current_ptr >= file_sz
        error('Invalid first_meta_ptr: 0x%X', current_ptr);
    end

    donor_map     = containers.Map('KeyType', 'double', 'ValueType', 'any');
    donor_n_map   = containers.Map('KeyType', 'double', 'ValueType', 'double');  % track best ch_n per Hz
    last_meta_ptr = current_ptr;
    session_dur   = 0;
    used_sr_raw   = zeros(1, 2000, 'double');  % pre-alloc for speed
    sr_raw_count  = 0;
    count         = 0;

    while current_ptr ~= 0 && current_ptr < file_sz
        fseek(fid, current_ptr, 'bof');
        rec      = fread(fid, META_BYTES, 'uint8=>uint8');
        next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
        sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
        unk1     = double(typecast(uint8(rec(19:20)), 'uint16'));
        sr_raw_val           = double(typecast(uint8(rec(17:18)), 'uint16'));
        sr_raw_count         = sr_raw_count + 1;
        used_sr_raw(sr_raw_count) = sr_raw_val;
        ch_n     = double(typecast(uint8(rec(13:16)), 'uint32'));

        % Compute session duration from ALL channels — use maximum
        if sr > 0 && ch_n > 0
            dur_this = ch_n / sr;
            if dur_this > session_dur
                session_dur = dur_this;
            end
        end

        % Select donor at each Hz: prefer highest ch_n (longest coverage),
        % with secondary preference for unk1=0x0003
        if sr > 0 && ch_n > 0
            best_n = 0;
            if isKey(donor_n_map, sr), best_n = donor_n_map(sr); end
            existing_unk1 = 0;
            if isKey(donor_map, sr)
                existing_rec  = donor_map(sr);
                existing_unk1 = double(typecast(uint8(existing_rec(19:20)), 'uint16'));
            end
            if ch_n > best_n || (ch_n == best_n && unk1 == 3 && isKey(donor_map, sr) && ...
                    existing_unk1 ~= 3)
                donor_map(sr)   = rec;
                donor_n_map(sr) = ch_n;
            end
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
    used_sr_raw = used_sr_raw(1:sr_raw_count);
end


% ======================================================================= %
%  BUILD SYNTHETIC DONOR
%  For Hz values not present in the file.
%  Borrows sr_raw from the nearest known donor — i2 Pro requires non-zero.
% ======================================================================= %
function rec = build_synthetic_donor(sample_rate, session_dur, donor_map)

    known_hz    = cell2mat(keys(donor_map));
    [~, idx]    = min(abs(known_hz - sample_rate));
    near_donor  = donor_map(known_hz(idx));
    near_sr_raw = double(typecast(uint8(near_donor(17:18)), 'uint16'));

    % Derive n_samples from nearest donor's ch_n scaled by Hz ratio.
    % Avoids the session_dur overestimate that causes time-shift in i2 Pro.
    near_n  = double(typecast(uint8(near_donor(13:16)), 'uint32'));
    near_hz = known_hz(idx);
    n_samples = round(near_n * sample_rate / near_hz);

    rec = near_donor;  % full 124-byte template — inherits tail (bytes 85-124) for correct i2 Pro timing
    % bytes 1-12: prev/next/data ptrs — overwritten by caller
    rec(13:16) = typecast(uint32(n_samples),    'uint8');   % data_len
    rec(17:18) = typecast(uint16(near_sr_raw),  'uint8');   % sr_raw = catalog ID from nearest donor
    rec(19:20) = typecast(uint16(3),            'uint8');   % unk1 = 0x0003
    rec(21:22) = typecast(uint16(2),          'uint8');   % datatype = int16
    rec(23:24) = typecast(uint16(sample_rate),'uint8');   % sample_rate
    rec(25:26) = typecast(int16(0),           'uint8');   % offset = 0
    rec(27:28) = typecast(int16(1),           'uint8');   % mul    = 1
    rec(29:30) = typecast(int16(1),           'uint8');   % scale  = 1
    rec(31:32) = typecast(int16(0),           'uint8');   % dec    = 0
    % bytes 33-84: name/short/units — overwritten by caller

    fprintf('   Synthetic: Hz=%d  n=%d  sr_raw=%d (nearest donor %dHz)\n', ...
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
            n_neg  = sum(raw_d < 0 & isfinite(raw_d));
            n_over = sum(raw_d > 32767 & isfinite(raw_d));
            if n_neg > 0
                warning('ld_add_channel:negativeRaw', ...
                    '%d samples have negative raw — offset (%.3g) must be <= min(phys) (%.3g). Set ch.offset = floor(min(phys)).', ...
                    n_neg, offset, min(phys_d(isfinite(phys_d))));
            end
            if n_over > 0
                warning('ld_add_channel:rawOverflow', ...
                    '%d samples exceed raw limit 32767 — dec=%d, max raw=%.0f. Reduce dec_places.', ...
                    n_over, dec, max(raw_d(isfinite(raw_d))));
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
%  BUILD NAME INDEX
%  Walk the linked list once, recording meta_ptr / prev_ptr / next_ptr for
%  every channel keyed by lowercase-trimmed name. Used purely to detect and
%  safely unlink name collisions with ch_list — never mutates anything.
%  Last-writer-wins if duplicate names already exist in the file.
% ======================================================================= %
function idx = build_name_index(filepath, file_sz, META_BYTES)
    idx = containers.Map('KeyType', 'char', 'ValueType', 'any');
    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    ptr  = fread(fid, 1, 'uint32=>double', 0, 'l');
    prev = 0;
    count = 0;
    while ptr ~= 0 && ptr < file_sz
        fseek(fid, ptr, 'bof');
        r = fread(fid, META_BYTES, 'uint8=>uint8')';
        next_ptr = double(typecast(uint8(r(5:8)), 'uint32'));
        name_raw = strtrim(char(r(33:64)));
        nul = find(name_raw == char(0), 1);
        if ~isempty(nul), name_raw = name_raw(1:nul-1); end
        key = lower(strtrim(name_raw));
        if ~isempty(key)
            idx(key) = struct('meta_ptr', ptr, 'prev_ptr', prev, 'next_ptr', next_ptr);
        end
        prev = ptr;
        ptr  = next_ptr;
        count = count + 1;
        if count > 5000, break; end
    end
end


% ======================================================================= %
%  FIND NAMED DONOR
%  Walk the linked list and return the 84-byte record whose name field
%  matches donor_name (case-insensitive). Returns [] if not found.
% ======================================================================= %
function rec = find_named_donor(filepath, donor_name, file_sz, META_BYTES)
    rec = [];
    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    target = lower(strtrim(donor_name));
    count = 0;
    while ptr ~= 0 && ptr < file_sz
        fseek(fid, ptr, 'bof');
        r = fread(fid, META_BYTES, 'uint8=>uint8')';
        name_raw = strtrim(char(r(33:64)));
        nul = find(name_raw == char(0), 1);
        if ~isempty(nul), name_raw = name_raw(1:nul-1); end
        if strcmpi(strtrim(name_raw), target)
            rec = r;
            return;
        end
        ptr = double(typecast(uint8(r(5:8)), 'uint32'));
        count = count + 1;
        if count > 5000, break; end
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

function sr_raw = find_unique_sr_raw(used_sr_raw)
    % Find the smallest value >= 30000 not already used in the file.
    % Range 30000-65535 is outside all known MoTeC catalog IDs (max observed ~11600).
    candidate = uint32(30000);
    while any(used_sr_raw == candidate)
        candidate = candidate + 1;
    end
    sr_raw = double(candidate);
end

function n = bytes_per_sample_local(datatype)
    switch datatype
        case {1, 2}, n = 2;
        case {3, 4}, n = 4;
        otherwise,   n = 2;
    end
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