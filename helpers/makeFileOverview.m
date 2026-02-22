function overview = makeFileOverview(filtFiles, MetaData, detections, ProcessingStatus)
%MAKEFILEOVERVIEW Summarize processed files, metadata match, and deployment lengths
%
% Inputs:
%   filtFiles  - cell array of file names actually processed
%   metaData   - metadata table (must include MATCH, DEPLOY_DATE_TIME, RECOVER_DATE_TIME, etc.)
%   detections - table of detections (must include time, filename)
%   status - log of successful processing or errors
% Output:
%   overview   - summary table to display

n = numel(filtFiles);
overview = table('Size',[n 5], ...
    'VariableTypes', {'string','string','string','string','string'}, ...
    'VariableNames', {'Filename','MetadataMatch','MetadataDeployment','DetectionSpan','Status'});

% Processing Status
ProcessingStatus = string(ProcessingStatus);
overview.Status = ProcessingStatus;

for i = 1:n
    [~, thisFile,~] = fileparts(filtFiles{i});

    thisFile = string(thisFile);
    overview.Filename(i) = thisFile;

    % Metadata match

    % Metadata match: check if this file appears in MatchingFiles
        mIdx = cellfun(@(x) any(contains(x,thisFile)), MetaData.MatchingFiles);
        if any(mIdx)
            overview.MetadataMatch(i) = "Yes";
        else
            overview.MetadataMatch(i) = "No";
        end

    % Metadata deployment length (Activation → Valid Until)
    if any(mIdx)
        t1 = MetaData.DEPLOY_DATE_TIME(mIdx);
        t2 = MetaData.VALID_DATA_UNTIL_DATE_TIME(mIdx);
        dur = t2 - t1;
        overview.MetadataDeployment(i) = formatDuration(dur);
    else
        overview.MetadataDeployment(i) = "N/A";
    end
end

% Add detection span
if ~isempty(detections) && ismember('PODfile', detections.Properties.VariableNames)
    detections.DETECTION_DATE_TIME = datetime(detections.DETECTION_DATE_TIME);
    detSummary = groupsummary(detections, 'PODfile', {'min','max'}, 'DETECTION_DATE_TIME');
    detSummary.Duration = detSummary.max_DETECTION_DATE_TIME - detSummary.min_DETECTION_DATE_TIME;

    for i = 1:n
        % strip extension (.FP3 or .CP3) to match filenames
        baseName = erase(overview.Filename(i), {'.FP3','.CP3'});
        fIdx = strcmp(detSummary.PODfile, baseName);
        if any(fIdx)
            dur = detSummary.Duration(fIdx);
            overview.DetectionSpan(i) = formatDuration(dur);
        else
            overview.DetectionSpan(i) = "N/A";
        end
    end
end

end
