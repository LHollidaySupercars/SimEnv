classdef test_concat_sessions < matlab.unittest.TestCase
% TEST_CONCAT_SESSIONS  Unit tests for concat_sessions().
%
% Tests multi-file Lap_Number renumbering so that joining two .ld files
% produces a monotonically increasing Lap_Number sequence with no
% duplicates.
%
% No .ld files required — builds minimal session structs in memory.
%
% Run with:
%   results = runtests('tests/unit/test_concat_sessions');
%   table(results)

    methods (Test)

        % -----------------------------------------------------------------
        function test_lap_numbers_no_collision_file2_starts_at_zero(tc)
        % File 2 starts at lap 0 — the typical MoTeC multi-file case.
        % s1=[0 1 2 3], s2=[0 1 2] → s2 renumbered to [4 5 6] → merged 0:6.
            s1 = build_session([0 1 2 3], 100, 0.01);
            s2 = build_session([0 1 2],   100, 0.01);

            merged = concat_sessions({s1, s2});
            laps   = unique(round(merged.Lap_Number.data));

            tc.verifyEqual(laps(:)', 0:6, ...
                'Merged lap numbers must be 0–6 with no duplicates');
        end

        % -----------------------------------------------------------------
        function test_lap_numbers_no_collision_file2_starts_at_one(tc)
        % File 2 starts at lap 1 — renumbering must still work correctly.
        % File 1 ends at lap 3; file 2 starts at 1.
        % Expected: merged laps = [0 1 2 3 4 5] (file2 1→4, 2→5, 3→6 ... etc)
            s1 = build_session([0 1 2 3], 100, 0.01);
            s2 = build_session([1 2 3],   100, 0.01);

            merged = concat_sessions({s1, s2});
            laps   = unique(round(merged.Lap_Number.data));

            tc.verifyEqual(laps(:)', 0:6, ...
                'Merged lap numbers must be 0–6 with no duplicates');
        end

        % -----------------------------------------------------------------
        function test_file2_min_lap_maps_to_max_plus_one(tc)
        % The lowest lap of file 2 in the merged result must equal
        % max(file1 laps) + 1.
            s1 = build_session([0 1 2], 80, 0.01);
            s2 = build_session([0 1],   80, 0.01);

            merged = concat_sessions({s1, s2});
            merged_data = round(merged.Lap_Number.data);

            n1 = numel(s1.Lap_Number.data);
            file2_min_in_merged = min(merged_data(n1+1:end));

            tc.verifyEqual(file2_min_in_merged, 3, ...
                'File 2 min lap in merged result must equal max(file1)+1 = 3');
        end

        % -----------------------------------------------------------------
        function test_three_files_monotonic(tc)
        % Three files, each starting at lap 0.
        % Expected result: strictly monotonically increasing unique laps.
            s1 = build_session([0 1 2], 60, 0.01);
            s2 = build_session([0 1 2], 60, 0.01);
            s3 = build_session([0 1],   60, 0.01);

            merged = concat_sessions({s1, s2, s3});
            laps   = unique(round(merged.Lap_Number.data));

            tc.verifyEqual(laps(:)', 0:7, ...
                'Three-file merge must produce monotonically increasing laps 0–7');
        end

        % -----------------------------------------------------------------
        function test_single_session_passthrough(tc)
        % Single session must be returned unchanged.
            s1 = build_session([0 1 2 3], 120, 0.01);

            merged = concat_sessions({s1});
            laps   = unique(round(merged.Lap_Number.data));

            tc.verifyEqual(laps(:)', 0:3, ...
                'Single-session passthrough must preserve original lap numbers');
        end

        % -----------------------------------------------------------------
        function test_time_axis_is_monotonically_increasing(tc)
        % Time axis of merged result must be strictly increasing.
            s1 = build_session([0 1 2], 90, 0.01);
            s2 = build_session([0 1 2], 90, 0.01);

            merged = concat_sessions({s1, s2});
            t      = merged.Lap_Number.time;

            tc.verifyTrue(all(diff(t) > 0), ...
                'Merged time axis must be strictly increasing');
        end

        % -----------------------------------------------------------------
        function test_no_lap_number_channel_does_not_error(tc)
        % Sessions without Lap_Number should concatenate without error.
            s1 = build_session_no_lap(90, 0.01);
            s2 = build_session_no_lap(90, 0.01);

            tc.verifyWarningFree(@() concat_sessions({s1, s2}), ...
                'concat_sessions must not error when Lap_Number is absent');
        end

    end
end

% =========================================================================
%  Helpers
% =========================================================================

function s = build_session(lap_sequence, duration_s, dt)
% Build a minimal session struct with a single Lap_Number channel.
% lap_sequence: vector of integer lap numbers, each held for equal duration.
    n_laps = numel(lap_sequence);
    n_pts  = round(duration_s / dt);
    t      = (0 : n_pts-1)' * dt;

    % Assign lap numbers uniformly across the time axis
    pts_per_lap = floor(n_pts / n_laps);
    data = zeros(n_pts, 1);
    for k = 1:n_laps
        idx_start = (k-1)*pts_per_lap + 1;
        idx_end   = min(k*pts_per_lap, n_pts);
        data(idx_start:idx_end) = lap_sequence(k);
    end
    % Fill any remainder with the last lap number
    data(n_laps*pts_per_lap+1:end) = lap_sequence(end);

    s.Lap_Number.data  = data;
    s.Lap_Number.time  = t;
    s.Lap_Number.units = 'samples';
end

function s = build_session_no_lap(duration_s, dt)
% Build a minimal session struct WITHOUT a Lap_Number channel.
    n_pts = round(duration_s / dt);
    t     = (0 : n_pts-1)' * dt;

    s.Ground_Speed.data  = ones(n_pts, 1) * 100;
    s.Ground_Speed.time  = t;
    s.Ground_Speed.units = 'km/h';
end
