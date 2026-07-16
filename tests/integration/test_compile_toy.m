classdef test_compile_toy < matlab.unittest.TestCase
% TEST_COMPILE_TOY  Integration test for Toyota (Chaz Mostert, car 1) test data.
%
% Expected values:
%   Car:          1
%   Driver:       Chaz Mostert
%   Manufacturer: Toyota
%   Venue:        Albert Park Grand Prix Circuit
%   Session:      Qualifying 6
%   Flying laps:  1
%   Best lap:     ~106.387s  (1:46.387)
%   Channels:     Ground_Speed, C1_Damper_Pos_FL present
%
% Run with:
%   results = runtests('tests/integration/test_compile_toy');
%   table(results)

    properties (Constant)
        TEAM_FOLDER  = 'C:\SimEnv\tests\testData\03_TOY'
        BEST_LAP_S   = 106.387
        LAP_TOL_S    = 0.5
        N_FLYING     = 1
    end

    properties
        laps
        info
        session
    end

    methods (TestMethodSetup)
        function loadData(tc)
            tc.assumeTrue(isfolder(tc.TEAM_FOLDER), ...
                '03_TOY test folder not found — skipping');
            [tc.laps, tc.session, tc.info] = ...
                smp_test_load_and_slice(tc.TEAM_FOLDER);
        end
    end

    methods (Test)

        function testDriverName(tc)
            tc.verifyTrue(contains(lower(tc.info.driver), 'mostert') || ...
                          contains(lower(tc.info.driver), 'chaz'), ...
                sprintf('Expected Mostert, got: %s', tc.info.driver));
        end

        function testCarNumber(tc)
            tc.verifyTrue(contains(char(tc.info.vehicle_id), '1'), ...
                sprintf('Expected car 1, got: %s', char(tc.info.vehicle_id)));
        end

        function testVenue(tc)
            tc.verifyTrue(contains(lower(tc.info.venue), 'albert park'), ...
                sprintf('Expected Albert Park, got: %s', tc.info.venue));
        end

        function testSession(tc)
            tc.verifyTrue(contains(lower(tc.info.event), 'qualifying'), ...
                sprintf('Expected Qualifying session, got: %s', tc.info.event));
        end

        function testFlyingLapCount(tc)
            lap_nums = [tc.laps.lap_number];
            n_flying = sum(lap_nums >= 1);
            tc.verifyEqual(n_flying, tc.N_FLYING, ...
                sprintf('Expected %d flying lap(s), got %d', tc.N_FLYING, n_flying));
        end

        function testBestLapTime(tc)
            lap_nums  = [tc.laps.lap_number];
            lap_times = [tc.laps.lap_time];
            flying    = lap_times(lap_nums >= 1);
            best      = min(flying);
            tc.verifyEqual(best, tc.BEST_LAP_S, 'AbsTol', tc.LAP_TOL_S, ...
                sprintf('Best lap expected ~%.3fs, got %.3fs', tc.BEST_LAP_S, best));
        end

        function testGroundSpeedChannelPresent(tc)
            fields = fieldnames(tc.laps(1).channels);
            tc.verifyTrue(any(strcmpi(fields, 'Ground_Speed')), ...
                'Ground_Speed channel not found');
        end

        function testDamperChannelPresent(tc)
            fields = fieldnames(tc.laps(1).channels);
            has_damper = any(contains(lower(fields), 'c1_damper'));
            tc.verifyTrue(has_damper, 'C1_Damper_Pos_FL channel not found');
        end

        function testGroundSpeedMaxReasonable(tc)
            lap_nums = [tc.laps.lap_number];
            flying_idx = find(lap_nums >= 1, 1);
            ch = tc.laps(flying_idx).channels.Ground_Speed;
            tc.verifyGreaterThan(max(ch.data), 150);
        end

    end
end
