%% Create a csv file to bulk upload receivers into the ETN database
% Input: User-provided metadata, where there is a match with uploaded file
% Output columns:
% RCV_MANUFACTURER: will always be CHELONIA
% RECEIVER_ID_SERIAL_NUMBER: POD number
% RECEIVER_MODEL: F or C-POD
% RCV_STATUS: will always be ACTIVE
% RCV_OWNER_ORGANIZATION: will leave out until the API can fill this in?

function [receivers] = createReceivers(tbl,filename)

% remove all rows in metadata wihtout a file match
% Keep only rows where MATCH == "Y"
tblMatch = tbl(tbl.MATCH == "Y", :);

numRows = height(tblMatch) ; % number of receivers based on the unique number used in the metadata

receivers = table('Size', [numRows,4], ...
    'VariableTypes', {'string','double','string','string'}, ...
    'VariableNames', {'RCV_MANUFACTURER','RECEIVER_ID_SERIAL_NUMBER','RECEIVER_MODEL','RCV_STATUS'});

receivers.RCV_MANUFACTURER(:) = "CHELONIA" ;
receivers.RCV_STATUS(:) = "ACTIVE" ;
receivers.RECEIVER_ID_SERIAL_NUMBER = tblMatch.RECEIVER ;

% For each row in the metadata, find the value in filenames that matches
% POD_FILE and figure out what the file extension is
[~, baseNames, extensions] = cellfun(@fileparts, filename, 'UniformOutput', false);
extMap = containers.Map(baseNames, extensions);
tblMatch.Extension = string(values(extMap, cellstr(tblMatch.POD_FILE)));

receivers.RECEIVER_MODEL(tblMatch.Extension == ".CP3") = "C-POD" ;
receivers.RECEIVER_MODEL(tblMatch.Extension == ".FP3") = "F-POD" ;

% Only one receiver entry per POD, even if the POD is used in multiple
% deployments
[~, idx] = unique(receivers.RECEIVER_ID_SERIAL_NUMBER, 'stable');
receivers = receivers(idx, :);

end