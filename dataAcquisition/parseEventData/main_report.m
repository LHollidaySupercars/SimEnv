%% =========================================================
%  MOTORSPORT REPORT — Main Script
%  =========================================================
%  Run this script to process MoTeC .ld files, slice into laps,
%  compute statistics, interpolate to distance, and produce plots.
%
%  BEFORE RUNNING: update all values in the CONFIG section below.
% =========================================================

clear; clc; close all;

% Add function paths
addpath(fullfile(pwd, 'functions'));
addpath(fullfile(pwd, 'config'));

% =========================================================
%  SECTION 1: DATA STRUCTURE CONFIG
%  *** REPLACE THESE VALUES ***
% =========================================================

% The top-level data variable loaded into your workspace.
% This is expected to have the structure:  DATA.(track).(team).channels{1,1}
% Replace this with however you load your data.

% *** REPLACE: path to your workspace / load command ***
DATA = load("C:\LOCAL_DATA\01 - SMP\_Team Data\smp_data.mat");   % loads variable called e.g. "DATA"

% For development/testing without a real file, uncomment:
% DATA = build_test_data();      % see bottom of this file

% =========================================================
%  SECTION 2: LAP SLICER CONFIG
% =========================================================
%%

lap_opts = struct();
lap_opts.lap_channel   = 'Lap_Number';   % *** REPLACE if channel name differs ***
lap_opts.lapTimer = 'Running_Lap_Time';
lap_opts.min_lap_time  = 10;             % minimum valid lap time (seconds)
lap_opts.max_lap_time  = 600;            % maximum valid lap time (seconds)
lap_opts.exclude_laps  = [];             % *** REPLACE: e.g. [1] to skip outlap ***
lap_opts.lap_range     = [];             % *** REPLACE: e.g. [2 30] to use laps 2-30 ***
lap_opts.verbose       = true;

% =========================================================
%  SECTION 3: DISTANCE INTERP CONFIG
% =========================================================

dist_opts = struct();
dist_opts.distance_channel = 'Distance';   % *** REPLACE if channel name differs ***
dist_opts.distance_scale   = 1.0;          % *** REPLACE: e.g. 1000 if units are km ***
dist_opts.speed_channel    = 'Speed';      % fallback if no distance channel
dist_opts.speed_to_ms      = 1/3.6;        % *** REPLACE: 1.0 if speed already in m/s ***
dist_opts.resolution       = 1;            % metres per grid point
dist_opts.common_grid      = true;         % all laps share same distance axis
dist_opts.verbose          = true;

% =========================================================
%  SECTION 4: CHANNELS TO ANALYSE
%  *** REPLACE with the channel names in your data ***
% =========================================================

channels_of_interest = {
    'Corr_Speed',        ...  % vehicle speed
    'Engine_Speed',          ...  % engine RPM
    'Throttle_Pedal', ...  % throttle position (%)
    'Brake_Pressure_Front',    ...  % brake pressure or position
    'Gear',         ...  % gear number
    % 'Steering_Angle', ...
    % 'Lateral_Accel',  ...
    % 'Longitudinal_Accel', ...
};

% =========================================================
%  SECTION 5: LAP STATS CONFIG
% =========================================================

stats_opts = struct();
stats_opts.operations  = {'min','max','mean','median','std','var','range','change','initial','final'};
stats_opts.percentiles = [10 90];   % also compute 10th and 90th percentile

% =========================================================
%  SECTION 6: COLOUR CONFIG
% =========================================================

% C = colours();   % loads manufacturer + driver colour lookup

% *** REPLACE: define which groups to plot and their labels ***
% group_labels should match manufacturer names ('Ford','Chev','Toyota')
% or driver names if plotting by driver.

% Example: plotting two teams
% groups = {
%     struct('label','Ford',   'manufacturer','Ford',   'colour', C.manufacturer('Ford'));
%     struct('label','Chev',   'manufacturer','Chev',   'colour', C.manufacturer('Chev'));
%     struct('label','Toyota', 'manufacturer','Toyota', 'colour', C.manufacturer('Toyota'));
% };
groups = {
    struct('label','Ford',   'manufacturer','Ford');
    struct('label','Chev',   'manufacturer','Chev');
    struct('label','Toyota', 'manufacturer','Toyota');
};
% =========================================================
%  SECTION 7: MAIN PROCESSING LOOP
%  Below is example processing for a single session struct.
%  Adapt this loop for your (TRACK).(TEAM).channels{1,1} structure.
% =========================================================

% ------------------------------------------------------------------
% Step 1: Load your session channels struct.
%
% Expected: session is a struct where each field is a channel:
%   session.Speed.data, session.Speed.time, etc.
%
% If your data is in the form DATA.TrackName.TeamName.channels{1,1},
% you would do something like:
%
  tracks = fieldnames(DATA);
  for t = 1:numel(tracks)
      teams = fieldnames(DATA.(tracks{t}));
      for tm = 1:numel(teams)
          session = DATA.(tracks{t}).(teams{tm}).channels{1,1};
%           ... run steps 2-4 below ...
      end
  end
%
% For now this script assumes you have a 'session' struct ready:
% ------------------------------------------------------------------
% session = DATA.SMP.T8R.channels{1,1};  % *** REPLACE ***

% ------------------------------------------------------------------
%% Step 2: Slice into laps
% ------------------------------------------------------------------
session = DATA.(tracks{t}).(teams{tm}).channels{8,1}
laps = lap_slicer(session, lap_opts);

% ------------------------------------------------------------------
% Step 3: Compute per-lap statistics
% ------------------------------------------------------------------
stats = lap_stats(laps, channels_of_interest, stats_opts);

% ------------------------------------------------------------------
% Step 4: Interpolate to distance (for trace plots)
% ------------------------------------------------------------------
laps_dist = distance_interp(laps, dist_opts);

% =========================================================
%  SECTION 8: EXAMPLE PLOTS
%  Uncomment and adapt after steps 2-4 are complete.
% =========================================================

% --- Example 1: Lap time trend (lap_trend) ------------------------
%
% Requires: stats.Lap_Number or you can use stats.Speed.lap_numbers
%
  pd = struct();
  pd(1).label       = 'Ford';
  pd(1).lap_numbers = stats.Speed.lap_numbers;
  pd(1).values      = stats.Speed.max;      % e.g. max speed per lap
  pd(1).colour      = C.manufacturer('Ford');

  cfg = struct('title','Max Speed per Lap','y_label','Speed','units','km/h');
  fig = create_motorsport_plot('lap_trend', pd, cfg);

% --- Example 2: Box plot of max speed per manufacturer -----------
%
  pd = struct();
  for g = 1:numel(groups)
      pd(g).label  = groups{g}.label;
%       pd(g).values = [stats_ford.Speed.max, stats_chev.Speed.max, ...];  % adapt
%       pd(g).colour = groups{g}.colour;
  end

  cfg_plot = struct('title','Max Speed per Lap','y_label','Speed','units','km/h');
  fig = create_motorsport_plot('lap_trend', pd, cfg_plot);

% --- Example 3: Distance trace — speed trace per lap -------------
%
  pd = struct();
  pd(1).label     = 'Ford';
  pd(1).dist_vec  = laps_dist(1).channels.Speed.dist_data;  % update field
  pd(1).traces    = [];   % assemble MxL matrix from laps_dist
  % Build traces matrix:
  for k = 1:numel(laps_dist)
      pd(1).traces(:,k) = laps_dist(k).channels.Speed.dist_data;
  end
  pd(1).dist_vec = laps_dist(1).dist_vec;
  pd(1).colour   = C.manufacturer('Ford');

  cfg = struct('title','Speed Trace','y_label','Speed','units','km/h');
  fig = create_motorsport_plot('trace', pd, cfg);

fprintf('\nmain_report: configuration loaded. Uncomment processing steps to run.\n');

% =========================================================
%  END
% =========================================================
