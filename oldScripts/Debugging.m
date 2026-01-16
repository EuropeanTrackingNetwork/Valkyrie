% Debuggind code

% Start up function
basePath = fileparts(mfilename('fullpath'));
check = 1; 
cfg = fullfile(basePath,'config','metadata_validation.json');
configText = fileread(cfg);
Config = jsondecode(configText);
minDate = datetime(Config.MinDate, 'TimeZone', 'UTC');
spec = Config.MetadataSpec;

dtFormat = Config.datetimeFormats; % get the format of datetime to be accepted

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
[filePaths, path] = fileSelect(validExt);

% get info on each file - used to filter if there are file duplicates:
info = cellfun(@dir, filePaths);   % struct array, one per file
name = string({info.name})';
bytes = [info.bytes]';

sig = lower(name) + "|" + string(bytes);        % signature
[~, ia] = unique(sig, 'stable');

dups = setdiff(1:numel(filePaths), ia);

duplicateFiles = filePaths(dups);  % store duplicates first
UniquefilePaths  = filePaths(ia);    % keep uniques


% This step is to extract the names of each of the files and
% their extention and then save them together in app.files
[~,names,ext] = fileparts(UniquefilePaths);
files = string(names)+ext;
files = cellstr(files);
[isValid, fileGroups, msg, unmatchedFiles,pairedFiles] = checkFileExtension(files, check);

isP3 = endsWith(pairedFiles,'.CP3','IgnoreCase',true) | ...
    endsWith(pairedFiles,'.FP3','IgnoreCase',true);
filtFiles = pairedFiles(isP3);

[file, path] = uigetfile('*.csv', 'Select Metadata File');
%requiredFields = (MandatoryFields); 

% Metadata validation
tbl = loadMetadataFile(fullfile(path, file)); 
tbl = checkMetadataColumns(tbl, MandatoryFields,OutputOrder, DatetimeCols);
tbl = validateMetadata(tbl,minDate,MetaRoles,dtFormat,MandatoryFields); 
%[~, filename, ~] = fileparts(filtFiles);
%tbl = matchFilenamesWithPOD(tbl, filename);
updatedMetadata = matchMetadataWithPOD(files,tbl);
MetaData = updatedMetadata;

% === Build the list of files to process based on metadata matches ===
nonEmpty = ~cellfun(@isempty, MetaData.MatchingFiles);
if any(nonEmpty)
    % Flatten all matched files into a single list
    matchedFilesAll = string(vertcat(MetaData.MatchingFiles{nonEmpty}));
else
    matchedFilesAll = string([]); % no matches at all
end

% Work off the filtered CP3/FP3 files to stay consistent with UI selection
filtFilesStr = string(filtFiles(:));

% Intersect to ensure we only process files the user selected AND that have metadata
processList = intersect(filtFilesStr, matchedFilesAll, 'stable');  % 'stable' preserves UI order



n = '';
if check == 1
    n = '-n';
end

% Process detection files
for i = 1:numel(filtFiles)
    [~, filename, ext] = fileparts(filtFiles{i});

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
            