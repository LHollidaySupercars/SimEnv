classdef test_smp_colours < matlab.unittest.TestCase
% TEST_SMP_COLOURS  Unit tests for smp_colours() and get_colour().
%
% Run with:
%   results = runtests('tests/unit/test_smp_colours');
%   table(results)

    properties
        cfg   % loaded once for all tests
    end

    methods (TestMethodSetup)
        function loadCfg(tc)
            tc.cfg = smp_colours();
        end
    end

    % =====================================================================
    %  smp_colours struct shape
    % =====================================================================
    methods (Test)

        function testStructHasManufacturerField(tc)
            tc.verifyTrue(isfield(tc.cfg, 'manufacturer'), ...
                'cfg must have a manufacturer field');
        end

        function testStructHasDriverField(tc)
            tc.verifyTrue(isfield(tc.cfg, 'driver'), ...
                'cfg must have a driver field');
        end

        function testStructHasFallbackField(tc)
            tc.verifyTrue(isfield(tc.cfg, 'fallback'), ...
                'cfg must have a fallback field');
        end

        % -----------------------------------------------------------------
        %  Primary manufacturer colours
        % -----------------------------------------------------------------
        function testFordIsBlue(tc)
            col = tc.cfg.manufacturer.Ford;
            tc.verifySize(col, [1 3], 'Ford colour must be [1x3]');
            tc.verifyGreaterThan(col(3), col(1), 'Ford should be blue-dominant');
        end

        function testChevIsYellow(tc)
            col = tc.cfg.manufacturer.Chev;
            tc.verifySize(col, [1 3], 'Chev colour must be [1x3]');
            % Yellow = high R, high G, low B
            tc.verifyGreaterThan(col(1), 0.8, 'Chev R should be high');
            tc.verifyGreaterThan(col(2), 0.7, 'Chev G should be high');
            tc.verifyLessThan(col(3), 0.3,    'Chev B should be low');
        end

        function testToyotaIsRed(tc)
            col = tc.cfg.manufacturer.Toyota;
            tc.verifySize(col, [1 3], 'Toyota colour must be [1x3]');
            tc.verifyGreaterThan(col(1), col(3), 'Toyota should be red-dominant');
        end

        % -----------------------------------------------------------------
        %  Aliases resolve to same colour as primary
        % -----------------------------------------------------------------
        function testChevroletAliasMatchesChev(tc)
            tc.verifyEqual(tc.cfg.manufacturer.Chevrolet, tc.cfg.manufacturer.Chev);
        end

        function testHoldenAliasMatchesChev(tc)
            tc.verifyEqual(tc.cfg.manufacturer.Holden, tc.cfg.manufacturer.Chev);
        end

        function testCamaroAliasMatchesChev(tc)
            tc.verifyEqual(tc.cfg.manufacturer.Camaro, tc.cfg.manufacturer.Chev);
        end

        function testMustangAliasMatchesFord(tc)
            tc.verifyEqual(tc.cfg.manufacturer.Mustang, tc.cfg.manufacturer.Ford);
        end

        function testCamryAliasMatchesToyota(tc)
            tc.verifyEqual(tc.cfg.manufacturer.Camry, tc.cfg.manufacturer.Toyota);
        end

        function testGRSupraAliasMatchesToyota(tc)
            tc.verifyEqual(tc.cfg.manufacturer.GR_Supra, tc.cfg.manufacturer.Toyota);
        end

        % -----------------------------------------------------------------
        %  All colours are valid RGB (values in [0,1], length 3)
        % -----------------------------------------------------------------
        function testAllManufacturerColoursInRange(tc)
            fields = fieldnames(tc.cfg.manufacturer);
            for i = 1:numel(fields)
                col = tc.cfg.manufacturer.(fields{i});
                tc.verifySize(col, [1 3], ...
                    sprintf('%s colour must be [1x3]', fields{i}));
                tc.verifyGreaterThanOrEqual(min(col), 0, ...
                    sprintf('%s has value below 0', fields{i}));
                tc.verifyLessThanOrEqual(max(col), 1, ...
                    sprintf('%s has value above 1', fields{i}));
            end
        end

        function testFallbackInRange(tc)
            col = tc.cfg.fallback;
            tc.verifySize(col, [1 3]);
            tc.verifyGreaterThanOrEqual(min(col), 0);
            tc.verifyLessThanOrEqual(max(col), 1);
        end

    end
end
