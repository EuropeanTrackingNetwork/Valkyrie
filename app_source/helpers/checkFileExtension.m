function [isValid,fileGroups,errorMsg,missing, pairedFiles] = checkFileExtension(files,check)
%=====================================
% Function to check the selected files
%=====================================

% Checks if there are a pair of files for all filenames (C/FP1 and C/FP3
% have the same name if they are part of same recording/are a pair).
% If errors found it will shown as an error message that the user have to
% correct before they can move on. 
% It also checks if files have more than one extension (e.g.
% filename.CP1.CP1 or filename.CP1.CP3) and removes those cases.
% The user will be provided with the filenames and filepaths of all files
% that did not have a match or had ambiguous extensions.
% 
% Input: 
% files = a list of the filenames (with extension) that have been selected
% by the user
% check = will run the check if equal to 1 (default)
%
% Output:
% isValid = TRUE if there are no missing pairs
% fileGroups = the filenames seperated in a struct based on the extension
% of each file. No files removed so could have missing filepairs
% errorMsg = error message. will be '' if no error found.
% pairedFiles = only the files where both the files of a filepair is
% present
% missing = the files that are missing a complementary file
    
% If the check input variable is included it means it will be assumed as 1,
% meaning that the function checks that both types of files of a filepair
% is present
    if nargin < 2
        check = 1;
    end

    % Supported file extensions
    supported = {'.CP1', '.CP3', '.FP1', '.FP3'};
    supportSet = string(supported);


    % Prepare per-extension name lists (names only, as before)
    fileMap = containers.Map(supported, {[], [], [], []});


    % Per-extension maps: name -> full path(s) (to emit 'missing' with path+ext)
    pathMap = struct();
    pathMap.CP1 = containers.Map('KeyType','char','ValueType','any');
    pathMap.CP3 = containers.Map('KeyType','char','ValueType','any');
    pathMap.FP1 = containers.Map('KeyType','char','ValueType','any');
    pathMap.FP3 = containers.Map('KeyType','char','ValueType','any');

    invalidDoubleExtPaths = {};  % full paths with double CP/FP tokens

    
    % Build file lists without growing arrays repeatedly
    for i = 1:numel(files)
        [~, name, ext] = fileparts(files{i});
        extU = upper(ext); % just to make sure all file extensions are upper case
        

        % Validate extension
        if ~ismember(extU, supported)
            isValid    = false;
            fileGroups = struct();
            errorMsg   = sprintf('Unsupported file type: %s. Supported types: %s.', ...
                                 extU, strjoin(supported, ', '));
            missing    = {};
            pairedFiles= {};
            return;
        end

        % Detect "double extension" in the name part (e.g., "file01.CP1" before final ".CP1/.CP3")
        % Examples: "file01.CP1.CP1", "file01.CP1.CP3", "file01.FP3.FP1", etc.
        hasExtraCPFP = ~isempty( regexp(name, '\.(?:CP|FP)[13]$', 'once', 'ignorecase') );
        if hasExtraCPFP
            % Keep for reporting; exclude from pairing
            invalidDoubleExtPaths{end+1,1} = files{i};
            continue;
        end

        % Append to corresponding extension list
        tempList = fileMap(extU);
        tempList{end+1, 1} = name;  % cell array of names
        fileMap(extU) = tempList; % adds the filename to the group matching its extension

       % Track full path(s) per name per extension (to build 'missing' with paths)
        key = erase(extU, '.');  % "CP1" | "CP3" | "FP1" | "FP3"
        m   = pathMap.(key);

        nameKey = char(name);    % Map keys must be char
        if isKey(m, nameKey)
            m(nameKey) = [m(nameKey); {files{i}}];
        else
            m(nameKey) = {files{i}};
        end
        pathMap.(key) = m;

    end

    % Check that not only C/FP1 files are added - if an C/FP1 is added the
    % corresponding file also has to be there 

    % Extract lists (names only)
    cp1 = fileMap('.CP1');
    cp3 = fileMap('.CP3');
    fp1 = fileMap('.FP1');
    fp3 = fileMap('.FP3');


    % --- PAIRED BASE NAMES (recordings that have both files in a pair) ---
    pairedCP = intersect(cp1, cp3, 'stable'); % base names that have both CP1 and CP3
    pairedFP = intersect(fp1, fp3, 'stable'); % base names that have both FP1 and FP3
    
    % Make sure empty pairs are handled correctly
    pairedCP = string(pairedCP); pairedCP(pairedCP=="") = []; 
    pairedFP = string(pairedFP); pairedFP(pairedFP=="") = [];

 
    % Build pairedFiles (names + extension), excluding invalid doubles
    pairedFiles = [ strcat(pairedCP, ".CP1"); strcat(pairedCP, ".CP3"); ...
                    strcat(pairedFP, ".FP1"); strcat(pairedFP, ".FP3") ];
    pairedFiles = cellstr(pairedFiles);


    % --- Missing pairs (report as full paths + ext) ---
    % CP1 present but CP3 missing; FP1 present but FP3 missing:
    miss_cp1_vs_cp3 = setdiff(cp1, cp3);
    miss_fp1_vs_fp3 = setdiff(fp1, fp3);
    % CP3 present but CP1 missing; FP3 present but FP1 missing (if check==1):
    miss_cp3_vs_cp1 = setdiff(cp3, cp1);
    miss_fp3_vs_fp1 = setdiff(fp3, fp1);

    % Expand names to full paths via pathMap (keeps extensions intact)
    missingPaths = {};
    missingPaths = [ missingPaths; expandPaths(pathMap.CP1, miss_cp1_vs_cp3) ];  % CP1 lacking CP3
    missingPaths = [ missingPaths; expandPaths(pathMap.FP1, miss_fp1_vs_fp3) ];  % FP1 lacking FP3
    if check == 1
        missingPaths = [ missingPaths; expandPaths(pathMap.CP3, miss_cp3_vs_cp1) ]; % CP3 lacking CP1
        missingPaths = [ missingPaths; expandPaths(pathMap.FP3, miss_fp3_vs_fp1) ]; % FP3 lacking FP1
    end

    % Add invalid double-extension files to 'missing' (full paths already include ext)
    missingPaths = [ invalidDoubleExtPaths; missingPaths ];

    % Unique, preserve order
    missing = unique(missingPaths, 'stable');

    % --- Final outputs & message ---
    if ~isempty(missing)
        isValid    = false;
        fileGroups = struct();   % keep empty since user must correct before moving on
        nInvalid   = numel(invalidDoubleExtPaths);
        nUnpaired  = numel(missing) - nInvalid;
        errorMsg   = sprintf(['Found %d problematic file(s): %d with multiple CP/FP tokens in the filename, ' ...
                              '%d lacking a matching pair (.CP1/.CP3 or .FP1/.FP3).\n' ...
                              'See the ''missing'' list for full paths.'], ...
                              numel(missing), nInvalid, nUnpaired);
        return;
    end

    isValid   = true;
    errorMsg  = '';
    fileGroups = struct('cp1', {cp1}, 'cp3', {cp3}, 'fp1', {fp1}, 'fp3', {fp3});


end


% --- Helper: expand name list to full paths via a Map(name -> paths) ---
function out = expandPaths(mapObj, namesCell)
    out = {};
    if isempty(namesCell), return; end
    % namesCell can be cellstr or string
    if isstring(namesCell), namesCell = cellstr(namesCell); end
    for i = 1:numel(namesCell)
        nm = char(namesCell{i});
        if isKey(mapObj, nm)
            arr = mapObj(nm);
            out = [out; arr(:)];
        end
    end
end

