
function msg = messages(key, varargin)
%MESSAGES Centralized message strings for VALKYRIE app
%   Usage: msg = messages('key', optional_args)

    switch key
        case 'importStart'
            msg = 'Importing data...';
        case 'readingFile'
            msg = sprintf('Reading file %d of %d...', varargin{:});
        case 'fileImported'
            msg = sprintf('%s file being imported.', varargin{1});
        case 'fileFormatted'
            msg = sprintf('Formatting %s file.', varargin{1});
        case 'fileError'
            msg = sprintf('Error processing file %s: %s', varargin{:});
        case 'metadataError'
            msg = 'Metadata Error: Please check the uploaded CSV file.';
        case 'uploadComplete'
            msg = 'Upload process completed.';
        case 'confirmMetadata'
            msg = sprintf(['Do you want to confirm the metadata?', ...
                          'The deployment counts %d days.', ...
                          'The recording counts %d days.'], varargin{:});
        otherwise
            msg = 'Unknown message key';
    end
end
