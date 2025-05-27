function ETN = cpodat3_2_etn(cpodat3, resolution, deployment_start, deployment_end, onlyporp)
% cpodat3 = the output from using importpoddata function on a CP3 file
% resolution = do you want it in seconds minutes or hours resolution
% deployment_start = when did the pod go in the water (so we can have minutes that
% are not detection-positive)
% deployment_end = when did the pod turn off
% onlyporp = do you want to filter out the dolphins and sonar
arguments
    cpodat3 struct
    resolution (1,:) char {mustBeMember(resolution, {'seconds','minutes','hours'})}
    deployment_start datetime
    deployment_end datetime
    onlyporp logical = true
end

% Check if there are any detections in this file
numRows = numel(cpodat3);
% If there are no detections, display an error message
if numRows <= 1
    error('This file has no detections.');
end
    

% Extract data
date = [cpodat3.date];
quality = arrayfun(@(x) x.clicktrain.quality, cpodat3);
duration = [cpodat3.duration];
species = arrayfun(@(x) x.clicktrain.species, cpodat3, 'UniformOutput', false);
[uniqueSpecies, ~, species] = unique(species);

% Keep high mod Q only, not filtering based on species, group by it
validQuality = find(quality == 3 | quality == 2); %high and mod, not low
date = date(validQuality);
species = species(validQuality)';
duration = duration(validQuality);


if resolution == "seconds"
    % Create Clix/S
    roundedSeconds = dateshift(date, 'start', 'second');
    % Create a table to group data
    ClixPerS = table(roundedSeconds', duration', species', 'VariableNames', {'time', 'duration', 'species'});
    % Group by Timestamp and species
    ClixPerS = varfun(@sum, ClixPerS, 'GroupingVariables', {'time', 'species'}, 'InputVariables', 'duration');

    %creating detection positive seconds
    timeVector = (deployment_start:seconds(1):deployment_end)';
    expandedTimeVector = repmat(timeVector, length(uniqueSpecies), 1);
    expandedSpeciesVector = repelem(uniqueSpecies', length(timeVector));
    [~, ~, expandedSpeciesVector] = unique(expandedSpeciesVector);

    % Create the new table with the expanded time and species vectors
    ETN = table(expandedTimeVector, expandedSpeciesVector, 'VariableNames', {'time', 'species'});

    % Merge the new table with your original event table
    ETN = outerjoin(ETN, ClixPerS, 'Keys', {'time', 'species'}, 'MergeKeys', true);
    ETN.nclicks = fillmissing(ETN.GroupCount, 'constant', 0);
    ETN.milliseconds = fillmissing(ETN.sum_duration, 'constant', 0);
    ETN = ETN(:,[1,2,5,6]);

    %Create DPS
    ETN.dps = ETN.nclicks > 0;

    clear ClixPerS expandedSpeciesVector expandedTimeVector timeVector roundedSeconds validQuality

end


if resolution == "minutes" || resolution == "hours"
    %Creating #clix/M
    % Round timestamps to the nearest minute
    roundedMinutes = dateshift(date, 'start', 'minute');
    % Create a table to group data
    ClixPerM = table(roundedMinutes', duration', species', 'VariableNames', {'Datetime', 'Duration', 'Species'});
    % Group by Timestamp andEventType1
    ClixPerM = varfun(@sum, ClixPerM, 'GroupingVariables', {'Datetime', 'Species'}, 'InputVariables', 'Duration');

    % creating detection positive minutes
    timeVector = (deployment_start:minutes(1):deployment_end)';
    expandedTimeVector = repmat(timeVector, length(uniqueSpecies), 1);
    expandedSpeciesVector = repelem(uniqueSpecies', length(timeVector));
    [~, ~, expandedSpeciesVector] = unique(expandedSpeciesVector);

    % Create the new table with the expanded time and species vectors
    ETN = table(expandedTimeVector, expandedSpeciesVector, 'VariableNames', {'Datetime', 'Species'});

    % Merge the new table with your original event table
    ETN = outerjoin(ETN, ClixPerM, 'Keys', {'Datetime', 'Species'}, 'MergeKeys', true);
    ETN.GroupCount = fillmissing(ETN.GroupCount, 'constant', 0);
    ETN.sum_Duration = fillmissing(ETN.sum_Duration, 'constant', 0);

    %Create DPM
    ETN.DPM = ETN.GroupCount > 0;

    ETN.Properties.VariableNames = {'time','species','nclicks','milliseconds','dpm'};

    clear roundedMinutes ClixPerM timeVector expandedTimeVector expandedSpeciesVector
end


%creating DPM/H and DPH
if resolution == "hours"
    ETN.time = dateshift(ETN.time, 'start', 'hour');
    ETN = varfun(@sum, ETN, 'GroupingVariables', {'time', 'species'}, 'InputVariables', {'milliseconds','dpm'}); % DPM/H
    ETN.dph = ETN.sum_dpm > 0; % DPH
    ETN.GroupCount = [];
    ETN.Properties.VariableNames = {'time','species','milliseconds','dpm','dph'};
end

%add species back in
ETN.species = categorical(ETN.species, 1:length(uniqueSpecies), uniqueSpecies);

%add quality back in
ETN.quality = repmat(3, height(ETN), 1);

% change duration from s to ms
ETN.milliseconds = ETN.milliseconds*1000;

% change time format
ETN.time = datetime(ETN.time, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');

% filter to only be porps
if onlyporp == true
    ETN = ETN(ETN.species == "NBHF", :);
end

end