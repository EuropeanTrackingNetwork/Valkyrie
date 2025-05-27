function [isValid,fileGroups,errorMsg] = checkFileExtension(files)
%=====================================
% Function to check the selected files
%=====================================

%TO DO: Do we need this to check for file pairs - could just check
%that at least C/FP3 files selected
    
    % Supported file extensions
    supported = {'.CP1', '.CP3', '.FP1', '.FP3'};
    fileMap = containers.Map(supported, ...
                                 {[], [], [], []});
    
    % Build file lists without growing arrays repeatedly
    for i = 1:numel(files)
        [~, name, ext] = fileparts(files{i});
        ext = upper(ext);
        
        if ~isKey(fileMap, ext)
            isValid = false;
            fileGroups = struct();
            errorMsg = sprintf('Unsupported file type: %s. Supported types: %s.', ...
                                   ext, strjoin(supported, ', '));
            return;
        end
        
        % Append to corresponding extension list
        tempList = fileMap(ext);
        tempList{end+1, 1} = name;  % cell array of names
        fileMap(ext) = tempList;
    end

    % Extract lists once (efficient use of memory)
    cp1 = fileMap('.CP1');
    cp3 = fileMap('.CP3');
    fp1 = fileMap('.FP1');
    fp3 = fileMap('.FP3');

    % Find missing pairs
    missing = [setdiff(cp1, cp3); setdiff(cp3, cp1); ...
               setdiff(fp1, fp3); setdiff(fp3, fp1)];

    if ~isempty(missing)
        isValid = false;
        fileGroups = struct();
        errorMsg = ['Missing corresponding file pairs: ', ...
                        strjoin(missing, ', '), ...
                        '. Ensure .CP1/.CP3 and .FP1/.FP3 pairs are matched.'];
        return;
    end

    % Final output
    isValid = true;
    errorMsg = '';
    fileGroups = struct('cp1', cp1, 'cp3', cp3, 'fp1', fp1, 'fp3', fp3);

end
