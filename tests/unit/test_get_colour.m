classdef test_get_colour < matlab.unittest.TestCase
% TEST_GET_COLOUR  Unit tests for get_colour().
%
% Run with:
%   results = runtests('tests/unit/test_get_colour');
%   table(results)

    properties
        cfg
    end

    methods (TestMethodSetup)
        function loadCfg(tc)
            tc.cfg = smp_colours();
        end
    end

    methods (Test)

        % -----------------------------------------------------------------
        %  Known manufacturer lookups
        % -----------------------------------------------------------------
        function testFordReturnsCorrectColour(tc)
            col = get_colour(tc.cfg, 'Ford', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.manufacturer.Ford);
        end

        function testChevReturnsCorrectColour(tc)
            col = get_colour(tc.cfg, 'Chev', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.manufacturer.Chev);
        end

        function testToyotaReturnsCorrectColour(tc)
            col = get_colour(tc.cfg, 'Toyota', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.manufacturer.Toyota);
        end

        % -----------------------------------------------------------------
        %  Alias lookups work through get_colour
        % -----------------------------------------------------------------
        function testChevroletAliasViaGetColour(tc)
            col = get_colour(tc.cfg, 'Chevrolet', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.manufacturer.Chev);
        end

        function testCamryAliasViaGetColour(tc)
            col = get_colour(tc.cfg, 'Camry', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.manufacturer.Toyota);
        end

        % -----------------------------------------------------------------
        %  Unknown key returns fallback
        % -----------------------------------------------------------------
        function testUnknownManufacturerReturnsFallback(tc)
            col = get_colour(tc.cfg, 'Nissan', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.fallback);
        end

        function testEmptyStringReturnsFallback(tc)
            col = get_colour(tc.cfg, '', 'manufacturer');
            tc.verifyEqual(col, tc.cfg.fallback);
        end

        % -----------------------------------------------------------------
        %  Default mode is 'manufacturer'
        % -----------------------------------------------------------------
        function testDefaultModeIsManufacturer(tc)
            col_explicit = get_colour(tc.cfg, 'Ford', 'manufacturer');
            col_default  = get_colour(tc.cfg, 'Ford');
            tc.verifyEqual(col_default, col_explicit);
        end

        % -----------------------------------------------------------------
        %  Output is always [1x3] double
        % -----------------------------------------------------------------
        function testOutputSizeForKnownKey(tc)
            col = get_colour(tc.cfg, 'Toyota', 'manufacturer');
            tc.verifySize(col, [1 3]);
            tc.verifyClass(col, 'double');
        end

        function testOutputSizeForUnknownKey(tc)
            col = get_colour(tc.cfg, 'Unknown_Brand_XYZ', 'manufacturer');
            tc.verifySize(col, [1 3]);
            tc.verifyClass(col, 'double');
        end

    end
end
