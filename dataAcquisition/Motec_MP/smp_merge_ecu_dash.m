
%% smp_merge_ecu_dash.m
% Align an ECU logger .ld file to a Dash logger .ld file using Engine RPM
% cross-correlation, then merge ECU channels into a combined struct.
%
% Both loggers record simultaneously but with an unknown time offset (phase
% shift). The Engine RPM signal is shared between both loggers and is
% sufficiently unique to resolve the offset via xcorr.
%
% Workflow:
%   1. Read ALL channels from both .ld files via motec_ld_reader
%   2. Resample both RPM signals to a common time grid
%   3. xcorr to find the time offset (ECU time + offset_s = Dash time)
%   4. Resample each ECU channel onto the Dash time axis
%   5. Merge into a single 'merged' struct (ECU fields prefixed 'ecu_')
%   6. Show alignment quality popup + diagnostic figure

clear; clc; close all;

%% =========================================================
%  CONFIG  — edit these paths and settings
%% =========================================================

DASH_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890015.ld';
ECU_FILE  = 'E:\2026\T01_QLR\ECU\S1_#26485_20260505_164454.ld';

% Engine RPM channel name — raw MoTeC channel name as it appears in each logger file.
% Set independently for each logger if they use different channel names.
DASH_RPM_CHANNEL = 'Engine_Speed';
ECU_RPM_CHANNEL  = 'Engine.Speed';

% Resample rate for xcorr (Hz). Higher = finer offset resolution but slower.
% 100 Hz gives 0.01s resolution, which is sufficient for logger phase alignment.
RESAMPLE_HZ = 100;

% Maximum plausible time offset between loggers (seconds).
% If xcorr finds an offset larger than this the script warns and caps it.
MAX_OFFSET_S = 600;

% Minimum RPM to include in xcorr (removes idle noise where signal is flat)
RPM_MIN = 500;

%% =========================================================
%  RUN
%% =========================================================

cfg.dash_rpm_channel  = DASH_RPM_CHANNEL;
cfg.ecu_rpm_channel   = ECU_RPM_CHANNEL;
cfg.resample_hz       = RESAMPLE_HZ;
cfg.max_offset_s      = MAX_OFFSET_S;
cfg.rpm_min           = RPM_MIN;
cfg.show_ui           = true;

result = smp_merge_ecu_dash_pair(DASH_FILE, ECU_FILE, cfg); 

% --- logic now lives in smp_merge_ecu_dash_pair.m ---
