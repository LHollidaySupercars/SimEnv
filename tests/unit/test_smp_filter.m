classdef test_smp_filter < matlab.unittest.TestCase
% TEST_SMP_FILTER  Unit tests for smp_filter() using synthetic SMP struct.
%
% No .ld files required — builds a minimal mock SMP struct in memory.
%
% Run with:
%   results = runtests('tests/unit/test_smp_filter');
%   table(results)

    properties
        SMP     % mock SMP struct with 3 teams
        alias   % empty alias (no Excel file needed)
    end

    methods (TestMethodSetup)
        function buildMockSMP(tc)
            % Build a minimal SMP struct that smp_filter can operate on.
            % Three teams: FRD (Ford), GM (Chev), TOY (Toyota)
            % Two sessions per team: Qualifying, Race

            tc.SMP = struct();
            tc.alias = smp_alias_load([]);   % empty alias table

            teams = {'FRD', 'GM', 'TOY'};
            mans  = {'Ford', 'Chev', 'Toyota'};
            cars  = {'888', '18', '1'};
            drivers = {'Will Brown', 'Anton De Pasquale', 'Chaz Mostert'};
            sessions = {'Qualifying 6', 'Qualifying 6', 'Qualifying 6'; ...
                        'Race 1',       'Race 1',       'Race 1'};

            for t = 1:numel(teams)
                tk = teams{t};
                n  = 2;   % 2 runs per team

                meta = table();
                meta.Venue        = repmat({'Albert Park Grand Prix Circuit'}, n, 1);
                meta.Year         = repmat({'2026'}, n, 1);
                meta.Session      = sessions(:, t);
                meta.Driver       = repmat(drivers(t), n, 1);
                meta.CarNumber    = repmat(cars(t), n, 1);
                meta.Manufacturer = repmat(mans(t), n, 1);
                meta.LoadOK       = true(n, 1);

                tc.SMP.(tk).meta     = meta;
                tc.SMP.(tk).channels = cell(n, 1);   % empty — not needed for filter
                tc.SMP.(tk).info     = cell(n, 1);
            end
        end
    end

    methods (Test)

        % -----------------------------------------------------------------
        %  No filter — all teams returned
        % -----------------------------------------------------------------
        function testNoFilterReturnsAllTeams(tc)
            out = smp_filter(tc.SMP, tc.alias);
            teams = fieldnames(out);
            tc.verifyEqual(numel(teams), 3, 'All 3 teams should be returned');
        end

        % -----------------------------------------------------------------
        %  Team filter
        % -----------------------------------------------------------------
        function testTeamFilterReturnsSingleTeam(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Team', 'FRD');
            tc.verifyTrue(isfield(out, 'FRD'), 'FRD should be present');
            tc.verifyFalse(isfield(out, 'GM'),  'GM should be absent');
            tc.verifyFalse(isfield(out, 'TOY'), 'TOY should be absent');
        end

        function testTeamFilterMultipleTeams(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Team', {'FRD', 'GM'});
            tc.verifyTrue(isfield(out, 'FRD'));
            tc.verifyTrue(isfield(out, 'GM'));
            tc.verifyFalse(isfield(out, 'TOY'));
        end

        % -----------------------------------------------------------------
        %  Manufacturer filter
        % -----------------------------------------------------------------
        function testManufacturerFilterFord(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Manufacturer', 'Ford');
            tc.verifyTrue(isfield(out, 'FRD'));
            tc.verifyFalse(isfield(out, 'GM'));
            tc.verifyFalse(isfield(out, 'TOY'));
        end

        function testManufacturerFilterChev(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Manufacturer', 'Chev');
            tc.verifyTrue(isfield(out, 'GM'));
            tc.verifyFalse(isfield(out, 'FRD'));
        end

        function testManufacturerFilterToyota(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Manufacturer', 'Toyota');
            tc.verifyTrue(isfield(out, 'TOY'));
            tc.verifyFalse(isfield(out, 'FRD'));
        end

        % -----------------------------------------------------------------
        %  Session filter
        % -----------------------------------------------------------------
        function testSessionFilterQualifying(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Session', 'Qualifying');
            % Each team has 1 qualifying run — all 3 teams returned
            teams = fieldnames(out);
            tc.verifyEqual(numel(teams), 3);
            % Each team should have exactly 1 run
            for i = 1:numel(teams)
                tc.verifyEqual(height(out.(teams{i}).meta), 1, ...
                    sprintf('%s should have 1 qualifying run', teams{i}));
            end
        end

        function testSessionFilterRace(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Session', 'Race');
            teams = fieldnames(out);
            tc.verifyEqual(numel(teams), 3);
            for i = 1:numel(teams)
                tc.verifyEqual(height(out.(teams{i}).meta), 1);
            end
        end

        % -----------------------------------------------------------------
        %  Driver filter
        % -----------------------------------------------------------------
        function testDriverFilterWillBrown(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Driver', 'Will Brown');
            tc.verifyTrue(isfield(out, 'FRD'));
            tc.verifyFalse(isfield(out, 'GM'));
            tc.verifyFalse(isfield(out, 'TOY'));
        end

        % -----------------------------------------------------------------
        %  Combined filters (AND logic)
        % -----------------------------------------------------------------
        function testCombinedManufacturerAndSession(tc)
            out = smp_filter(tc.SMP, tc.alias, ...
                'Manufacturer', 'Ford', 'Session', 'Qualifying');
            tc.verifyTrue(isfield(out, 'FRD'));
            tc.verifyEqual(height(out.FRD.meta), 1);
        end

        function testCombinedManufacturerAndSessionNoMatch(tc)
            % There is no Chevrolet race — this should still find it
            out = smp_filter(tc.SMP, tc.alias, ...
                'Manufacturer', 'Chev', 'Session', 'Race');
            tc.verifyTrue(isfield(out, 'GM'));
        end

        % -----------------------------------------------------------------
        %  No match returns empty struct
        % -----------------------------------------------------------------
        function testNoMatchReturnsEmptyStruct(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Manufacturer', 'Nissan');
            tc.verifyEmpty(fieldnames(out), 'No teams should match Nissan');
        end

        % -----------------------------------------------------------------
        %  Output struct preserves correct meta columns
        % -----------------------------------------------------------------
        function testOutputMetaHasExpectedColumns(tc)
            out = smp_filter(tc.SMP, tc.alias, 'Team', 'FRD');
            expected_cols = {'Venue','Year','Session','Driver','CarNumber','Manufacturer','LoadOK'};
            actual_cols   = out.FRD.meta.Properties.VariableNames;
            for i = 1:numel(expected_cols)
                tc.verifyTrue(ismember(expected_cols{i}, actual_cols), ...
                    sprintf('Column %s missing from output meta', expected_cols{i}));
            end
        end

    end
end
