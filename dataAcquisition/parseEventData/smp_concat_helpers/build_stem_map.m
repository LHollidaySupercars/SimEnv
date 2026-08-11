function map = build_stem_map(folder)
% BUILD_STEM_MAP  Create struct map of MATLAB-safe file stems to full paths.
% Maps: {valid_stem} -> full_filepath
    map = struct();
    if ~isfolder(folder), return; end
    listing_temp = dir(fullfile(folder, '**', '*.ld'));
    listing = listing_temp(~[listing_temp.isdir]);
    listing = listing(~startsWith({listing.name}, '._'));
    listing = listing(~contains({listing.name}, '_shifted'));
    for i = 1 : numel(listing)
        [~, stem]  = fileparts(listing(i).name);
        safe_stem  = matlab.lang.makeValidName(stem);
        map.(safe_stem) = fullfile(listing(i).folder, listing(i).name);
    end
end

