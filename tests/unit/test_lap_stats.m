classdef test_lap_stats < matlab.unittest.TestCase
% TEST_LAP_STATS  Unit tests for lap_stats() using synthetic lap data.
%
% No .ld files required — builds a minimal laps struct in memory.
%
% Run with:
%   results = runtests('tests/unit/test_lap_stats');
%   table(results)

    properties
        laps_uniform    % 3 laps, constant speed = 100
        laps_varying    % 3 laps, known varying values
        tol             % numeric tolerance
    end

    methods (TestMethodSetup)
        function buildLaps(tc)
            tc.tol = 1e-9;

            % ---- Uniform laps: speed = 100 km/h for all samples ----------
            for k = 1:3
                tc.laps_uniform(k).lap_number = k;
                tc.laps_uniform(k).lap_time   = 100.0;
                tc.laps_uniform(k).t_start    = (k-1) * 100;
                tc.laps_uniform(k).t_end      = k * 100;
                n = 500;
                ch.data        = ones(n, 1) * 100;
                ch.time        = linspace(0, 100, n)';
                ch.units       = 'km/h';
                ch.sample_rate = 5;
                ch.raw_name    = 'Ground Speed';
                tc.laps_uniform(k).channels.Ground_Speed = ch;
            end

            % ---- Varying laps: known values per lap ----------------------
            % Lap 1: [10, 20, 30, 40, 50]  → min=10, max=50, mean=30
            % Lap 2: [5,  15, 25, 35, 45]  → min=5,  max=45, mean=25
            % Lap 3: [0,  25, 50, 75, 100] → min=0,  max=100, mean=50
            vals = {[10;20;30;40;50], [5;15;25;35;45], [0;25;50;75;100]};
            lap_times = [106.026, 106.812, 106.387];

            for k = 1:3
                tc.laps_varying(k).lap_number = k;
                tc.laps_varying(k).lap_time   = lap_times(k);
                tc.laps_varying(k).t_start    = (k-1) * 107;
                tc.laps_varying(k).t_end      = k * 107;

                ch.data        = vals{k};
                ch.time        = linspace(0, 106, numel(vals{k}))';
                ch.units       = 'km/h';
                ch.sample_rate = 5;
                ch.raw_name    = 'Ground Speed';
                tc.laps_varying(k).channels.Ground_Speed = ch;
            end
        end
    end

    methods (Test)

        % -----------------------------------------------------------------
        %  Output struct shape
        % -----------------------------------------------------------------
        function testOutputHasRequestedChannel(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyTrue(isfield(stats, 'Ground_Speed'), ...
                'stats must have Ground_Speed field');
        end

        function testOutputHasLapNumbers(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyTrue(isfield(stats.Ground_Speed, 'lap_numbers'));
        end

        function testOutputHasLapTimes(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyTrue(isfield(stats.Ground_Speed, 'lap_times'));
        end

        function testLapCountMatchesInput(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(numel(stats.Ground_Speed.lap_numbers), 3);
        end

        % -----------------------------------------------------------------
        %  Lap numbers and times preserved correctly
        % -----------------------------------------------------------------
        function testLapNumbersCorrect(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.lap_numbers, [1 2 3]);
        end

        function testLapTimesCorrect(tc)
            stats = lap_stats(tc.laps_varying, 'Ground_Speed');
            expected = [106.026, 106.812, 106.387];
            tc.verifyEqual(stats.Ground_Speed.lap_times, expected, ...
                'AbsTol', tc.tol);
        end

        % -----------------------------------------------------------------
        %  Statistics on uniform data (all laps = constant 100)
        % -----------------------------------------------------------------
        function testMeanUniform(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.mean, [100 100 100], 'AbsTol', tc.tol);
        end

        function testMinUniform(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.min, [100 100 100], 'AbsTol', tc.tol);
        end

        function testMaxUniform(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.max, [100 100 100], 'AbsTol', tc.tol);
        end

        function testRangeUniform(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.range, [0 0 0], 'AbsTol', tc.tol);
        end

        function testStdUniform(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.std, [0 0 0], 'AbsTol', tc.tol);
        end

        % -----------------------------------------------------------------
        %  Statistics on varying data
        % -----------------------------------------------------------------
        function testMinVarying(tc)
            stats = lap_stats(tc.laps_varying, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.min, [10 5 0], 'AbsTol', tc.tol);
        end

        function testMaxVarying(tc)
            stats = lap_stats(tc.laps_varying, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.max, [50 45 100], 'AbsTol', tc.tol);
        end

        function testMeanVarying(tc)
            stats = lap_stats(tc.laps_varying, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.mean, [30 25 50], 'AbsTol', tc.tol);
        end

        function testRangeVarying(tc)
            stats = lap_stats(tc.laps_varying, 'Ground_Speed');
            expected = [40 40 100];
            tc.verifyEqual(stats.Ground_Speed.range, expected, 'AbsTol', tc.tol);
        end

        % -----------------------------------------------------------------
        %  Units and raw_name preserved
        % -----------------------------------------------------------------
        function testUnitsPreserved(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.units, 'km/h');
        end

        function testRawNamePreserved(tc)
            stats = lap_stats(tc.laps_uniform, 'Ground_Speed');
            tc.verifyEqual(stats.Ground_Speed.raw_name, 'Ground Speed');
        end

        % -----------------------------------------------------------------
        %  Missing channel gracefully skipped (warning, not error)
        % -----------------------------------------------------------------
        function testMissingChannelSkipped(tc)
            % Should not throw — just warns and omits the field
            try
                result = lap_stats(tc.laps_uniform, 'NonExistent_Channel');
                tc.verifyFalse(isfield(result, 'NonExistent_Channel'), ...
                    'Missing channel should not appear in output');
            catch e
                tc.verifyFail(sprintf('lap_stats threw an error for missing channel: %s', e.message));
            end
        end

    end
end
