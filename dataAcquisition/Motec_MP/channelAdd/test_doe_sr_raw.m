%% test_doe_sr_raw.m
% DOE: vary sr_raw only — everything else identical to native channel.
% Each test channel = Laser Ride Height Rear + 3mm, same metadata,
% only sr_raw differs. Open output in i2 Pro and note which align.

clear; clc;

SOURCE_FILE = 'E:\2026\T01_QLR\COM\20260505-156890014_combined.ld';
OUTPUT_FILE = 'E:\2026\T01_QLR\COM\doe_sr_raw_test.ld';
DONOR_NAME  = 'Laser Ride Height Rear';
OFFSET_MM   = 3;

ch_add_dir = fileparts(mfilename('fullpath'));
if ~any(strcmp(strsplit(path, pathsep), ch_add_dir)), addpath(ch_add_dir); end

%% Read donor data
fprintf('=== Reading source ===\n');
src     = motec_ld_reader(SOURCE_FILE, {DONOR_NAME});
fn      = (regexprep(DONOR_NAME, '[^a-zA-Z0-9]', '_'));
orig    = src.(fn).data + OFFSET_MM;
orig_sr = src.(fn).sample_rate;
fprintf('  n=%d  sr=%d Hz\n\n', numel(orig), orig_sr);

%% DOE table
% A = native sr_raw (same as original — collision risk but maybe required)
% B = Hz-matched donor sr_raw (current approach)
% C = zero
% D = 1
% E = native + 1
doe_sr   = [9102,  11600,              0,    1,        9103             ];
doe_name = {'A_sr9102_native', 'B_sr11600_hzmatch', 'C_sr0_zero', 'D_sr1_one', 'E_sr9103_nativep1'};

%% Build channel list — sr_raw_override set directly, no post-hoc patching
ch = struct([]);
for i = 1:numel(doe_sr)
    ch(i).name            = doe_name{i};
    ch(i).donor_name      = DONOR_NAME;   % inherits short_name, units, dec/scale
    ch(i).value           = orig;
    ch(i).sample_rate     = orig_sr;
    ch(i).sr_raw_override = doe_sr(i);    % written directly into bytes 17-18
end

%% Write
ld_add_channel(SOURCE_FILE, OUTPUT_FILE, ch);

%% Summary
fprintf('\n=== DOE summary ===\n');
fprintf('  %-30s  %s\n', 'Channel', 'sr_raw');
fprintf('  %s\n', repmat('-', 1, 45));
for i = 1:numel(doe_sr)
    fprintf('  %-30s  %d\n', doe_name{i}, doe_sr(i));
end
fprintf('\nOpen in i2 Pro and search "sr" in channels panel.\n');
fprintf('Note which of A-E are time-aligned with Laser Ride Height Rear.\n');
fprintf('\n  %s\n', OUTPUT_FILE);
