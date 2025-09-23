function overview = makeFileOverview(filtFiles, MetaData, detections)
%MAKEFILEOVERVIEW Summarize processed files, metadata match, and deployment lengths
%
% Inputs:
%   filtFiles  - cell array of file names actually processed
%   metaData   - metadata table (must include MATCH, DEPLOY_DATE_TIME, RECOVER_DATE_TIME, etc.)
%   detections - table of detections (must include time, filename)
%
% Output:
%   overview   - summary table to display

n = numel(filtFiles);
overview = table('Size',[n 4], ...
    'VariableTypes', {'string','string','string','string'}, ...
    'VariableNames', {'Filename','MetadataMatch','MetadataDeployment','DetectionSpan'});

for i = 1:n
    [~, thisFile,~] = fileparts(filtFiles{i});

    thisFile = string(thisFile);
    overview.Filename(i) = thisFile;

    % Metadata match
    if ismember('MATCH', MetaData.Properties.VariableNames)
        mIdx = strcmp(MetaData.MATCH,"Y") & contains(MetaData.POD_FILE,thisFile);
        if any(mIdx)
            overview.MetadataMatch(i) = "Yes";
        else
            overview.MetadataMatch(i) = "No";
        end
    else
        overview.MetadataMatch(i) = "Unknown";
    end

    % Metadata deployment length
    if any(mIdx)
        t1 = MetaData.DEPLOY_DATE_TIME(mIdx);
        t2 = MetaData.VALID_DATA_UNTIL_DATE_TIME(mIdx);
        dur = t2 - t1;
        overview.MetadataDeployment(i) = formatDuration(dur);
    else
        overview.MetadataDeployment(i) = duration(NaN,0,0);
    end

end

% Add detection span
if ~isempty(detections) && ismember('filename', detections.Properties.VariableNames)
    detections.DETECTION_DATE_TIME = datetime(detections.DETECTION_DATE_TIME);
    detSummary = groupsummary(detections, 'filename', {'min','max'}, 'DETECTION_DATE_TIME');
    detSummary.Duration = detSummary.max_DETECTION_DATE_TIME - detSummary.min_DETECTION_DATE_TIME;

    for i = 1:n
        % strip extension (.FP3 or .CP3) to match filenames
        baseName = erase(overview.Filename(i), {'.FP3','.CP3'});
        fIdx = strcmp(detSummary.filename, baseName);
        if any(fIdx)
            dur = detSummary.Duration(fIdx);
            overview.DetectionSpan(i) = formatDuration(dur);
        end
    end
end

end
