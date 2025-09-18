% Script to check if the POD files have a match in the metadata file -
% based on the filename and the filename column
function fullTable = matchFilenamesWithPOD(metadataTbl, podFiles)
    podFilenames = string(podFiles);
    if contains(podFilenames(1), filesep)
        podFilenames = extractAfter(podFilenames, filesep);
    end

    % Initialize MATCH column
    metadataTbl.MATCH = repmat("N", height(metadataTbl), 1);
    metadataTbl.MATCH(ismember(metadataTbl.POD_FILE, podFilenames)) = "Y";

    % Find unmatched POD files
    matchedFilenames = metadataTbl.POD_FILE(metadataTbl.MATCH == "Y");
    unmatchedPodFiles = podFilenames(~ismember(podFilenames, matchedFilenames));

    % Create rows for unmatched POD files
    emptyRow = metadataTbl(1, :);
    emptyRow(:,:) = {missing}; % Set all fields to missing
    emptyRow.MATCH = "N";

    podOnlyRows = repmat(emptyRow, numel(unmatchedPodFiles), 1);
    podOnlyRows.POD_FILE = unmatchedPodFiles(:);

    % Combine metadata and unmatched POD rows
    fullTable = [metadataTbl; podOnlyRows];
end
