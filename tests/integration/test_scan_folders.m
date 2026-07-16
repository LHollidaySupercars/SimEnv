classdef test_scan_folders < matlab.unittest.TestCase
% TEST_SCAN_FOLDERS  Integration test for smp_scan_folders().
%
% Requires testData folder to be populated with .ld files:
%   C:\SimEnv\tests\testData\
%       01_FRD\  ← Will Brown / Ford
%       02_GM\   ← Anton De Pasquale / Chev
%       03_TOY\  ← Chaz Mostert / Toyota
%
% Run with:
%   results = runtests('tests/integration/test_scan_folders');
%   table(results)

    properties (Constant)
        TEST_DATA_DIR = 'C:\SimEnv\tests\testData'
    end

    properties
        result   % output of smp_scan_folders
    end

    methods (TestMethodSetup)
        function runScan(tc)
            tc.assumeTrue(isfolder(tc.TEST_DATA_DIR), ...
                'testData folder not found — skipping integration tests');
            tc.result = smp_scan_folders(tc.TEST_DATA_DIR);
        end
    end

    methods (Test)

        function testFindsThreeTeams(tc)
            tc.verifyEqual(numel(tc.result), 3, ...
                'Should find exactly 3 team folders');
        end

        function testAcronymsFound(tc)
            acronyms = {tc.result.acronym};
            tc.verifyTrue(ismember('FRD', acronyms), 'FRD team not found');
            tc.verifyTrue(ismember('GM',  acronyms), 'GM team not found');
            tc.verifyTrue(ismember('TOY', acronyms), 'TOY team not found');
        end

        function testEachTeamHasLdFiles(tc)
            for i = 1:numel(tc.result)
                tc.verifyNotEmpty(tc.result(i).files, ...
                    sprintf('%s has no .ld files', tc.result(i).acronym));
            end
        end

        function testFordHasCorrectIndex(tc)
            idx = find(strcmp({tc.result.acronym}, 'FRD'));
            tc.verifyEqual(tc.result(idx).index, 1, ...
                'FRD should have index 1 (folder 01_FRD)');
        end

        function testGMHasCorrectIndex(tc)
            idx = find(strcmp({tc.result.acronym}, 'GM'));
            tc.verifyEqual(tc.result(idx).index, 2, ...
                'GM should have index 2 (folder 02_GM)');
        end

        function testToyotaHasCorrectIndex(tc)
            idx = find(strcmp({tc.result.acronym}, 'TOY'));
            tc.verifyEqual(tc.result(idx).index, 3, ...
                'TOY should have index 3 (folder 03_TOY)');
        end

        function testFolderPathsExist(tc)
            for i = 1:numel(tc.result)
                tc.verifyTrue(isfolder(tc.result(i).folder), ...
                    sprintf('Folder path does not exist: %s', tc.result(i).folder));
            end
        end

    end
end
