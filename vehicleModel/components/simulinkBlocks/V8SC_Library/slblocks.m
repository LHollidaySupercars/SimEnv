function blkStruct = slblocks
% This function specifies that the library should appear
% in the Simulink Library Browser

Browser.Library = 'V8SC_controls';       % Must match your actual .slx file name
Browser.Name    = 'V8SC controls'; % The display name you want in the browser
Browser.IsFlat  = 0;             % 0 if you use subsystems/categories, 1 if flat

blkStruct.Browser = Browser;
end