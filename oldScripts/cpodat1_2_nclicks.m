function nclicks = cpodat1_2_nclicks(cpodat1, resolution, deployment_start, deployment_end)
% cpodat1 = the output from using importpoddata function on a CP1 file
% deployment_start = when did the pod go in the water (so we can have minutes that
% are not detection-positive)
% deployment_end = when did the pod turn off

arguments
    cpodat1 struct
    resolution (1,:) char {mustBeMember(resolution, {'seconds','minutes','hours'})}
    deployment_start datetime
    deployment_end datetime
end

% Check if there are any detections in this file
numRows = numel(cpodat1);
% If there are no detections, display an error message
if numRows <= 1
    error('This file has no detections.');
end

date = [cpodat1.date];

% Round timestamps to the nearest minute
ClixPer = dateshift(date, 'start', resolution);
% Create a table to group data
ClixPer = table(ClixPer', 'VariableNames', {'Datetime'});
% Group by Timestamp
ClixPer = varfun(@numel, ClixPer, 'GroupingVariables', 'Datetime');
% fill in the 0s
timeVector = table((deployment_start:feval(resolution):deployment_end)', 'VariableNames',{'Datetime'});
% join them together
nclicks = outerjoin(timeVector, ClixPer, 'Keys', {'Datetime'}, 'MergeKeys', true);
% format
nclicks.GroupCount = fillmissing(nclicks.GroupCount, 'constant', 0);
nclicks.Properties.VariableNames = {'time','nclicks'};

%then do a join of the output of this with the output of cpodat3_2_etn and
%then you have all the info for the ETN
end