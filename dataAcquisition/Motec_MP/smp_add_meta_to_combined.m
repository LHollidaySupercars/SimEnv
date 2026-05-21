%% smp_add_meta_to_combined.m
% Standalone script — append session constant channels (Temperature, Humidity,
% Pressure, Density, Wind, Mass) to an existing combined .ld file.
%
% Edit the CONFIG block below and press Run.

clear; clc;

%% =========================================================
%  CONFIG  — edit these paths
%% =========================================================

COM_FILE  = 'E:\2026\T01_QLR\COM\20260505-156890009_combined.ld';
DASH_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890009.ld';   % used to match session_metadata.xlsx row

SESSION_METADATA_FILE = fullfile(fileparts(mfilename('fullpath')), 'channels', 'session_metadata.xlsx');

META_HZ = 10;   % sample rate for all metadata channels

%% =========================================================
%  SETUP
%% =========================================================

script_dir = fileparts(mfilename('fullpath'));

ch_add_dir = fullfile(script_dir, 'channelAdd');
if exist(ch_add_dir, 'dir') && ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

parse_dir = fullfile(script_dir, '..', 'parseEventData');
if exist(parse_dir, 'dir') && ~any(strcmp(strsplit(path, pathsep), fullfile(parse_dir)))
    addpath(parse_dir);
end

%% =========================================================
%  STEP 1: Load session metadata
%% =========================================================

fprintf('=== Loading session metadata ===\n');
session_meta = smp_session_metadata_load(SESSION_METADATA_FILE, DASH_FILE);
meta_fields  = fieldnames(session_meta);

if isempty(meta_fields)
    error(['No session metadata matched.\n' ...
           'Check that session_metadata.xlsx has a DASH_FILE row matching:\n  %s'], COM_FILE);
end

for mf = 1:numel(meta_fields)
    fn  = meta_fields{mf};
    sch = session_meta.(fn);
    fprintf('  %-20s = %.4f %s\n', sch.name, sch.value, sch.units);
end

%% =========================================================
%  STEP 2: Build channel list (scalar — ld_add_channel owns the count)
%% =========================================================

fprintf('\n=== Building metadata channel list ===\n');
ch_list = {};
for k = 1:numel(meta_fields)
    fn  = meta_fields{k};
    sch = session_meta.(fn);

    new_ch.name        = sch.name;
    new_ch.short_name  = sch.name(1:min(end, 7));
    new_ch.units       = sch.units;
    new_ch.sample_rate = META_HZ;
    new_ch.value       = double(sch.value);   % scalar — ld_add_channel sizes from donor_n

    ch_list{end+1} = new_ch; %#ok<AGROW>
    fprintf('  + %-20s = %.4f %s\n', sch.name, sch.value, sch.units);
end

%% =========================================================
%  STEP 3: Append via ld_add_channel
%% =========================================================

fprintf('\n=== Appending %d metadata channels ===\n', numel(ch_list));

[out_dir, out_base, out_ext] = fileparts(COM_FILE);
tmp_file = fullfile(out_dir, [out_base '_smeta_tmp' out_ext]);

ld_add_channel(COM_FILE, tmp_file, ch_list);
movefile(tmp_file, COM_FILE, 'f');

fprintf('\nDone. Metadata channels written to:\n  %s\n', COM_FILE);
