function splitDetectionsByDeployment()
%SPLITDETECTIONSBYDEPLOYMENT  Split a large detections CSV into one file
%   per deployment, based on a user-chosen grouping column.
%
% Workflow:
%   1. User selects the detections CSV file.
%   2. User picks which column to split on (default: 'filename').
%   3. User selects an output folder.
%   4. One CSV is written per unique value in the chosen column.
%      Output filenames are sanitised versions of the column value.
%   5. A summary is printed listing each file and its row count.

%% ── 1. Select input file ─────────────────────────────────────────────────
[file, folder] = uigetfile('*.csv', 'Select detections CSV file');

if isequal(file, 0)
    disp('No file selected. Exiting.');
    return
end

filePath = fullfile(folder, file);
fprintf('Loading %s ...\n', file);

opts = detectImportOptions(filePath, 'TextType', 'string');
tbl  = readtable(filePath, opts);

fprintf('Loaded %d rows, %d columns.\n', height(tbl), width(tbl));

%% ── 2. Choose split column ───────────────────────────────────────────────
colNames    = tbl.Properties.VariableNames;
defaultCol  = 'filename';
defaultIdx  = find(strcmpi(colNames, defaultCol), 1);

if isempty(defaultIdx)
    defaultIdx = 1;
end

[colChoice, confirmed] = listdlg( ...
    'ListString',    colNames, ...
    'SelectionMode', 'single', ...
    'InitialValue',  defaultIdx, ...
    'Name',          'Split column', ...
    'PromptString',  'Choose the column to split on:', ...
    'ListSize',      [350 200]);

if ~confirmed
    disp('No column selected. Exiting.');
    return
end

splitCol = colNames{colChoice};
fprintf('Splitting on column: %s\n', splitCol);

%% ── 3. Select output folder ──────────────────────────────────────────────
outFolder = uigetdir(folder, 'Select output folder');

if isequal(outFolder, 0)
    disp('No output folder selected. Exiting.');
    return
end

%% ── 4. Split and write files ─────────────────────────────────────────────
groupVals = unique(tbl.(splitCol));     % one output file per unique value
nGroups   = numel(groupVals);

fprintf('\nFound %d unique value(s) in "%s". Writing files...\n\n', ...
    nGroups, splitCol);

for i = 1:nGroups
    val     = groupVals(i);
    
    % Handle both string and numeric split columns
    if isstring(val) || ischar(val)
        mask = tbl.(splitCol) == val;
        valStr = char(val);
    else
        mask   = tbl.(splitCol) == val;
        valStr = num2str(val);
    end

    subset = tbl(mask, :);

    % Sanitise value for use as a filename (replace spaces and
    % characters that are invalid in filenames with underscores)
    safeName = regexprep(valStr, '[^\w\-]', '_');
    safeName = regexprep(safeName, '_+', '_');   % collapse repeated underscores
    outName  = [safeName '.csv'];
    outPath  = fullfile(outFolder, outName);

    writetable(subset, outPath);
    fprintf('  %-45s  %d rows\n', outName, height(subset));
end

fprintf('\nDone. %d file(s) written to:\n  %s\n', nGroups, outFolder);
end
