%% Create a csv file to bulk upload receivers into the ETN database
% Input: User-provided metadata, where there is a match with uploaded file
% Output columns:
% RCV_MANUFACTURER: will always be CHELONIA
% RECEIVER_ID_SERIAL_NUMBER: POD number
% RECEIVER_MODEL: F- or C-POD
% RCV_STATUS: will always be ACTIVE

function [receivers] = createReceivers(tbl,filename)


% Keep only rows where there is at least one matched file
tblMatch = tbl(tbl.MatchCount > 0, :);


numRows = height(tblMatch) ; % number of receivers based on the unique number used in the metadata

receivers = table('Size', [numRows,4], ...
    'VariableTypes', {'string','double','string','string'}, ...
    'VariableNames', {'RCV_MANUFACTURER','RECEIVER_ID_SERIAL_NUMBER','RECEIVER_MODEL','RCV_STATUS'});

receivers.RCV_MANUFACTURER(:) = "CHELONIA" ;
receivers.RECEIVER_ID_SERIAL_NUMBER = tblMatch.RECEIVER ;
receivers.RECEIVER_MODEL = tblMatch.PodType; % Should be either C-POD or F-POD
receivers.RCV_STATUS(:) = "Active" ;


% Only one receiver entry per POD, even if the POD is used in multiple
% deployments
[~, idx] = unique(receivers.RECEIVER_ID_SERIAL_NUMBER, 'stable');
receivers = receivers(idx, :);

end