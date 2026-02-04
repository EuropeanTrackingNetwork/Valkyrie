% Debuggind code

% Start up function
basePath = fileparts(mfilename('fullpath'));
check = 1; 
cfg = fullfile(basePath,'config','metadata_validation.json');
configText = fileread(cfg);
Config = jsondecode(configText);
minDate = datetime(Config.MinDate, 'TimeZone', 'UTC');
spec = Config.MetadataSpec;

MandatoryFields = Config.MandatoryFields;

OutputOrder = Config.OutputOrder;

% Specify which fields are used for metadata validation
roles = struct(); % to hold metadata with the Roles identifier
dtCols = strings(0,1); % to hold metadata with type Datetime
% Specify the metadata that has the field Options
fo = struct(); % factor options

fields = fieldnames(spec); %get field names
for f = 1:numel(fields)
    fname = fields{f};
    entry = spec.(fname); % get one entry in the metadata spec struct
    if isfield(entry,'Role') % find the ones where Role is included
        roles.(entry.Role) = fname; % Get the column name of the ones where Role is included
    end
    if isfield(entry, 'Type') && strcmpi(string(entry.Type),"Datetime") % get the entries where Type is included and where Type is Datetime
        dtCols(end+1,1) = upper(string(fname)); % Get the column name of each
    end
    entry = spec.(fname); %the entry for the specific metadata column name
    if isfield(entry, "Options")
        % Store as UPPER fieldname for easy matching later
        fo.(upper(fname)) = string(entry.Options);
    end
end

MetaRoles = roles; %metadata with the Roles identifier
DatetimeCols = dtCols; %metadata with type Datetime
FactorOptions = fo;      % metadata factor options  

Detections = table();

% Select files

validExt = {'.CP1', '.CP3', '.FP1', '.FP3'};

% Function where user can upload either single or multiple
% files. Output is the path to the parent folder and the
% filePaths to each specific file.
[filePaths, ~] = fileSelect(validExt);

fileTbl = createFileTable(filePaths);

% This step is to extract the names of each of the files and
% their extention and then save them together in app.files
[~, ~, ~, unmatchedFiles, pairedFiles] = checkFileExtension(fileTbl.FullPath, check);

% Check for dupliate files with different names
[fileTbl, removedFiles] = removeFileDuplicates(fileTbl, pairedFiles);
% writetable(fileTbl, 'fileTblFull.txt'); %to save the table

% Create a list of only the P3 files that are paired:
isP3 = endsWith(fileTbl.NameExt,'.CP3','IgnoreCase',true) | ...
    endsWith(fileTbl.NameExt,'.FP3','IgnoreCase',true);
filtFiles = fileTbl.NameExt(isP3);
filtFilesStr = string(filtFiles(:));

[file, path] = uigetfile('*.csv', 'Select Metadata File');
%requiredFields = (MandatoryFields); 

% Metadata validation
tbl = loadMetadataFile(fullfile(path, file)); 

tbl = createDateTime(tbl, Config); % Takes year, month, date columns and collapses them + gives ISO 8601 format

[tbl, all_identical, projects] = checkMetadataColumns(tbl, MandatoryFields,OutputOrder, DatetimeCols);

if ~all_identical
    chosen = chooseReceiverProjectPopup(projects, tbl);

    if chosen == ""
        % User cancelled: keep Next disabled and ask them to re-upload/fix
        uialert(UIFigure, ...
            "You cancelled Receiver Project selection. Please upload metadata again or correct the file.", ...
            "Selection cancelled");
        return
    end
    % Filter metadata to chosen project
    tbl = filterByReceiverProject(tbl, chosen);
    MetadataUITable.Data = tbl;
end

tbl = validateMetadata(tbl,minDate,MetaRoles,DatetimeCols); 

updatedMetadata = matchMetadataWithPOD(fileTbl.NameExt,tbl);
MetaData = updatedMetadata;


disp(MetaData.MatchingFiles);

% === Build the list of files to process based on metadata matches ===
nonEmpty = ~cellfun(@isempty, MetaData.MatchingFiles);
if any(nonEmpty)
    matchedCells = MetaData.MatchingFiles(nonEmpty);
    
    flat = {};  % will become a column cell array
    for i = 1:numel(matchedCells)
        ci = matchedCells{i};
    
        if isstring(ci)
            % Convert string array to cellstr (each element becomes a char in a cell)
            ci = cellstr(ci(:));
        elseif ischar(ci)
            % Single char row => wrap into cell
            ci = {ci};
        elseif iscell(ci)
            % Nested cell: ensure column shape
            ci = ci(:);
        else
            % Unknown type — skip with a warning
            warning('MatchingFiles{%d} has unsupported type: %s', i, class(ci));
            continue;
        end
    
        % Append
        flat = [flat; ci]; % ensure vertical concatenation
    end
    
    % Remove empties and convert to string array
    flat = flat(~cellfun(@isempty, flat));
    matchedFilesAll = string(flat);

     % Optional: trim whitespace and deduplicate
    matchedFilesAll = unique(strtrim(matchedFilesAll));
else
    matchedFilesAll = string([]); % no matches at all
end          

disp(matchedFilesAll);

% Intersect to ensure we only process files the user selected AND that have metadata
processNames = intersect(filtFilesStr, matchedFilesAll, 'stable');  % preserves UI order


% Find rows whose NameExt is in processNames, preserving the 'stable' order of processNames
[tf, loc] = ismember(processNames, fileTbl.NameExt);
processList = fileTbl.FullPath(loc(tf));   % full paths in UI order

% Build a table with path + filename columns for downstream code
[processFolders, processNamesNoExt, processExt] = arrayfun(@fileparts, cellstr(processList), ...
    'UniformOutput', false);
processFileNames = string(processNamesNoExt) + string(processExt);
processPaths = string(processFolders);

processTbl = table(processPaths, processFileNames, processList, ...
    'VariableNames', {'Path','FileName','FullPath'});

n = '';
if check == 1
    n = '-n';
end

nFiles = height(processTbl);
ProcessingStatus = repmat({'NOT ATTEMPTED'}, nFiles, 1) ;

% Process detection files
for i = 1:height(processTbl)

    filename = processTbl.FileName{i};
    path = processTbl.Path{i};

    try % Wrapped in a try-catch to ensure app will not crash if the import and formatting doesn't work for one of the files
        switch ext
            case '.CP3'
                % Import CP3 (and CP1) file and convert to ETN format
                tmpMinutes = CP3read_DTO(path,filename,n);
                ETN = CP3read_2_etn(tmpMinutes);
            case '.FP3'
                % Import FP3 (and FP1) file and convert to ETN
                % format
                tmpMinutes = FP3read_DTO(path, filename, n);
                ETN = CP3read_2_etn(tmpMinutes);
        end
    catch
        continue; % SKip to next file
    end

    %Set the timezone for ETN data (Detection date time column)
    dep = metadata.DEPLOY_DATE_TIME(i);
    val = metadata.VALID_DATA_UNTIL_DATE_TIME(i);
    ETN.DETECTION_DATE_TIME.TimeZone = 'UTC';
    inRange = ETN.DETECTION_DATE_TIME >= dep & ETN.DETECTION_DATE_TIME <= val;
    ETN = ETN(inRange, :);

    if isempty(Detections)
        Detections = ETN;
    else
        Detections = [Detections; ETN];
    end
end

% Make receiver output
Receivers = createReceivers(MetaData,filtFiles);

% Make an overview of the output
overview = makeFileOverview(filtFiles, MetaData,Detections);

% Prepare and save metadata
isMetadataRow = MetaData.RowType == "metadata";
hasMatch      = MetaData.MatchCount > 0;
cleanedMeta   = MetaData(isMetadataRow & hasMatch, :);

OutputOrder = Config.OutputOrder;
cleanedMeta = CleanMetadata(cleanedMeta,OutputOrder,DatetimeCols);
writetable(cleanedMeta, fullfile(basePath, [nameOnly '_metadata.csv']));
            