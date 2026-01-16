%% Choice of file or folder selection
% Function to prompt user to either choose a folder or seperate files to
% upload. 
%
% validExt example: [".cp1" ".cp3" ".fp1" ".fp3"]

function [selectedFiles, selectedPath] = fileSelect(validExt)
    % Prompt user for folder or file selection
    choice = questdlg('Select a folder or individual files?', ...
                      'Choose Selection Mode', ...
                      'Folder', 'Files', 'Cancel', 'Folder');

    selectedFiles = {};
    selectedPath = {};

    % allow user to cancel selection
    if strcmp(choice, 'Cancel') || isempty(choice)
        return;
    end

    switch choice
        case 'Folder'
            folderPath = uigetdir('', 'Select folder with CPOD/FPOD files');
            if folderPath == 0, return; end

            selectedPath = folderPath;

            % Lists all content including subfolders
            allFiles = dir(fullfile(folderPath, '**', '*.*'));
            allFiles = allFiles(~[allFiles.isdir]); % Remove folders and keep only files

            % Filter by extension
            [~,~,exts] = ((arrayfun(@(f) fileparts(f.name), allFiles, 'UniformOutput', false))); % get extention of all files
            isValid = ismember(exts, validExt); %check if extentsion match the valid extentsion

            selectedStructs = allFiles(isValid); % all the files that fit the criteria

            % Return full file paths (important if subfolders exist)
            % The specific filenames are then extracted later
            selectedFiles = fullfile({selectedStructs.folder}, {selectedStructs.name});
           
        case 'Files'
            [files, path] = uigetfile({'*.CP1;*.CP3;*.FP1;*.FP3', ...
                                       'C/FPOD Files (*.CP1, *.CP3, *.FP1, *.FP3)'}, ...
                                       'Select files', ...
                                       'MultiSelect', 'on');
            if isequal(files, 0), return; end

            if ischar(files)
                files = {files};
            end

            selectedFiles = fullfile(path,files);
            selectedPath = path; % since all files are within same folder save only one example
    end
end