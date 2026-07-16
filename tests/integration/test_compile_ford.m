classdef test_compile_ford < matlab.unittest.TestCase
% TEST_COMPILE_FORD  Integration test for Ford (Will Brown, car 888) test data.
%
% Expected values:
%   Car:          888
%   Driver:       Will Brown
%   Manufacturer: Ford
%   Venue:        Albert Park Grand Prix Circuit
%   Session:      Qualifying 6 or 7
%   Flying laps:  6
%   Best lap:     ~106.026s  (1:46.026)
%   Channels:     Ground_Speed, C1_Damper_Pos_FL present
%
% Run with:
%   results = runtests('tests/integration/test_compile_ford');
%   table(results)

    properties (Constant)
        TEAM_FOLDER  = 'C:\SimEnv\tests\testData\01_FRD'
        BEST_LAP_S   = 106.026    % 1:46.026
        LAP_TOL_S    = 0.5        % ± 0.5s tolerance on lap times
        N_FLYING     = 6
    end

    properties
        laps
        info
        session
    end

    methods (TestMethodSetup)
        function loadData(tc)
            tc.assumeTrue(isfolder(tc.TEAM_FOLDER), ...
                '01_FRD test folder not found — skipping');
            [tc.laps, tc.session, tc.info] = ...
                smp_test_load_and_slice(tc.TEAM_FOLDER);
        end
    end

    methods (Test)

        % -----------------------------------------------------------------
        %  File header / metadata
        % -----------------------------------------------------------------
        function testDriverName(tc)
            tc.verifyTrue(contains(lower(tc.info.driver), 'brown'), ...
                sprintf('Expected Will Brown, got: %s', tc.info.driver));
        end

        function testCarNumber(tc)
            tc.verifyTrue(contains(char(tc.info.vehicle_id), '888'), ...
                sprintf('Expected car 888, got: %s', char(tc.info.vehicle_id)));
        end

        function testVenue(tc)
            tc.verifyTrue(contains(lower(tc.info.venue), 'albert park'), ...
                sprintf('Expected Albert Park, got: %s', tc.info.venue));
        end

        function testSession(tc)
            tc.verifyTrue(contains(lower(tc.info.event), 'qualifying'), ...
                sprintf('Expected Qualifying session, got: %s', tc.info.event));
        end

        % -----------------------------------------------------------------
        %  Lap count
        % -----------------------------------------------------------------
        function testFlyingLapCount(tc)
            % Count laps with lap_number >= 1 (flying laps only)
            lap_nums = [tc.laps.lap_number];
            n_flying = sum(lap_nums >= 1);
            tc.verifyEqual(n_flying, tc.N_FLYING, ...
                sprintf('Expected %d flying laps, got %d', tc.N_FLYING, n_flying));
        end

        % -----------------------------------------------------------------
        %  Lap times
        % -----------------------------------------------------------------
        function testBestLapTime(tc)
            lap_nums  = [tc.laps.lap_number];
            lap_times = [tc.laps.lap_time];
            flying    = lap_times(lap_nums >= 1);
            best      = min(flying);
            tc.verifyEqual(best, tc.BEST_LAP_S, 'AbsTol', tc.LAP_TOL_S, ...
                sprintf('Best lap expected ~%.3fs, got %.3fs', tc.BEST_LAP_S, best));
        end

        function testAllFlyingLapsReasonable(tc)
            lap_nums  = [tc.laps.lap_number];
            lap_times = [tc.laps.lap_time];
            flying    = lap_times(lap_nums >= 1);
            tc.verifyTrue(all(flying > 100 & flying < 130), ...
                'All flying laps should be between 100s and 130s for Albert Park');
        end

        % -----------------------------------------------------------------
        %  Channel presence
        % -----------------------------------------------------------------
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

        % -----------------------------------------------------------------
        %  Ground speed sanity — should reach >150 km/h on a flying lap
        % -----------------------------------------------------------------
        function testGroundSpeedMaxReasonable(tc)
            lap_nums = [tc.laps.lap_number];
            flying_idx = find(lap_nums >= 1, 1);
            ch = tc.laps(flying_idx).channels.Ground_Speed;
            tc.verifyGreaterThan(max(ch.data), 150, ...
                'Max ground speed on flying lap should exceed 150 km/h');
        end

        function testGroundSpeedMinReasonable(tc)
            lap_nums = [tc.laps.lap_number];
            flying_idx = find(lap_nums >= 1, 1);
            ch = tc.laps(flying_idx).channels.Ground_Speed;
            tc.verifyGreaterThanOrEqual(min(ch.data), 0, ...
                'Ground speed should not be negative');
        end

    end
end
