
% Function to load a metadata file based on the selected file path.
% Reads everything as text; datetime parsing is deferred to validateDatetime.


function tbl = loadMetadataFile(fullpath)

    try
        % Detect import options from file
        opts = detectImportOptions(fullpath, 'TextType', 'string');

        % Force ALL columns to be read as text (string) to avoid auto datetime creation
        % You can restrict this to specific columns if you prefer.
        opts = setvartype(opts, opts.VariableNames, 'string');

        % Read table with these options
        tbl = readtable(fullpath, opts);
    catch
        error('Unable to read the metadata file.');
    end

end
