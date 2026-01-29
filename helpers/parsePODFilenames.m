
function P = parsePODFilenames(nameExtList)
% Parse a list of POD files-with-extension strings into canonical parts:
%   - Date (YYYYMMDD)
%   - Receiver digits (e.g., 1739)
%   - File number (normalized to 2 digits: 01, 02, ...)
%   - PodFamily: CP|FP
%   - ExtKind:   "1"|"3"  (from CP1/CP3/FP1/FP3)
%   - Flags: HasPART, HasSoft (Based on a case where users have added
%   FromFPODSoftware at the end of filename, or when users make a cropped
%   file
%   - BaseKey = yyyymmdd_receiver_fileNN
%   - PairKey = BaseKey_PodFamily_ExtKind
%   - NameScore = a score used to evaluate the names to keep the 
% The station name is ignored since this is something the user can choose
% and this can therefore be extremely unreliable and inconsistent

% Input: the list of filenames 
% Output: a table with all the parts explained above

    % Normalize to string column
    S = string(nameExtList(:));
    S(ismissing(S)) = "";


    % --- Collapse any non-final CP/FP extension tokens ---
    % Remove any ".CP1/.CP3/.FP1/.FP3" that are followed by another CP/FP token.
    % Example: "file01.CP1.CP3" -> remove first ".CP1" -> "file01.CP3"
    S = regexprep(S, '\.(?:CP|FP)[13](?=\.(?:CP|FP)[13]\b)', '', 'ignorecase');


    n = numel(S);
    DateStr  = strings(n,1);
    RecID    = strings(n,1);
    FileNN   = strings(n,1);
    PodFamily = strings(n,1);
    ExtKind   = strings(n,1);
    HasPART   = false(n,1);
    HasSoft   = false(n,1);


    % --- Parse the **last** extension only ---
    % Using fileparts to respect last '.' reliably.
    [~, ~, ext] = cellfun(@fileparts, cellstr(S), 'UniformOutput', false);
    extUpper = upper(string(erase(string(ext), ".")));  % "CP1", "FP3"

    isCP = startsWith(extUpper, "CP");
    isFP = startsWith(extUpper, "FP");
    PodFamily(isCP) = "CP";
    PodFamily(isFP) = "FP";
    ExtKind = regexprep(extUpper, '^[A-Z]+', '');     % keep trailing digits, e.g., "3"

    % Remove last extension to parse the core
    core = regexprep(S, '\.[^.]+$', '');   % remove last .ext


    for i = 1:n
        c = core(i);

        % 1) Date: accept 4-digit year, 1–2-digit month/day, any non-digits as separators
        %    Matches "2023 10 31", "2023-10-31", "2023_10_31"
        
        datePat = '(?<Y>\d{4})\D*(?<M>\d{1,2})\D*(?<D>\d{1,2})(?=\D*(?:[FC]?\D*POD\d+))';
        d = regexp(c, datePat, 'names', 'once');
        
        if ~isempty(d)
            DateStr(i) = sprintf('%04d%02d%02d', str2double(d.Y), str2double(d.M), str2double(d.D));
        else
            DateStr(i) = "UNKNOWNDATE";
        end


        % 2) Receiver digits: accept POD1990, CPOD1686, FPOD_7043, POD 1593
        r = regexp(c, '(?:F?C?POD)[_\s]*(?<RID>\d+)', 'names', 'once', 'ignorecase');
        if ~isempty(r)
            RecID(i) = string(r.RID);
        else
            RecID(i) = "UNKNOWN";
        end

        % 3) File number: accept "file01", "file 1", "file0", "file00"
        
        filePat = '(?i)file\s*(?<N>\d+)';
        f = regexp(c, filePat, 'names', 'once');

        if ~isempty(f)
            FileNN(i) = sprintf('%02d', str2double(f.N));   % normalize 1 -> "01"
        else
            FileNN(i) = "NA";
        end

        % 4) Flags for tie-breaking (we still ignore them in the key)
        HasPART(i) = ~isempty(regexp(c, '(?i)\s+PART.*$', 'once'));
        HasSoft(i) = ~isempty(regexp(c, '(?i)(?:^|[_\s-])(FPODsoftware|CPODsoftware)\b', 'once'));
    end


    % ---- Compute NameScore (ranking quality of filenames) ----
    NameScore = zeros(n,1);
    
    % Good: matches canonical-style format
    isClean = ~cellfun(@isempty, regexp(core, ...
        '^[A-Za-z0-9_]+?\s+\d{4}\s+\d{2}\s+\d{2}\s+POD\d+\s+file\d+', ...
        'once'));
    
    % Extra station names after POD
    hasExtraStation = ~cellfun(@isempty, regexp(core, ...
        'POD\d+\s+[A-Za-z]+[A-Za-z0-9]*\s+file', 'once'));
    
    % Multiple POD tokens
    hasMultiplePOD = cellfun(@(x) numel(regexp(x,'POD\d+')) > 1, cellstr(core));
    
    % Missing fileNN (very rare troubleshooting case)
    missingFileNN = (FileNN == "NA");
    
    % Weighted score: lower = better
    NameScore = ...
        (isClean==0).*0 + ...   % perfect names get 0
        hasExtraStation .* 3 + ...
        hasMultiplePOD  .* 3 + ...
        HasPART         .* 2 + ...
        HasSoft         .* 2 + ...
        missingFileNN   .* 5;

    BaseKey = DateStr + "_" + RecID + "_" + FileNN;
    PairKey = BaseKey + "_" + PodFamily + "_" + ExtKind;


    P = table(S,BaseKey,PairKey,PodFamily,ExtKind,HasPART,HasSoft,NameScore, ...
          'VariableNames', ...
          {'NameExt','BaseKey','PairKey','PodFamily','ExtKind','HasPART','HasSoft','NameScore'});

end