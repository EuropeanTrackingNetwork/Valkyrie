% Script to check if the POD files have a match in the metadata file -
% based on the filename and the filename column

function tbl = matchFilenamesWithPOD(tbl, podFiles)
    podFilenames = string(podFiles);
    if contains(podFilenames(1), filesep)
        podFilenames = extractAfter(podFilenames, filesep);
    end

    tbl.MATCH = repmat("N", height(tbl), 1);
    tbl.MATCH(ismember(tbl.Filename, podFilenames)) = "Y";
end
