function checkReceiverDuplicates()
%CHECKRECEIVERSDUPLICATES  Merge receiver CSV files, remove exact duplicates,
%   flag conflicting entries, and save a clean output.
%
% Workflow:
%   1. User selects one or more receiver CSV files via file picker.
%   2. All files are loaded and combined into one table.
%   3. Exact duplicate rows (identical on ALL columns) are silently removed.
%   4. Rows sharing a RECEIVER_ID_SERIAL_NUMBER but differing on any other
%      column are flagged as CONFLICTS and written to a separate report.
%   5. The clean table (no exact duplicates, no conflicting IDs) is saved.
%
% Output files  (saved to user-chosen location):
%   <name>_receivers_clean.csv    — deduplicated, conflict-free rows
%   <name>_receivers_conflicts.csv — all rows involved in a conflict,
%                                    annotated with SourceFile

%% ── 1. File selection ────────────────────────────────────────────────────
ID_COL = 'RECEIVER_ID_SERIAL_NUMBER'; % primary key column

[files, folder] = uigetfile('*.csv', ...
    'Select receiver CSV files (multi-select OK)', ...
    'MultiSelect', 'on');

if isequal(files, 0)
    disp('No files selected. Exiting.');
    return
end

% uigetfile returns char when one file is chosen, cell when multiple
if ischar(files)
    files = {files};
end

fprintf('Loading %d file(s)...\n', numel(files));

%% ── 1b. Mark which files are already in the database ────────────────────
[dbIdx, confirmed] = listdlg( ...
    'ListString',      files, ...
    'SelectionMode',  'multiple', ...
    'Name',           'Already in database', ...
    'PromptString',   'Select files already uploaded to the database (or cancel for none):', ...
    'ListSize',       [400 150]);

if ~confirmed
    dbIdx = [];  % user cancelled = none are in the database
end

dbFiles  = files(dbIdx);                    % files already in DB
newFiles = files(setdiff(1:end, dbIdx));    % files with new data

fprintf('\nFiles marked as already in database: %d\n', numel(dbFiles));
fprintf('Files with new data: %d\n', numel(newFiles));

%% ── 2. Load and stack all files ──────────────────────────────────────────
allTables = cell(numel(files), 1);

for i = 1:numel(files)
    fPath = fullfile(folder, files{i});
    try
        t = readtable(fPath, 'TextType', 'string');
    catch ME
        warning('Could not read "%s": %s', files{i}, ME.message);
        continue
    end

    if ~ismember(ID_COL, t.Properties.VariableNames)
        warning('"%s" is missing column "%s" – skipped.', files{i}, ID_COL);
        continue
    end

    % Normalise ID column
    rawID = t.(ID_COL);
    if isnumeric(rawID)
        t.(ID_COL) = string(rawID);
    else
        t.(ID_COL) = strtrim(string(rawID));
    end

    t.SourceFile  = repmat(string(files{i}), height(t), 1);
    t.InDatabase  = repmat(ismember(i, dbIdx), height(t), 1);  % <-- new
    allTables{i}  = t;
    fprintf('  Loaded %d rows from %s%s\n', height(t), files{i}, ...
        repmat('  [DB]', ismember(i, dbIdx)));
end

% ── Combine all loaded tables ──────────────────────────────────────────
allTables = allTables(~cellfun(@isempty, allTables));
combined  = vertcat(allTables{:});
fprintf('\nTotal rows after combining: %d\n', height(combined));

% Collect DB IDs NOW, before deduplication can overwrite InDatabase flags
dbIDs = combined.(ID_COL)(combined.InDatabase);   % <-- add this line

%% ── 3. Remove exact duplicate rows ──────────────────────────────────────
% Compare on all columns EXCEPT SourceFile so that the same row appearing
% in two different files is still treated as an exact duplicate.

dataCols = combined.Properties.VariableNames;
dataCols = dataCols(~ismember(dataCols, {'SourceFile', 'InDatabase'})); % <-- fix

[~, firstOccurrence] = unique(combined(:, dataCols), 'rows', 'stable');
nExact = height(combined) - numel(firstOccurrence);
combined = combined(firstOccurrence, :);

fprintf('Exact duplicate rows removed: %d\n', nExact);
fprintf('Rows after exact-duplicate removal: %d\n', height(combined));

%% ── 4. Detect conflicting IDs ────────────────────────────────────────────
% After exact duplicates are gone, any ID appearing more than once means
% the same receiver has contradictory metadata across files.

ids = combined.(ID_COL);

% Count occurrences of each ID
[uniqueIDs, ~, idIdx] = unique(ids);
counts = accumarray(idIdx, 1);

conflictIDs = uniqueIDs(counts > 1);
nConflicts  = numel(conflictIDs);

if nConflicts > 0
    fprintf('\n⚠  %d RECEIVER_ID(s) have conflicting information:\n', nConflicts);
    for k = 1:nConflicts
        fprintf('   %s\n', conflictIDs(k));
    end
else
    fprintf('\nNo conflicting IDs found.\n');
end

% Split into clean and conflict subsets
isConflict = ismember(ids, conflictIDs);
conflictTbl = combined(isConflict,  :);
cleanTbl    = combined(~isConflict, :);

% Remove SourceFile from the clean output (internal bookkeeping only)
cleanTbl.SourceFile = [];

fprintf('\nClean rows (no conflicts):  %d\n', height(cleanTbl));
fprintf('Rows flagged as conflicts:  %d\n', height(conflictTbl));

%% ── 4b. Remove IDs already present in the database ──────────────────────
% dbIDs already collected before deduplication (see above)
isInDB   = ismember(cleanTbl.(ID_COL), dbIDs);
nInDB    = sum(isInDB);

cleanTbl = cleanTbl(~isInDB, :);

cleanTbl.InDatabase = []; 

fprintf('Rows excluded (ID already in database): %d\n', nInDB);
fprintf('Final clean rows:                       %d\n', height(cleanTbl));

%% ── 5. Save outputs ──────────────────────────────────────────────────────
[baseFile, savePath] = uiputfile('*.csv', 'Save output files as');

if isequal(baseFile, 0)
    disp('Save cancelled. Results not written to disk.');
    return
end

[~, nameOnly] = fileparts(baseFile);

cleanPath    = fullfile(savePath, [nameOnly '_receivers_clean.csv']);
conflictPath = fullfile(savePath, [nameOnly '_receivers_conflicts.csv']);

writetable(cleanTbl,    cleanPath);
fprintf('\nClean receivers saved to:\n  %s\n', cleanPath);

if ~isempty(conflictTbl)
    writetable(conflictTbl, conflictPath);
    fprintf('Conflict report saved to:\n  %s\n', conflictPath);
    fprintf('\nReview the conflict file manually: same Receiver ID appears\n');
    fprintf('in multiple source files with different metadata.\n');
else
    fprintf('No conflict file written (no conflicts found).\n');
end

fprintf('\nDone.\n');
end
