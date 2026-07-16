function [toeResults_corrected] = applyToeOffsetCorrection(toeResults, uprightGeometry)
% APPLYTOEOFFSETCORRECTION Applies the initial toe offset to kinematic results
%
% Takes the toe results from solveWheelToe and corrects them to account for
% the offset between the pickup plane (where kinematics are calculated) and
% the wheel plane (where toe should be measured).
%
% INPUTS:
%   toeResults - output struct from solveWheelToe containing:
%       .phi           - rotation about KPI axis [rad]
%       .toe           - toe angle [deg] (in pickup plane)
%       .toeGain       - d(toe)/d(wheelTravel) [deg/mm]
%       .toeRodUprightPos - [N x 3] positions
%
%   uprightGeometry - struct containing:
%       .pickupPlaneOrigin - [x,y,z] reference point in pickup plane
%       .wheelCenter       - [x,y,z] wheel center position
%       .KPI_axis          - [x,y,z] unit vector of KPI axis at ride height
%
% OUTPUTS:
%   toeResults_corrected - struct with corrected toe values:
%       .phi           - unchanged
%       .toe           - toe angle [deg] (corrected to wheel plane)
%       .toeGain       - unchanged (gradient is still correct)
%       .toeRodUprightPos - unchanged
%       .initial_toe_offset - the offset that was applied [deg]
%       .toe_uncorrected    - original toe values for reference [deg]

%% Calculate the initial toe offset
initial_toe_offset = calculateInitialToeOffset(uprightGeometry);

%% Apply correction
toeResults_corrected = toeResults;
toeResults_corrected.toe_uncorrected = toeResults.toe;  % Save original
toeResults_corrected.toe = toeResults.toe + initial_toe_offset;  % Correct
toeResults_corrected.initial_toe_offset = initial_toe_offset;

%% Summary
fprintf('TOE CORRECTION APPLIED:\n');
fprintf('  Offset applied:     %+.4f deg\n', initial_toe_offset);
fprintf('  Toe at ride height: %.4f deg (uncorrected) → %.4f deg (corrected)\n', ...
    toeResults.toe(find(abs(toeResults.toe) == min(abs(toeResults.toe)), 1)), ...
    toeResults_corrected.toe(find(abs(toeResults.toe) == min(abs(toeResults.toe)), 1)));
fprintf('  Toe gain unchanged: %.4f deg/mm\n', ...
    toeResults.toeGain(find(abs(toeResults.toe) == min(abs(toeResults.toe)), 1)));
fprintf('\n');

end
