function ETN = CP3read_2_etn(outputminutes)

% Takes the output from the CP3read_DTO function and turns it into the correct
% format for the ETN database

% outputminutes = the first output structure from CP3read
% the user-selected resolution of the data (minutes, hours)

% MINUTE RESOLUTION and HARBOR PORPS ONLY

arguments
    outputminutes struct
end

% extract data
fieldsToKeep = {'filename','time', 'temperature', 'angle', 'nall', 'clickLow', 'clickHi', 'clickMed', 'no_of_clicks', 'train'};
allFields = fieldnames(outputminutes);
fieldsToRemove = setdiff(allFields, fieldsToKeep);
ETN = rmfield(outputminutes, fieldsToRemove);
ETN = struct2table(ETN);

% Convert the serial dates to datetime
ETN.time = datetime([ETN.time], 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss');
ETN.time = dateshift(ETN.time, 'start','second','nearest');  % rounds to nearest second, to correct rounding errors from datenum conversion

% Separate out by quality
ETN = stack(ETN, {'clickHi', 'clickMed', 'clickLow'}, 'NewDataVariableName','number_clicks_filtered','IndexVariableName','quality') ;
ETN.quality = double(categorical(ETN.quality, {'clickLow', 'clickMed', 'clickHi'})) ;
ETN.no_of_clicks = [];

% After separation: DPM, milliseconds, N_filtered

% DPM
ETN.dpm = double(ETN.number_clicks_filtered ~= 0);

% Dive into the train data to calculate train duration (milliseconds) and
% IPI (for buzz-positive minute)
ETN.milliseconds = zeros(height(ETN), 1);
ETN.bpm = zeros(height(ETN), 1);
for i = 1:height(ETN)
    train_data = ETN.train{i};
    if ~isempty(train_data)
        quality_match = [train_data.qualityclass] == ETN.quality(i);
        species_match = [train_data.spclass] == 0; % only calculate for trains from NBHF sources!
        keep_mask = quality_match & species_match;
        dummy_minute = train_data(keep_mask);
        if ~isempty(dummy_minute)
            milliseconds = arrayfun(@(x) x.time(end) - x.time(1), dummy_minute); % train duration
            ETN.milliseconds(i) = sum(milliseconds);
            ETN.bpm(i) = any(arrayfun(@(s) any(s.ici < 40000), dummy_minute)); % are there any buzzes?
        end
    end
end

% round angle
ETN.angle = round([ETN.angle]);

% change quality to names
ETN.quality = categorical(ETN.quality, [1 2 3], {'Lo', 'Mod', 'Hi'});

% change units from 0.2 microsecond steps to milliseconds
ETN.milliseconds = round(ETN.milliseconds*0.0002) ; %no decimal ms

% lost minutes
ETN.lost_minutes = double(ETN.nall > 4096) ;

% species
ETN.species = repmat("NBHF", height(ETN), 1);

% minsON **this is misleading and must come with a warning before use!
ETN.minsON = double(ETN.nall > 0 & ETN.angle < 80) ;

% delete extraneous columns
ETN.train = [] ;

% rename columns to match ETN input fields
ETN.Properties.VariableNames = {'DETECTION_DATE_TIME', 'TEMPERATURE', 'ANGLE', 'NUMBER_CLICKS_TOTAL', 'filename', 'QUALITY', 'NUMBER_CLICKS_FILTERED', 'DPM', 'MILLISECONDS', 'BPM', 'TIME_LOST_PERCENTAGE', 'SPECIES', 'RECORDED'};

end