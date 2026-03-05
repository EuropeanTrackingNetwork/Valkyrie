
function updatedMetadata = matchMetadataWithPOD(fileList, metadata)
% MATCHMETADATAWITHPOD
% Returns a unified table with:
%   - original metadata rows annotated with MatchingFiles/MatchCount/PodType/FileName/RowType
%   - appended "file-only" rows for CP3/FP3 files that do not match any metadata
%
% Inputs:
%   fileList : cell array of filenames (can include CP1/FP1; we'll filter to CP3/FP3)
%   metadata : table with at least RECEIVER, ACTIVATION_DATE_TIME, VALID_DATA_UNTIL_DATE_TIME
%
% Output:
%   updatedMetadata : table (metadata rows + unmatched file rows)
%   + it changes RECEIVER to inlcude the POD type

    % -----------------------------
    % Normalize file list & filter
    % -----------------------------

   % fileList = {fileList};

    %assert(iscell(fileList), 'fileList must be a cell array of char.');
    isP3 = endsWith(fileList, {'.CP3', '.FP3'}, 'IgnoreCase', true);
    fileList = fileList(isP3);

    % -----------------------------
    % Preallocate output columns
    % -----------------------------
    n = height(metadata);
    matches   = cell(n, 1);
    matchCnt  = zeros(n, 1);
    podTypes  = strings(n, 1);
    fileNames = strings(n, 1);      % optional: first matched filename for convenience
    rowType   = repmat("metadata", n, 1);
    deploymentId = strings(n, 1);   % identifier per metadata row


    % -----------------------------
    % Match loop (per metadata row)
    % -----------------------------
    for i = 1:n

        % --- Build start date for a metadata row i ---
        % OBS: for some files it has to be activation date
        act = metadata.ACTIVATION_DATE_TIME(i);
        dep = metadata.DEPLOY_DATE_TIME(i);
        val = metadata.VALID_DATA_UNTIL_DATE_TIME(i);

        % Start time for both activation and deployment datetime
        if ~isnat(act)
            startDtact = act;
        end
        if ~isnat(dep)
            startDtdep = dep;
        end
        
        % Normalize both file date and start date to day-level and strip timezone
        % activation datetime:
        startDayact = dateshift(startDtact, 'start', 'day');
        startDayact.TimeZone = '';
        startDayact.Format = 'yyyyMMdd';

        % Deployment datetime
        startDaydep = dateshift(startDtdep, 'start', 'day');
        startDaydep.TimeZone = '';
        startDaydep.Format = 'yyyyMMdd';

        % End day defined by the valid data until (also mandatory field)
        endDay = dateshift(val, 'start','day');
        endDay.Format = 'yyyyMMdd';
        endDay.TimeZone = '';


% --- Build the deployment identifier (INLINE, no helpers) ---
        station     = string(metadata.STATION_NAME(i));   % use exactly as in metadata
        receiverStr = string(metadata.RECEIVER(i));
        % Extract first run of digits from RECEIVER (serial number)
        tok = regexp(receiverStr, '(\d+)', 'match', 'once');
        if isempty(tok)
            receiverDigits = "UNKNOWN";
        else
            receiverDigits = string(tok);
        end

        if isdatetime(startDtdep) && ~isnat(startDtdep)
            startDtdep.TimeZone = 'UTC';
            startDtdep.Format = "yyyyMMdd'T'HHmmss'Z'";
            tsDep = string(startDtdep);
            if ~isempty(startDtdep) && isdatetime(startDtact) && ~isnat(startDtact)
                startDtact.TimeZone = 'UTC';
                startDtact.Format = "yyyyMMdd'T'HHmmss'Z'";
                tsAct = string(startDtact);
            end
        else
            tsDep = "UNKNOWNDATE";
            tsAct = "UNKNOWNDATE";
        end

        % Extract digits from RECEIVER (e.g., "FPOD_123" -> "123")
        rawReceiver   = string(metadata.RECEIVER(i));
        receiverDigits = regexp(rawReceiver, '\d+', 'match');
        if isempty(receiverDigits)
            % No receiver ID -> no matches
            matches{i}  = {};
            matchCnt(i) = 0;
            podTypes(i) = "";
            continue;
        end
        receiverID = receiverDigits{1};

        matchedFilesForRow = {};
        typeDetected = "";

        for j = 1:numel(fileList)
            fname = fileList{j};
            [~, name, ext] = fileparts(fname);

            % Extract date (support underscores/dashes/spaces)
            % Looks for YYYY MM DD in a flexible way: 2024_09_05 or 2024-09-05 or 2024 09 05
            % OBS: this will cause a mistake for names like this: 'CPOD1686 2011 11 09 POD1686 file01.CP3'
            tokens = regexp(name, '(?<!\w)(\d{4})\s+(\d{2})\s+(\d{2})(?!\w)', 'tokens');
            if isempty(tokens), continue; end
            dateStr = strjoin(tokens{1}, '');
            fileDate = datetime(dateStr, 'InputFormat', 'yyyyMMdd');  % timezone-less


            % String for deploymentId (exactly "YYYY MM DD")
            dateForId = datestr(startDaydep, 'yyyy mm dd');


            % Check POD ID match (support CPOD/FPOD naming)
            % Examples: "...POD123..." or "...FPOD_123..."
            podMatch = contains(name, "POD" + receiverID) || contains(name, "FPOD_" + receiverID);
            
            % Parse file date (already date-only)
            % Make sure we also normalize to day-level and timezone-less
            fileDay = dateshift(fileDate, 'start', 'day');
            fileDay.TimeZone = '';
            
            % The ID used for ETN (filename in Detection output) should
            % always refer the station name, deploytment date and receiver
            % ID:
      
            deploymentId(i) = station + " " + dateForId + " POD" + receiverDigits; 

            % Check if POD filename date is within the datetime provided in
            % metadata:
            if fileDay >= startDayact && fileDay < startDaydep && fileDay < endDay
                % deploymentId(i) = station + " " + dateForId + " POD" + receiverDigits; 
                inRange = true;
            elseif fileDay >= startDaydep && fileDay > startDayact && fileDay < endDay
                % deploymentId(i) = station + " " + dateForId + " POD" + receiverDigits; 
                inRange = true;
            else
                % deploymentId(i) = station + " " + dateForId + " POD" + receiverDigits;
                inRange = false;
            end



            if podMatch && inRange
                matchedFilesForRow{end+1} = fname;

                % Determine PodType from extension
                if strcmpi(ext, '.CP3')
                    typeDetected = "C-POD";
                elseif strcmpi(ext, '.FP3')
                    typeDetected = "F-POD";
                end
            end
        end

        matches{i}  = matchedFilesForRow;
        matchCnt(i) = numel(matchedFilesForRow);
        podTypes(i) = typeDetected;

 
    end
    
    % --- Add receiver ID
    
    for i = 1:n
        if podTypes(i) ~= ""   % Only modify if we actually found a POD type
            rec = string(metadata.RECEIVER(i));
            rec = strtrim(rec);
    
            % Extract numeric part again (same logic you already use)
            digits = regexp(rec, '\d+', 'match', 'once');
            if isempty(digits)
                % If no digits, skip
                continue;
            end
    
            % Write back the modified receiver
            metadata.RECEIVER(i) = digits;
        end
    end


    % -----------------------------------------
    % Build updated metadata rows (annotated)
    % -----------------------------------------
    updatedMetadata = metadata;
    % Add/overwrite output columns
    updatedMetadata.MatchingFiles = matches;
    updatedMetadata.MatchCount    = matchCnt;
    updatedMetadata.PodType       = podTypes;
    updatedMetadata.RowType       = rowType;
    updatedMetadata.DeploymentID  = deploymentId;

    % -----------------------------------------
    % Determine unmatched files (CP3/FP3 only)
    % -----------------------------------------
    nonEmpty = ~cellfun(@isempty, matches);
    if any(nonEmpty)
        % Flatten safely; if all empty, leave empty list
        matchedFlat = unique(string([matches{nonEmpty}]));
    else
        matchedFlat = string([]);  % no matches at all
    end
    allFilesStr = string(fileList(:));
    % Case-insensitive comparison
    unmatchedFilesStr = setdiff(lower(allFilesStr), lower(matchedFlat));
    % Recover original casing by indexing back
    % (lower(...) loses original case; map by lower)
    lowerToOrig = containers.Map(lower(allFilesStr), allFilesStr);
    unmatchedOrig = strings(numel(unmatchedFilesStr), 1);
    for k = 1:numel(unmatchedFilesStr)
        unmatchedOrig(k) = lowerToOrig(unmatchedFilesStr(k));
    end

    % -----------------------------------------
    % Append "file-only" rows for unmatched files
    % -----------------------------------------
    nU = numel(unmatchedOrig);
    if nU > 0
        % Use the first row as a template for variable types
        template = updatedMetadata(1, :);

        % Convert template row to "missing" values by type
        for v = 1:width(template)
            val = template{1, v};
            if iscell(val)
                template{1, v} = {[]};
            elseif isstring(val)
                template{1, v} = string(missing);
            elseif ischar(val)
                template{1, v} = '';
            elseif isnumeric(val)
                template{1, v} = NaN;
            elseif islogical(val)
                template{1, v} = false;
            elseif isdatetime(val)
                template{1, v} = NaT;
            elseif isduration(val)
                template{1, v} = seconds(NaN);
            elseif iscategorical(val)
                template{1, v} = categorical(missing); % <undefined>
            else
                template{1, v} = []; % fallback
            end
        end

        % Replicate template for each unmatched file
        unmatchedTbl = repmat(template, nU, 1);

        % Set the "output" columns for file-only rows
        unmatchedTbl.MatchingFiles = repmat({{}}, nU, 1);
        unmatchedTbl.MatchCount    = zeros(nU, 1);
        unmatchedTbl.RowType       = repmat("file-only", nU, 1);

        % Derive PodType from extension
        podTypeOut = strings(nU, 1);
        for k = 1:nU
            [~, ~, ext] = fileparts(unmatchedOrig(k));
            if strcmpi(ext, '.CP3')
                podTypeOut(k) = "C-POD";
            elseif strcmpi(ext, '.FP3')
                podTypeOut(k) = "F-POD";
            else
                podTypeOut(k) = string(missing);
            end
        end
        unmatchedTbl.PodType = podTypeOut;

        % Append to output
        updatedMetadata = [updatedMetadata; unmatchedTbl];
    end
end
