function cleanedMeta = CleanMetadata(metadata)
%EXPORTCLEANMETADATA Create final metadata table for ETN upload

requiredCols = { ...
    'RCV_PROJECT','RECEIVER','ACTIVATION_DATE_TIME','STATION_NAME','DEPLOY_DATE_TIME', ...
    'DEPLOY_LAT','DEPLOY_LONG','VALID_DATA_UNTIL_DATE_TIME','RECOVER_DATE_TIME', ...
    'ACOUSTIC_RELEASE_NUMBER','SAMPLE_RATE','HYDROPHONE_CABLE_LENGTH','MOORING_TYPE', ...
    'AMPLIFIER_SENSIVITY','HYDROPHONE_SENSIVITY','RECORDING_NAME','BATTERY_END_DATE', ...
    'DOWNLOAD_DATE_TIME','COMMENTS','ADDITIONAL_CLASSIFIER','SPECIES_PREFERENCES'};

% Create export table with required columns
exportTable = table();
for i = 1:numel(requiredCols)
    colName = requiredCols{i};
    if ismember(colName, metadata.Properties.VariableNames)
        exportTable.(colName) = metadata.(colName);
    else
        exportTable.(colName) = repmat({''}, height(metadata), 1); % empty if missing
    end
end

cleanedMeta = exportTable; % Assign the export table to the cleaned metadata
