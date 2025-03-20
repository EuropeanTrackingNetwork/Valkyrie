function ETN = CP3read_2_etn(outputminutes)

% Takes the output from the CP3read function and turns it into the correct
% format for the ETN database

% outputminutes = the first output structure from CP3read
% the user-selected resolution of the data (minutes, hours)

% MINUTE RESOLUTION and HARBOR PORPS ONLY
% NALL IS WRONG %

arguments
    outputminutes struct
    resolution (1,:) char {mustBeMember(resolution, {'minutes','hours'})}
end

% extract data
fieldsToKeep = {'time', 'temperature', 'angle', 'nall', 'clickHi', 'clickMed', 'no_of_trains', 'train'};
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


% train duration (milliseconds)
ETN.milliseconds = zeros(height(ETN), 1) ;
for i = 1:size(ETN, 1)
    if ~isempty(ETN.train{i})
        dummy_minute = ETN.train{i} ;

        % filter out the low q trains
        dummy_minute = dummy_minute([dummy_minute.qualityclass] ~= 1);

        %calculate duration
        if ~isempty(dummy_minute)
            [dummy_minute.milliseconds] = deal(0) ;
            for j = 1:size(dummy_minute, 2)
                dummy_minute(j).milliseconds = dummy_minute(j).time(end) - dummy_minute(j).time(1) ;
            end
            ETN.milliseconds(i) = sum([dummy_minute.milliseconds]) ;
        end
    end
end
% change units from 0.2 microsecond steps to milliseconds
ETN.milliseconds = ETN.milliseconds*0.0002 ; %IS THIS RIGHT

% species
ETN.species = repmat("NBHF", height(ETN), 1);

end