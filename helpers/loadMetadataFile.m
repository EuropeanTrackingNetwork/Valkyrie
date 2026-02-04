
% Function to load a metadata file based on the selected file path.
% Reads everything as text; datetime parsing is deferred to createDateTime.


function tbl = loadMetadataFile(fullpath)

    try
        % Detect import options from file
        opts = detectImportOptions(fullpath, 'TextType', 'string');

        % Import only the first 38 cols, deleting the extra excel macro cols
        opts.SelectedVariableNames = opts.VariableNames(1:38);

        % Force all columns to be read as text (string) to avoid auto datetime creation
        opts = setvartype(opts, opts.SelectedVariableNames, 'string');

        % Read table with these options
        tbl = readtable(fullpath, opts);
    catch
        error('Unable to read the metadata file.');
    end

end
