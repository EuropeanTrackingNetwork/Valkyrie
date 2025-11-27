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

% Specify which fields are used for metadata validation
roles = struct();

fields = fieldnames(spec);
for f = 1:numel(fields)
    fname = fields{f};
    entry = spec.(fname);
    if isfield(entry,'Role')
        roles.(entry.Role) = fname;  % map role → actual column name
    end
end

MetaRoles = roles;

Detections = table();

disp('Loaded roles:'); % DEBUGGING
disp(MetaRoles); % DEBUGGING

% Select files

validExt = {'.CP1', '.CP3', '.FP1', '.FP3'};
[files, path] = fileSelect(validExt);
[isValid, fileGroups, msg] = checkFileExtension(files, check);
isP3 = endsWith(files,'.CP3','IgnoreCase',true) | ...
    endsWith(files,'.FP3','IgnoreCase',true);
filtFiles = files(isP3);

[file, path] = uigetfile('*.csv', 'Select Metadata File');
requiredFields = fieldnames(spec); 

% Metadata validation
tbl = loadMetadataFile(fullfile(path, file)); 
checkMetadataColumns(tbl, requiredFields);
tbl = validateMetadata(tbl,minDate,MetaRoles,dtFormat); 
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
                tmpMinutes = CP3read_DTO(app.path,filename,n);
                ETN = CP3read_2_etn(tmpMinutes);
            case '.FP3'
                % Import FP3 (and FP1) file and convert to ETN
                % format
                tmpMinutes = FP3read_DTO(app.path, filename, n);
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