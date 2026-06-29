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
%   + it changes RECEIVER to include the POD type
%
% Tiebreaker logic:
%   If the same file matches multiple metadata rows (same receiver ID + date range),
%   the match is awarded only to the row whose STATION_NAME best matches the
%   station-name portion of the filename (word-overlap score). Ties in score
%   keep all equally-good rows.

    % -----------------------------
    % Normalize file list & filter
    % -----------------------------
    isP3 = endsWith(fileList, {'.CP3', '.FP3'}, 'IgnoreCase', true);
    fileList = fileList(isP3);

    % -----------------------------
    % Preallocate output columns
    % -----------------------------
    n = height(metadata);
    matches      = cell(n, 1);
    matchCnt     = zeros(n, 1);
    podTypes     = strings(n, 1);
    rowType      = repmat("metadata", n, 1);
    deploymentId = strings(n, 1);

    % ---------------------------------------------------------
    % Pass 1: collect ALL candidate matches per (file, row)
    % Store as a struct array: fileIdx -> list of matching rowIdxs
    % ---------------------------------------------------------
    % We'll build a nFiles x n logical matrix of candidates, then
    % apply the tiebreaker per file.

    nF        = numel(fileList);
    candidate = false(nF, n);   % candidate(j,i) = file j could match row i
    extByFile = strings(nF, 1); % store extension for POD type lookup

    for i = 1:n

        act = metadata.ACTIVATION_DATE_TIME(i);
        dep = metadata.DEPLOY_DATE_TIME(i);
        val = metadata.VALID_DATA_UNTIL_DATE_TIME(i);

        if ~isnat(act), startDtact = act; end
        if ~isnat(dep), startDtdep = dep; end

        startDayact = dateshift(startDtact, 'start', 'day');
        startDayact.TimeZone = '';
        startDayact.Format   = 'yyyyMMdd';

        startDaydep = dateshift(startDtdep, 'start', 'day');
        startDaydep.TimeZone = '';
        startDaydep.Format   = 'yyyyMMdd';

        endDay = dateshift(val, 'start', 'day');
        endDay.Format    = 'yyyyMMdd';
        endDay.TimeZone  = '';

        % Build deployment identifier
        station     = string(metadata.STATION_NAME(i));
        receiverStr = string(metadata.RECEIVER(i));
        digits      = regexp(receiverStr, '\d+', 'match', 'once');
        if isempty(digits)
            matches{i}  = {};
            matchCnt(i) = 0;
            podTypes(i) = "";
            continue;
        end
        receiverID = digits;

        if isdatetime(startDtdep) && ~isnat(startDtdep)
            startDtdep.TimeZone = 'UTC';
            startDtdep.Format   = "yyyyMMdd'T'HHmmss'Z'";
        end

        dateForId        = datestr(startDaydep, 'yyyy mm dd');
        deploymentId(i)  = station + " " + dateForId + " POD" + receiverID;

        for j = 1:nF
            fname = fileList{j};
            [~, name, ext] = fileparts(fname);

            extByFile(j) = ext;

            % Date extraction
            tokens = regexp(name, '(?<!\w)(\d{4})\s+(\d{2})\s+(\d{2})(?!\w)', 'tokens');
            if isempty(tokens), continue; end
            dateStr  = strjoin(tokens{1}, '');
            fileDate = datetime(dateStr, 'InputFormat', 'yyyyMMdd');
            fileDay  = dateshift(fileDate, 'start', 'day');
            fileDay.TimeZone = '';

            % Receiver ID match
            podMatch = contains(name, "POD" + receiverID) || contains(name, "FPOD_" + receiverID);
            if ~podMatch, continue; end

            % Date range check
            inRange = (fileDay >= startDayact && fileDay <= startDaydep && fileDay < endDay) || ...
                      (fileDay >= startDaydep && fileDay >= startDayact && fileDay < endDay);
            if ~inRange, continue; end

            candidate(j, i) = true;
        end
    end

    % ---------------------------------------------------------
    % Pass 2: station-name scoring — applied to ALL candidates,
    % not just ambiguous ones.
    %
    % For each file:
    %   a) Score every candidate row by station-name overlap.
    %   b) If the best score is 0 (no overlap at all), reject all
    %      candidates for that file — receiver ID + date alone is
    %      not enough when the station name doesn't match at all
    %      (catches KALF* files being pulled into GB*/KF* rows).
    %   c) If best score > 0, keep only rows that match that score
    %      (tiebreaker for multi-row ambiguity).
    % ---------------------------------------------------------
    MIN_STATION_SCORE = 0.0;   % files scoring exactly 0 are rejected

    for j = 1:nF
        rowHits = find(candidate(j, :));
        if isempty(rowHits)
            continue
        end

        [~, fname, ~] = fileparts(fileList{j});
        fnameNorm     = lower(fname);

        scores = zeros(size(rowHits));
        for k = 1:numel(rowHits)
            station    = string(metadata.STATION_NAME(rowHits(k)));
            scores(k)  = stationNameScore(station, fnameNorm);
        end

        bestScore = max(scores);

        if bestScore <= MIN_STATION_SCORE
            % No station name overlap at all — reject this file entirely
            candidate(j, rowHits) = false;
        else
            % Keep only rows that achieved the best score
            losers = rowHits(scores < bestScore);
            candidate(j, losers) = false;
        end
    end

    % ---------------------------------------------------------
    % Pass 3: build per-row match lists from the candidate matrix
    %         Deduplicate file lists (same file may appear via
    %         multiple paths due to case or trailing separators)
    % ---------------------------------------------------------
    for i = 1:n
        fileHits = find(candidate(:, i));
        if isempty(fileHits)
            matches{i}  = {};
            matchCnt(i) = 0;
            podTypes(i) = "";
            continue;
        end

        matchedFiles = unique(fileList(fileHits), 'stable');  % deduplicate
        matches{i}   = matchedFiles;
        matchCnt(i)  = numel(matchedFiles);

        % POD type from extensions of matched files
        exts = extByFile(fileHits);
        if any(strcmpi(exts, '.CP3'))
            podTypes(i) = "C-POD";
        elseif any(strcmpi(exts, '.FP3'))
            podTypes(i) = "F-POD";
        else
            podTypes(i) = "";
        end
    end

    % --- Update RECEIVER to include POD type ---
    for i = 1:n
        if podTypes(i) ~= ""
            rec    = strtrim(string(metadata.RECEIVER(i)));
            digits = regexp(rec, '\d+', 'match', 'once');
            if ~isempty(digits)
                metadata.RECEIVER(i) = podTypes(i) + "-" + digits;
            end
        end
    end

    % -----------------------------------------
    % Build updated metadata rows (annotated)
    % -----------------------------------------
    updatedMetadata               = metadata;
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
        allMatched  = matches(nonEmpty);
        matchedFlat = unique(string(vertcat(allMatched{:})));
    else
        matchedFlat = string([]);
    end
    allFilesStr       = string(fileList(:));
    unmatchedFilesStr = setdiff(lower(allFilesStr), lower(matchedFlat));
    lowerToOrig       = containers.Map(lower(allFilesStr), allFilesStr);
    unmatchedOrig     = strings(numel(unmatchedFilesStr), 1);
    for k = 1:numel(unmatchedFilesStr)
        unmatchedOrig(k) = lowerToOrig(unmatchedFilesStr(k));
    end

    % -----------------------------------------
    % Append "file-only" rows for unmatched files
    % -----------------------------------------
    nU = numel(unmatchedOrig);
    if nU > 0
        template = updatedMetadata(1, :);
        for v = 1:width(template)
            val = template{1, v};
            if iscell(val),            template{1, v} = {[]};
            elseif isstring(val),      template{1, v} = string(missing);
            elseif ischar(val),        template{1, v} = '';
            elseif isnumeric(val),     template{1, v} = NaN;
            elseif islogical(val),     template{1, v} = false;
            elseif isdatetime(val),    template{1, v} = NaT;
            elseif isduration(val),    template{1, v} = seconds(NaN);
            elseif iscategorical(val), template{1, v} = categorical(missing);
            else,                      template{1, v} = [];
            end
        end

        unmatchedTbl                = repmat(template, nU, 1);
        unmatchedTbl.MatchingFiles  = repmat({{}}, nU, 1);
        unmatchedTbl.MatchCount     = zeros(nU, 1);
        unmatchedTbl.RowType        = repmat("file-only", nU, 1);

        podTypeOut = strings(nU, 1);
        for k = 1:nU
            [~, ~, ext] = fileparts(unmatchedOrig(k));
            if strcmpi(ext, '.CP3'),     podTypeOut(k) = "C-POD";
            elseif strcmpi(ext, '.FP3'), podTypeOut(k) = "F-POD";
            else,                        podTypeOut(k) = string(missing);
            end
        end
        unmatchedTbl.PodType = podTypeOut;

        updatedMetadata = [updatedMetadata; unmatchedTbl];
    end
end


% =========================================================================
function score = stationNameScore(stationName, fnameNorm)
% STATIONNAMESCORE
% Returns a [0,1] similarity score between a metadata STATION_NAME and a
% (already-lowercased) filename string.
%
% Strategy — two checks, best score wins:
%
%   1) COMPACT match: strip all separators from the station name and look
%      for it as a substring in the filename. This handles short codes like
%      "FB 1" -> "fb1", "GB 2" -> "gb2", or "Anholt E" -> "anholte".
%      Score = 1.0 if found, 0 otherwise.
%
%   2) WORD match: split station name on separators, look for each token
%      (any length) in the filename, return fraction found. This catches
%      longer names like "Anholt East" where compacting gives "anholteast"
%      which may not appear verbatim in the filename.
%
% The higher of the two scores is returned, so short codes and long names
% are both handled well.
%
% Examples:
%   "FB1"       vs "fb1_pod123 2024 05 01"       -> 1.0 (compact hit)
%   "FB 1"      vs "fb1_pod123 2024 05 01"       -> 1.0 (compact hit)
%   "FB1a"      vs "fb1a_pod123 2024 05 01"      -> 1.0 (compact hit)
%   "Anholt E"  vs "anholte_pod123 2024 05 01"   -> 1.0 (compact hit)
%   "Anholt East" vs "anholt_pod123 2024 05 01"  -> 0.5 (word: "anholt" found, "east" not)
%   "GB2"       vs "fb1_pod123 2024 05 01"       -> 0.0 (neither match)

    stnNorm = lower(char(stationName));

    % --- Score 1: compact (remove all separators, match as substring) ---
    compact      = regexprep(stnNorm, '[^a-z0-9]', '');   % keep only alphanumeric
    if ~isempty(compact)
        compactScore = double(contains(fnameNorm, compact));
    else
        compactScore = 0;
    end

    % --- Score 2: word-level fraction ---
    words     = strsplit(stnNorm, {' ', '-', '_', '.'});
    words     = words(strlength(words) >= 1);   % keep all tokens, even single chars
    if isempty(words)
        wordScore = 0;
    else
        hits = 0;
        for w = 1:numel(words)
            if contains(fnameNorm, words{w})
                hits = hits + 1;
            end
        end
        wordScore = hits / numel(words);
    end

    score = max(compactScore, wordScore);
end
