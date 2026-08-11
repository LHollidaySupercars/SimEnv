function stem = extract_stem(filepath)
% EXTRACT_STEM  Get MATLAB-safe filename stem (without .ld extension).
    [~, name] = fileparts(filepath);
    stem = matlab.lang.makeValidName(name);
end

