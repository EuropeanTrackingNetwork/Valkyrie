%% Choice of file or folder selection
% Function to prompt user to either choose a folder or seperate files to
% upload. 

function [selectedFiles, selectedPath] = fileSelect(validExt)
    % Prompt user for folder or file selection
    choice = questdlg('Select a folder or individual files?', ...
                      'Choose Selection Mode', ...
                      'Folder', 'Files', 'Cancel', 'Folder');

    selectedFiles = {};
    selectedPath = {};

    if strcmp(choice, 'Cancel') || isempty(choice)
        return;
    end

    switch choice
        case 'Folder'
            folderPath = uigetdir('', 'Select folder with CPOD/FPOD files');
            if folderPath == 0, return; end

            allFiles = dir(fullfile(folderPath, '**', '*.*'));
            allFiles = allFiles(~[allFiles.isdir]); % Remove folders

            % Filter by extension
            isValid = arrayfun(@(f) ...
                any(strcmpi(validExt, lower(getExt(f.name)))), ...
                allFiles);

            selectedStructs = allFiles(isValid); % all the files that fit the criteria

            selectedFiles = {selectedStructs.name}; % file names with extension
            selectedPath = selectedStructs(1).folder; % path name to folder 

        case 'Files'
            [files, path] = uigetfile({'*.CP1;*.CP3;*.FP1;*.FP3', ...
                                       'C/FPOD Files (*.CP1, *.CP3, *.FP1, *.FP3)'}, ...
                                       'Select files', ...
                                       'MultiSelect', 'on');
            if isequal(files, 0), return; end

            if ischar(files)
                files = {files};
            end

            selectedFiles = files;
            selectedPath = path; % since all files are within same folder save only one example
    end
end

% Local helper to get extension of filenames
function ext = getExt(filename)
    [~, ~, ext] = fileparts(filename);
end