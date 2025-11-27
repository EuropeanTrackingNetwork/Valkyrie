function [isValid,fileGroups,errorMsg] = checkFileExtension(files,check)
%=====================================
% Function to check the selected files
%=====================================

% Checks if there are a pair of files for all filenames (C/FP1 and C/FP3
% have the same name if they are part of same recording/are a pair).
% If errors found it will shown as an error message that the user have to
% correct before they can move on.
% 
% Input: 
% files = a list of the filenames (with extension) that have been selected
% by the user
% check = will run the check if equal to 1 (default)
%
% Output:
% isValid = TRUE if there are no missing pairs
% fileGroups = the filenames seperated in a struct based on the extension
% of each file
% errorMsg = error message. will be '' if no error found.
    
    % Supported file extensions
    supported = {'.CP1', '.CP3', '.FP1', '.FP3'};
    fileMap = containers.Map(supported, ...
                                 {[], [], [], []});
    
    % Build file lists without growing arrays repeatedly
    for i = 1:numel(files)
        [~, name, ext] = fileparts(files{i});
        ext = upper(ext);
        
        if ~isKey(fileMap, ext) % check for valid file type
            isValid = false;
            fileGroups = struct();
            errorMsg = sprintf('Unsupported file type: %s. Supported types: %s.', ...
                                   ext, strjoin(supported, ', '));
            return; % will only run until here if error found
        end
        
        % Append to corresponding extension list
        tempList = fileMap(ext);
        tempList{end+1, 1} = name;  % cell array of names
        fileMap(ext) = tempList;
    end

    % Check that not only C/FP1 files are added - if an C/FP1 is added the
    % corresponding file also has to be there 

    % Extract lists once (efficient use of memory)
    cp1 = fileMap('.CP1');
    cp3 = fileMap('.CP3');
    fp1 = fileMap('.FP1');
    fp3 = fileMap('.FP3');

    % Always enforce: CP1 → CP3 and FP1 → FP3
    missing = [setdiff(cp1, cp3); setdiff(fp1, fp3)];

    % Find missing pairs - added as an if statement to be able to 'toggle'
    % it on/off
    if check == 1 % make sure the variable check is specified in app
        missing = [missing; setdiff(cp3, cp1);setdiff(fp3, fp1)];
    end

    
    if ~isempty(missing)
        isValid = false;
        fileGroups = struct();
        errorMsg = ['Missing corresponding file pairs: ', ...
                        strjoin(missing, ', '), ...
                        '. Ensure .CP1/.CP3 and .FP1/.FP3 pairs are matched.'];
        return; % will only run until here if error found
    end
    
    % Final output
    isValid = true;
    errorMsg = '';
    fileGroups = struct('cp1', {cp1}, 'cp3', {cp3}, 'fp1', {fp1}, 'fp3', {fp3});

end
