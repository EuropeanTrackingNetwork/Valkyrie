deployment_start = datetime("03-Jun-2021 00:00:00",'InputFormat','dd-MMM-yyyy HH:mm:ss'); %putting this in manually for now
deployment_end = datetime("04-Jun-2021 21:49:00",'InputFormat','dd-MMM-yyyy HH:mm:ss');


function ETN = cpodat3_2_etn(cpodat3, resolution, deployment_start, deployment_end, onlyporp)
% cpodat3 = the output from using importpoddata function on a CP3 file
% resolution = do you want it in seconds minutes or hours resolution
% deployment_start = when did the pod go in the water (so we can have minutes that
% are not detection-positive)
% deployment_end = when did the pod turn off
% onlyporp = do you want to filter out the dolphins and sonar

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
quality = quality(validQuality);
duration = duration(validQuality);


if resolution == "seconds"
    % Create Clix/S
    roundedSeconds = dateshift(date, 'start', 'second');
    % Create a table to group data
    ClixPerS = table(roundedSeconds', quality', duration', species', 'VariableNames', {'Datetime', 'Quality', 'Duration', 'Species'});
    % Group by Timestamp and species
    ClixPerS = varfun(@sum, ClixPerS, 'GroupingVariables', {'Datetime', 'Species'}, 'InputVariables', 'Duration');

    %creating detection positive seconds
    timeVector = (deployment_start:seconds(1):deployment_end)';
    expandedTimeVector = repmat(timeVector, length(uniqueSpecies), 1);
    expandedSpeciesVector = repelem(uniqueSpecies', length(timeVector));
    [~, ~, expandedSpeciesVector] = unique(expandedSpeciesVector);

    % Create the new table with the expanded time and species vectors
    ETN = table(expandedTimeVector, expandedSpeciesVector, 'VariableNames', {'Datetime', 'Species'});

    % Merge the new table with your original event table
    ETN = outerjoin(ETN, ClixPerS, 'Keys', {'Datetime', 'Species'}, 'MergeKeys', true);
    ETN.GroupCount = fillmissing(ETN.GroupCount, 'constant', 0);
    ETN.sum_Duration = fillmissing(ETN.sum_Duration, 'constant', 0);

    %Create DPS
    ETN.DPS = ETN.GroupCount > 0;

    clear ClixPerS expandedSpeciesVector expandedTimeVector timeVector roundedSeconds validQuality

end


if resolution == "minutes" || resolution == "hours"
    %Creating #clix/M
    % Round timestamps to the nearest minute
    roundedMinutes = dateshift(date, 'start', 'minute');
    % Create a table to group data
    ClixPerM = table(roundedMinutes', quality', duration', species', 'VariableNames', {'Datetime', 'Quality', 'Duration', 'Species'});
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

    clear roundedMinutes ClixPerM timeVector expandedTimeVector expandedSpeciesVector
end

%creating DPM/H and DPH
if resolution == "hours"
    ETN.Hour = dateshift(ETN.Datetime, 'start', 'hour');
    ETN = varfun(@sum, ETN, 'GroupingVariables', {'Hour', 'Species'}, 'InputVariables', {'sum_Duration','DPM'}); % DPM/H
    ETN.DPH = ETN.sum_DPM > 0; % DPH
    ETN.Properties.VariableNames{'sum_sum_Duration'} = 'sum_Duration';
end

%add species back in
ETN.Species = categorical(ETN.Species, 1:length(uniqueSpecies), uniqueSpecies);

%add quality back in
ETN.quality = repmat(3, height(ETN), 1);

% change duration from s to ms
ETN.sum_Duration = ETN.sum_Duration*1000;

% change date format
ETN.Hour = datetime(ETN.Hour, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');

% move cols around
ETN = ETN(:,[1, 2, 4, 5, 6, 7]);

%rename columns
ETN.Properties.VariableNames = {'time','species','milliseconds','dpm','dph','quality'};

% filter to only be porps
if onlyporp == "TRUE"
    ETN = ETN(ETN.species == "NBHF", :);
end

end