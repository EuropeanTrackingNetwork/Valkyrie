%% Create a csv file to bulk upload receivers into the ETN database
% Input: User-provided metadata
% Output columns:
% RCV_MANUFACTURER: will always be CHELONIA
% RECEIVER_ID_SERIAL_NUMBER: POD number
% RECEIVER_MODEL: F or C-POD
% RCV_STATUS: will always be ACTIVE
% RCV_OWNER_ORGANIZATION: will leave out until the API can fill this in?

function [receivers] = createReceivers(tbl)

numRows = height(tbl) ; % number of receivers based on the unique number used in the metadata

receivers = table('Size', [numRows,4], ...
    'VariableTypes', {'string','double','string','string'}, ...
    'VariableNames', {'RCV_MANUFACTURER','RECEIVER_ID_SERIAL_NUMBER','RECEIVER_MODEL','RCV_STATUS'});

receivers.RCV_MANUFACTURER(:) = "CHELONIA" ;
receivers.RCV_STATUS(:) = "ACTIVE" ;
receivers.RECEIVER_ID_SERIAL_NUMBER = tbl.RECEIVER ;

% For each row in the metadata, find the value in app.filtfiles that matches
% POD_FILE and figure out what the file extension is
[~, baseNames, extensions] = cellfun(@fileparts, app.filtFiles, 'UniformOutput', false);
extMap = containers.Map(baseNames, extensions);
tbl.Extension = string(values(extMap, cellstr(tbl.POD_FILE)));

receivers.RECEIVER_MODEL(tbl.Extension == ".CP3") = "C-POD" ;
receivers.RECEIVER_MODEL(tbl.Extension == ".FP3") = "F-POD" ;

% Only one receiver entry per POD, even if the POD is used in multiple
% deployments
[~, idx] = unique(receivers.RECEIVER_ID_SERIAL_NUMBER, 'stable');
receivers = receivers(idx, :);

end