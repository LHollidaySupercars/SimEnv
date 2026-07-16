%% debug_decimal_encoding.m
% Adds many "Density" channels to a single .ld file, each with a different
% combination of dec_places / mul / scale / offset.
% Open the output in i2 Pro and check which channel shows the correct value.
%
% Test value: DENSITY_VAL (e.g. 0.742 kg/L)

clear; clc;

%% =========================================================
%  CONFIG
%% =========================================================
SOURCE_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';
OUTPUT_FILE = 'E:\2026\T01_QLR\COM\debug_decimal_encoding.ld';

DENSITY_VAL = 0.742;   % kg/L — the physical value we want to see in i2
SAMPLE_RATE = 5;       % Hz — must have a donor at this rate in the file

%% =========================================================
%  SETUP
%% =========================================================
ch_add_dir = fileparts(mfilename('fullpath'));
if ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

%% =========================================================
%  BUILD CHANNEL MATRIX
%  Vary dec_places (0-4), mul/scale pairs, offset
%% =========================================================

% dec_places to try
dec_vals = [0, 1, 2, 3, 4];

% mul/scale combinations (physical = raw * mul/scale / 10^dec + offset)
mul_scale_pairs = [
    1,  1;   % standard: mul=scale=1, ratio=1
    1, 10;   % ratio = 0.1
   10,  1;   % ratio = 10
    1,  1;   % repeated with offset != 0 (see below)
];

offsets = [0, 0, 0, 1];   % offset per mul/scale row above

ch = struct([]);
ci = 0;

for di = 1:numel(dec_vals)
    dec = dec_vals(di);
    for msi = 1:size(mul_scale_pairs, 1)
        mul    = mul_scale_pairs(msi, 1);
        sc     = mul_scale_pairs(msi, 2);
        offs   = offsets(msi);

        % Predict what raw int16 will be written and what i2 will decode
        % encode: raw = (phys - offset) * 10^dec * scale/mul
        if sc ~= 0 && mul ~= 0
            raw_pred = (DENSITY_VAL - offs) * (10^dec) * (sc / mul);
        else
            raw_pred = (DENSITY_VAL - offs) * (10^dec);
        end
        raw_int = round(raw_pred);

        % Skip if overflows int16
        if abs(raw_int) > 32767
            continue;
        end

        % decode: phys = raw * mul/scale / 10^dec + offset
        if sc ~= 0 && mul ~= 0
            decoded = raw_int * (mul/sc) / (10^dec) + offs;
        else
            decoded = raw_int / (10^dec) + offs;
        end

        err = abs(decoded - DENSITY_VAL);

        ci = ci + 1;
        label = sprintf('Den d%d m%d s%d o%d', dec, mul, sc, offs);
        ch(ci).name        = label;
        ch(ci).short_name  = label(1:min(end,7));
        ch(ci).units       = 'kg/L';
        ch(ci).value       = DENSITY_VAL;
        ch(ci).sample_rate = SAMPLE_RATE;
        ch(ci).dec_places  = dec;
        ch(ci).mul         = mul;
        ch(ci).scale       = sc;
        ch(ci).offset      = offs;

        fprintf('Ch %-22s  raw=%6d  decoded=%.5f  err=%.5f%s\n', ...
            label, raw_int, decoded, err, iif(err < 5e-4, '  <-- EXACT', ''));
    end
end

fprintf('\nTotal channels to write: %d\n\n', ci);

%% =========================================================
%  WRITE
%% =========================================================
if exist(OUTPUT_FILE, 'file'), delete(OUTPUT_FILE); end
ld_add_channel(SOURCE_FILE, OUTPUT_FILE, ch);

%% =========================================================
%  READ BACK + REPORT
%% =========================================================
fprintf('\n=== Read-back verification ===\n');
out = motec_ld_reader(OUTPUT_FILE);
out_fns = fieldnames(out);

san = @(s) lower(regexprep(regexprep(s, '[^a-zA-Z0-9]', '_'), '_+', '_'));

fprintf('\n%-24s  %8s  %8s  %8s  %s\n', 'Channel', 'expected', 'readback', 'error', 'Status');
fprintf('%s\n', repmat('-', 1, 65));

for ci = 1:numel(ch)
    target = san(ch(ci).name);
    fn = '';
    for fi = 1:numel(out_fns)
        if strcmpi(out_fns{fi}, target) || strcmpi(out_fns{fi}, regexprep(target,'_+$',''))
            fn = out_fns{fi}; break;
        end
    end
    if isempty(fn)
        fprintf('%-24s  NOT FOUND\n', ch(ci).name);
        continue;
    end
    rb  = out.(fn).data(1);
    err = abs(rb - DENSITY_VAL);
    if err < 5e-4
        status = 'PASS';
    else
        status = sprintf('FAIL  (dec=%d mul=%d scale=%d offs=%d)', ...
            ch(ci).dec_places, ch(ci).mul, ch(ci).scale, ch(ci).offset);
    end
    fprintf('%-24s  %8.4f  %8.4f  %8.5f  %s\n', ch(ci).name, DENSITY_VAL, rb, err, status);
end

fprintf('\nOpen in i2:\n  %s\n', OUTPUT_FILE);
fprintf('Look for the channel that shows %.4f\n', DENSITY_VAL);

%% =========================================================
%  LOCAL HELPER
%% =========================================================
function out = iif(cond, a, b)
    if cond, out = a; else, out = b; end
end
