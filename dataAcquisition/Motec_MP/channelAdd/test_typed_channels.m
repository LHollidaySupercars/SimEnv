%% test_typed_channels.m
% Creates channels of several physical types, verifies readback, and lists
% what to inspect in i2 Pro.  No ch.donor_name — auto-donor from file.
%
% Types exercised:
%   CH1 : Percentage constant    (73.50 %,   50 Hz, dec=2)
%   CH2 : Integer ramp           (0-9999,    100 Hz, dec=0)
%   CH3 : Small float constant   (2.345 mm,  100 Hz, dec=3)
%   CH4 : Signed constant        (-6.25 g,    50 Hz, scale=100)
%   CH5 : Low-rate constant      (1234.5 rpm,  5 Hz, dec=1)
%   CH6 : With offset            (35.7 degC,  10 Hz, offset=20, scale=10)
%   CH7 : Sine wave vector       (±1 V,       50 Hz, dec=4)
%   CH8 : Boolean flag           (0/1,        100 Hz, dec=0)
%
% All channels target the single-session Dash file.
% Available Hz tiers in file: 5, 10, 50, 100, 500.

clear; clc;

SOURCE_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';
OUTPUT_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890002_typed_test.ld';

ch_add_dir = fileparts(mfilename('fullpath'));
if ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

% Session has 36800 samples at 100 Hz  (= 368 s)
N100 = 36800;
N50  = 18400;
N10  =  3680;
N5   =  1840;

%% -----------------------------------------------------------------------
%  CH1: Percentage constant — 73.50 %
%       raw = round(73.5 * 10^2) = 7350   phys = 7350/1/100 + 0 = 73.50
% -----------------------------------------------------------------------
ch(1).name        = 'Test Pct Channel';
ch(1).short_name  = 'Pct';
ch(1).units       = '%';
ch(1).sample_rate = 50;
ch(1).value       = 73.5;            % scalar → repeated N50 times
ch(1).mul         = 1;
ch(1).scale       = 1;
ch(1).dec_places  = 2;
ch(1).offset      = 0;
expected(1).val   = 73.5;
expected(1).tol   = 0.005;           % half of 1 LSB at dec=2

%% -----------------------------------------------------------------------
%  CH2: Integer ramp — sawtooth 0-9999 at 100 Hz
%       dec=0, scale=1 → raw = value exactly
% -----------------------------------------------------------------------
ch(2).name        = 'Test Int Channel';
ch(2).short_name  = 'IntCnt';
ch(2).units       = 'count';
ch(2).sample_rate = 100;
ch(2).value       = mod(0:N100-1, 10000)';   % sawtooth 0-9999
ch(2).mul         = 1;
ch(2).scale       = 1;
ch(2).dec_places  = 0;
ch(2).offset      = 0;
expected(2).val   = ch(2).value;
expected(2).tol   = 0.5;             % half LSB at dec=0

%% -----------------------------------------------------------------------
%  CH3: Small float constant — 2.345 mm
%       raw = round(2.345 * 10^3) = 2345   phys = 2345/1000 = 2.345
% -----------------------------------------------------------------------
ch(3).name        = 'Test Float Channel';
ch(3).short_name  = 'Flt';
ch(3).units       = 'mm';
ch(3).sample_rate = 100;
ch(3).value       = 2.345;
ch(3).mul         = 1;
ch(3).scale       = 1;
ch(3).dec_places  = 3;
ch(3).offset      = 0;
expected(3).val   = 2.345;
expected(3).tol   = 0.0005;

%% -----------------------------------------------------------------------
%  CH4: Signed constant — -6.25 g
%       scale=100 → raw = round(-6.25 * 100) = -625   phys = -625/100 = -6.25
% -----------------------------------------------------------------------
ch(4).name        = 'Test Signed Channel';
ch(4).short_name  = 'Sgn';
ch(4).units       = 'g';
ch(4).sample_rate = 50;
ch(4).value       = -6.25;
ch(4).mul         = 1;
ch(4).scale       = 100;
ch(4).dec_places  = 0;
ch(4).offset      = 0;
expected(4).val   = -6.25;
expected(4).tol   = 0.005;

%% -----------------------------------------------------------------------
%  CH5: Low-rate constant — 1234.5 rpm at 5 Hz
%       dec=1 → raw = round(1234.5 * 10) = 12345   phys = 12345/10 = 1234.5
% -----------------------------------------------------------------------
ch(5).name        = 'Test LowRate Channel';
ch(5).short_name  = 'LowRt';
ch(5).units       = 'rpm';
ch(5).sample_rate = 5;
ch(5).value       = 1234.5;
ch(5).mul         = 1;
ch(5).scale       = 1;
ch(5).dec_places  = 1;
ch(5).offset      = 0;
expected(5).val   = 1234.5;
expected(5).tol   = 0.05;

%% -----------------------------------------------------------------------
%  CH6: Value with offset — 35.7 degC
%       offset=20, scale=10 → raw = round((35.7-20)*10) = 157   phys = 157/10+20 = 35.7
% -----------------------------------------------------------------------
ch(6).name        = 'Test Offset Channel';
ch(6).short_name  = 'OffTmp';
ch(6).units       = 'degC';
ch(6).sample_rate = 10;
ch(6).value       = 35.7;
ch(6).mul         = 1;
ch(6).scale       = 10;
ch(6).dec_places  = 0;
ch(6).offset      = 20;
expected(6).val   = 35.7;
expected(6).tol   = 0.05;

%% -----------------------------------------------------------------------
%  CH7: Sine wave vector — ±1 V at 50 Hz over full session
%       dec=4 → resolution 0.0001 V
% -----------------------------------------------------------------------
t_50hz          = (0:N50-1)' / 50;
ch(7).name        = 'Test Sine Channel';
ch(7).short_name  = 'Sine';
ch(7).units       = 'V';
ch(7).sample_rate = 50;
ch(7).value       = sin(2*pi*0.5*t_50hz);   % 0.5 Hz sine, amplitude 1 V
ch(7).mul         = 1;
ch(7).scale       = 1;
ch(7).dec_places  = 4;
ch(7).offset      = 0;
expected(7).val   = ch(7).value;
expected(7).tol   = 5e-5;            % half LSB at dec=4

%% -----------------------------------------------------------------------
%  CH8: Boolean flag — alternates 0/1 every 100 samples at 100 Hz
%       dec=0, scale=1 → raw = 0 or 1
% -----------------------------------------------------------------------
flag             = double(mod(floor((0:N100-1)/100), 2))';
ch(8).name        = 'Test Bool Channel';
ch(8).short_name  = 'Bool';
ch(8).units       = '';
ch(8).sample_rate = 100;
ch(8).value       = flag;
ch(8).mul         = 1;
ch(8).scale       = 1;
ch(8).dec_places  = 0;
ch(8).offset      = 0;
expected(8).val   = flag;
expected(8).tol   = 0.5;

%% -----------------------------------------------------------------------
%  Write all channels
% -----------------------------------------------------------------------
fprintf('Source : %s\n',  SOURCE_FILE);
fprintf('Output : %s\n\n', OUTPUT_FILE);

ld_add_channel(SOURCE_FILE, OUTPUT_FILE, ch);

%% -----------------------------------------------------------------------
%  Readback verification — walk output file, find each channel by name,
%  decode, compare against expected.
% -----------------------------------------------------------------------
fprintf('\n=== READBACK VERIFICATION ===\n');
fprintf('%-25s  %-8s  %-12s  %-12s  %s\n', 'Channel', 'n_samp', 'val[1]', 'expected', 'Result');
fprintf('%s\n', repmat('-', 1, 75));

META_BYTES = 124;
fid = fopen(OUTPUT_FILE, 'rb');
fseek(fid, 0, 'eof'); fsz = ftell(fid);
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
fclose(fid);

% Walk once, collect all records
MAX_CH = 5000;
rb_names    = cell(MAX_CH,1);
rb_n        = zeros(MAX_CH,1);
rb_data_ptr = zeros(MAX_CH,1);
rb_dtype    = zeros(MAX_CH,1);
rb_offset   = zeros(MAX_CH,1);
rb_mul      = zeros(MAX_CH,1);
rb_scale    = zeros(MAX_CH,1);
rb_dec      = zeros(MAX_CH,1);
rb_next     = zeros(MAX_CH,1);
k = 0;
fid2 = fopen(OUTPUT_FILE, 'rb');
cur = ptr;
while cur ~= 0 && cur < fsz && k < MAX_CH
    fseek(fid2, cur, 'bof');
    r = fread(fid2, META_BYTES, 'uint8=>uint8')';
    if numel(r) < META_BYTES, break; end
    k = k+1;
    rb_next(k)     = double(typecast(r(5:8),   'uint32'));
    rb_data_ptr(k) = double(typecast(r(9:12),  'uint32'));
    rb_n(k)        = double(typecast(r(13:16), 'uint32'));
    rb_dtype(k)    = double(typecast(r(21:22), 'uint16'));
    rb_offset(k)   = double(typecast(r(25:26), 'int16'));
    rb_mul(k)      = double(typecast(r(27:28), 'int16'));
    rb_scale(k)    = double(typecast(r(29:30), 'int16'));
    rb_dec(k)      = double(typecast(r(31:32), 'int16'));
    nb = r(33:64); nz = find(nb==0,1);
    if isempty(nz), rb_names{k} = deblank(char(nb'));
    elseif nz==1,   rb_names{k} = '';
    else,           rb_names{k} = char(nb(1:nz-1)'); end
    cur = rb_next(k);
end
fclose(fid2);
n_found = k;
rb_names    = rb_names(1:n_found);
rb_data_ptr = rb_data_ptr(1:n_found);
rb_n        = rb_n(1:n_found);
rb_dtype    = rb_dtype(1:n_found);
rb_offset   = rb_offset(1:n_found);
rb_mul      = rb_mul(1:n_found);
rb_scale    = rb_scale(1:n_found);
rb_dec      = rb_dec(1:n_found);

n_pass = 0; n_fail = 0;
for ci = 1:numel(ch)
    idx = find(strcmpi(rb_names, ch(ci).name), 1);
    if isempty(idx)
        fprintf('%-25s  NOT FOUND IN OUTPUT\n', ch(ci).name);
        n_fail = n_fail + 1;
        continue;
    end

    % Decode
    fid3 = fopen(OUTPUT_FILE, 'rb');
    fseek(fid3, rb_data_ptr(idx), 'bof');
    nn = rb_n(idx);
    switch rb_dtype(idx)
        case 2
            raw = fread(fid3, nn, 'int16=>double', 0, 'l');
            if rb_scale(idx) ~= 0 && rb_mul(idx) ~= 0
                phys = raw .* (rb_mul(idx)/rb_scale(idx)) ./ (10^rb_dec(idx)) + rb_offset(idx);
            else
                phys = raw ./ (10^rb_dec(idx)) + rb_offset(idx);
            end
        case 4
            raw  = fread(fid3, nn, 'int16=>double', 2, 'l');
            phys = raw ./ (10^rb_dec(idx)) + rb_offset(idx);
        otherwise
            fclose(fid3);
            fprintf('%-25s  unsupported dtype %d\n', ch(ci).name, rb_dtype(idx));
            n_fail = n_fail + 1;
            continue;
    end
    fclose(fid3);

    % Compare
    exp_val = expected(ci).val;
    tol     = expected(ci).tol;
    if isscalar(exp_val)
        max_err = max(abs(phys - exp_val));
        val1_str = sprintf('%.5g', phys(1));
        exp_str  = sprintf('%.5g', exp_val);
    else
        max_err  = max(abs(phys - exp_val));
        val1_str = sprintf('%.5g', phys(1));
        exp_str  = sprintf('%.5g', exp_val(1));
    end

    if max_err <= tol
        result = 'PASS';
        n_pass = n_pass + 1;
    else
        result = sprintf('FAIL  max_err=%.2e tol=%.2e', max_err, tol);
        n_fail = n_fail + 1;
    end
    fprintf('%-25s  %-8d  %-12s  %-12s  %s\n', ch(ci).name, nn, val1_str, exp_str, result);
end
fprintf('%s\n', repmat('-', 1, 75));
fprintf('  %d/%d PASS\n\n', n_pass, numel(ch));

%% -----------------------------------------------------------------------
%  i2 Pro checklist
% -----------------------------------------------------------------------
fprintf('=== OPEN IN i2 PRO ===\n');
fprintf('  File: %s\n\n', OUTPUT_FILE);
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Channel name', 'Hz', 'Expected', 'Shape');
fprintf('  %s\n', repmat('-', 1, 65));
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Pct Channel',    '50 Hz',  '73.50 %',    'flat line');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Int Channel',    '100 Hz', '0-9999',      'sawtooth ramp');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Float Channel',  '100 Hz', '2.345 mm',    'flat line');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Signed Channel', '50 Hz',  '-6.25 g',     'flat line (negative)');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test LowRate Channel','5 Hz',   '1234.5 rpm',  'flat line (stepped)');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Offset Channel', '10 Hz',  '35.7 degC',   'flat line');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Sine Channel',   '50 Hz',  '+/-1 V',      '0.5 Hz sine wave');
fprintf('  %-25s  %-8s  %-12s  %s\n', 'Test Bool Channel',   '100 Hz', '0 or 1',      'square wave 1s period');
fprintf('\n  ALL channels should start at session t=0 with NO time offset.\n');
