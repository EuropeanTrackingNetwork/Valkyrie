% Function to load a metadata file based on the selected file path. 
% Will give an error message if the metadata file can't be read

function tbl = loadMetadataFile(fullpath)
    try
        tbl = readtable(fullpath, 'TextType', 'string');
    catch
        error('Unable to read the metadata file.');
    end
end
