%% test_clone_ride_height.m
% Tests for diagnosing i2 Pro time offset on appended/prepended channels.
%
%   TEST SS:   Single-session source file (not combined) — if offset disappears,
%              the combined file's session registry is the root cause.
%   TEST A:    PREPEND on combined file (rules out meta_ptr position — already done).
%   TEST B:    APPEND raw clone on combined file (control — expect ~1450s offset).
%   TEST C:    APPEND +3mm offset on combined file.

clear; clc;

SOURCE_FILE    = 'E:\2026\T01_QLR\COM\20260505-156890014_combined.ld';
OUTPUT_FILE    = 'E:\2026\T01_QLR\COM\20260505-156890014_rh_offset_test.ld';
OUTPUT_FILE2   = 'E:\2026\T01_QLR\COM\20260505-156890014_rh_prepend_test.ld';

% Single-session source: one raw .ld file (NOT combined).
% Change this to any single-session .ld file that contains Laser Ride Height Rear.
SOURCE_SS_FILE = 'E:\2026\T01_QLR\COM\20260505-156890002.ld';
OUTPUT_SS_FILE = 'E:\2026\T01_QLR\COM\20260505-156890002_rh_prepend_test.ld';

DONOR_NAME = 'Laser Ride Height Rear';

%% -- Add channelAdd dir to path ----------------------------------------
ch_add_dir = fileparts(mfilename('fullpath'));
if ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

%% ======================================================================
%  TEST SS: PREPEND on SINGLE-SESSION file
%  Key diagnostic: if offset disappears → combined file session registry
%  is the root cause, not anything in channel metadata.
%  ======================================================================
fprintf('\n\n=== TEST SS: PREPEND on single-session file ===\n');
fprintf('Source: %s\n\n', SOURCE_SS_FILE);

if ~exist(SOURCE_SS_FILE, 'file')
    fprintf('[SKIP] SOURCE_SS_FILE not found — update path at top of script.\n\n');
else
    ch_ss.name        = 'Laser RH Rear Prepend';
    ch_ss.donor_name  = DONOR_NAME;
    ch_ss.sample_rate = 100;

    ld_prepend_channel(SOURCE_SS_FILE, OUTPUT_SS_FILE, ch_ss);

    fprintf('\nCheck "%s" in i2 Pro:\n', OUTPUT_SS_FILE);
    fprintf('  - Offset present?  YES = timing is in channel metadata.\n');
    fprintf('  - Offset absent?   YES = combined file session registry is the cause.\n\n');
end

%% ======================================================================
%  TEST A: PREPEND on combined file (meta_ptr hypothesis — already eliminated)
%  ======================================================================
fprintf('\n\n=== TEST A: PREPEND (ld_prepend_channel) ===\n');
fprintf('Writes into pre-channel space at 0x10000 — new linked-list head.\n');
fprintf('If i2 Pro aligns by meta_ptr position, this should show no offset.\n\n');

ch_pre.name        = 'Laser RH Rear Prepend';
ch_pre.donor_name  = DONOR_NAME;
ch_pre.sample_rate = 100;

ld_prepend_channel(SOURCE_FILE, OUTPUT_FILE2, ch_pre);

fprintf('\nCheck "%s" in i2 Pro:\n', OUTPUT_FILE2);
fprintf('  - Does channel appear at correct session time? (expected: YES if hypothesis holds)\n');
fprintf('  - Does channel appear offset by ~1450s?        (expected: NO)\n\n');

%% ======================================================================
%  TEST B: APPEND raw clone (ld_add_channel, no ch.value)
%  ======================================================================
fprintf('\n\n=== TEST B: APPEND raw clone (ld_add_channel) ===\n');
fprintf('Appended at EOF — meta_ptr at ~file end.  Control: expect ~1450s offset.\n\n');

NEW_NAME    = 'Laser Ride Height Rear Clone';

ch.name               = NEW_NAME;
ch.donor_name         = DONOR_NAME;
ch.sample_rate        = 100;
ch.use_donor_data_ptr = true;   % TIMING TEST: point data_ptr at donor's original data
% ch.value intentionally absent — triggers raw byte copy in ld_add_channel

%% -- Write --------------------------------------------------------------
fprintf('=== Writing output ===\n');
ld_add_channel(SOURCE_FILE, OUTPUT_FILE, ch);

%% -- Read back and verify (values should be identical to donor) ---------
fprintf('\n=== Readback verification ===\n');
san = @(s) lower(regexprep(s, '[^a-zA-Z0-9]', '_'));
rb  = motec_ld_reader(OUTPUT_FILE, {NEW_NAME, DONOR_NAME});
fns = fieldnames(rb);

fn_clone = fns(strcmpi(fns, san(NEW_NAME)));
fn_orig  = fns(strcmpi(fns, san(DONOR_NAME)));

if isempty(fn_clone)
    fprintf('[FAIL] "%s" not found in output.\n', NEW_NAME);
    return;
end

rb_clone = rb.(fn_clone{1}).data;
rb_orig  = rb.(fn_orig{1}).data;

fprintf('  Original first 5 : %s\n', mat2str(rb_orig(1:min(5,end)), 6));
fprintf('  Clone    first 5 : %s\n', mat2str(rb_clone(1:min(5,end)), 6));

n_cmp    = min(numel(rb_orig), numel(rb_clone));
max_diff = max(abs(rb_clone(1:n_cmp) - rb_orig(1:n_cmp)));
fprintf('\n  Max diff (should be 0): %.6f\n', max_diff);
if max_diff == 0
    fprintf('  [PASS] Clone is bit-perfect.\n');
else
    fprintf('  [WARN] Non-zero diff — decode round-trip introduced error.\n');
end

%% ======================================================================
%  TEST C: APPEND +3mm offset (ld_add_channel, ch.value = orig + 3)
%  ======================================================================
fprintf('\n\n=== TEST C: APPEND +3mm offset (ld_add_channel) ===\n\n');

NEW_NAME    = 'Laser Ride Height Rear Offset';
OFFSET_MM   = 3;

%% -- Read source file, extract donor channel data -----------------------
fprintf('=== Reading source file ===\n');
src = motec_ld_reader(SOURCE_FILE, {DONOR_NAME});

san = @(s) lower(regexprep(s, '[^a-zA-Z0-9]', '_'));
fn  = san(DONOR_NAME);

if ~isfield(src, fn)
    % try with trailing underscores stripped
    fns = fieldnames(src);
    hit = fns(strncmpi(fns, fn, numel(fn)));
    if isempty(hit)
        error('Channel "%s" not found in source. Available: %s', ...
            DONOR_NAME, strjoin(fieldnames(src), ', '));
    end
    fn = hit{1};
end

orig_data = src.(fn).data;
orig_sr   = src.(fn).sample_rate;

fprintf('  Found: %s  n=%d  sr=%d Hz\n', fn, numel(orig_data), orig_sr);
fprintf('  First 5 values: %s\n\n', mat2str(orig_data(1:min(5,end)), 5));

%% -- Build channel struct -----------------------------------------------
ch.name        = NEW_NAME;
% short_name intentionally NOT set — inherit donor's catalog key ("GPD 9vs")
% i2 Pro uses this field as an internal channel catalog ID, not a display label.
ch.donor_name  = DONOR_NAME;         % named donor — inherits all metadata
ch.value       = orig_data + OFFSET_MM;
ch.sample_rate = orig_sr;
% No dec_places / mul / scale / offset overrides — all from donor

%% -- Write --------------------------------------------------------------
fprintf('=== Writing output ===\n');
ld_add_channel(SOURCE_FILE, OUTPUT_FILE, ch);

%% -- Read back and verify -----------------------------------------------
fprintf('\n=== Readback verification ===\n');
rb  = motec_ld_reader(OUTPUT_FILE, {NEW_NAME, DONOR_NAME});
fns = fieldnames(rb);

fn_new  = fns(strcmpi(fns, san(NEW_NAME)));
fn_orig = fns(strcmpi(fns, fn));

if isempty(fn_new)
    fprintf('[FAIL] "%s" not found in output.\n', NEW_NAME);
    return;
end

rb_new  = rb.(fn_new{1}).data;
rb_orig = rb.(fn_orig{1}).data;

fprintf('  Original first 5 : %s\n', mat2str(rb_orig(1:min(5,end)), 5));
fprintf('  Offset   first 5 : %s\n', mat2str(rb_new(1:min(5,end)),  5));
fprintf('  Expected first 5 : %s\n', mat2str(rb_orig(1:min(5,end)) + OFFSET_MM, 5));

diff_err = max(abs(rb_new - (rb_orig + OFFSET_MM)));
fprintf('\n  Max error vs (orig + %d): %.6f\n', OFFSET_MM, diff_err);

if diff_err < 0.1
    fprintf('  [PASS] Offset channel encodes correctly.\n');
else
    fprintf('  [FAIL] Unexpected error — check donor scaling.\n');
end

fprintf('\nOpen in i2 Pro:\n  %s\n', OUTPUT_FILE);
