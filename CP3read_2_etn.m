function ETN = CP3read_2_etn(outputminutes, resolution)

% Takes the output from the CP3read function and turns it into the correct
% format for the ETN database

% outputminutes = the first output structure from CP3read
% the user-selected resolution of the data (minutes, hours)

% MINUTE or HOUR RESOLUTION and HARBOR PORPS ONLY
% NALL IS WRONG %

arguments
    outputminutes struct
    resolution (1,:) char {mustBeMember(resolution, {'minutes','hours'})}
end

% extract data
fieldsToKeep = {'time', 'nall', 'clickHi', 'clickMed'};
allFields = fieldnames(outputminutes);
fieldsToRemove = setdiff(allFields, fieldsToKeep);
ETN = rmfield(outputminutes, fieldsToRemove);
ETN = struct2table(ETN);

% Convert the serial dates to datetime
ETN.time = datetime([ETN.time], 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss');

% DPM
ETN.dpm = double(ETN.clickMed ~= 0 | ETN.clickHi ~= 0);

% number_clicks_filtered
ETN.number_clicks_filtered = ETN.clickMed + ETN.clickHi ;

% remove clickHi and clickMed
ETN.clickHi = [] ;
ETN.clickMed = [] ;

%hour resolution
if resolution == "hours"
    ETN.time = dateshift([ETN.time], 'start', 'hour');
    ETN = varfun(@sum, ETN, 'GroupingVariables', {'time'}, 'InputVariables', {'dpm','nall','number_clicks_filtered'}); % DPM/H
    ETN.dph = ETN.sum_dpm > 0; % DPH
    ETN.GroupCount = [];
    ETN.Properties.VariableNames = {'time','dpm','nall','number_clicks_filtered','dph'};
end

% species
ETN.species = repmat("NBHF", height(ETN), 1);

end