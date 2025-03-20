%% Setting up and testing upload of data to SQL server

% Define the DSN-less connection string
connStr = 'Driver={SQL Server};Server=D54296\SQLEXPRESS;Database=mydatabase;Trusted_Connection=yes;';

% Establish the database connection using the DSN-less connection string
conn = odbc(connStr);


% Check the connection
if isopen(conn)
    disp('Connection successful');
else
    disp('Connection failed');
    disp(conn.Message);
end

%%
[files, path] = uigetfile('*.*', 'MultiSelect','on') ;
SelectedFilePath = fullfile(path, files);

%%
i = 1 ;
fileID = i;
fileName = files{i};
fileName = strrep(fileName, ' ', ''); % remove spaces from file name
fileName = fileName(1:min(50, length(fileName)));

%%
fileData = uint8(SelectedFilePath{i});
hexFileData = reshape(dec2hex(fileData)', 1, []);

%%
fpodfile = SelectedFilePath{i};
[poddata] = importpoddata(fpodfile, 'detstart', 0, 'maxdet', 1000);

% Define your data: Example
%fileID = 9; % Example FileID
%fileName = 'test.txt'; % Example FileName
%fileData = uint8([1, 2, 3, 4, 5,6,7,8,9]); % Example FileData (binary data)

% Convert binary data to hexadecimal string for SQL insertion
fileData=getByteStreamFromArray(poddata); % convert to byte array
hexFileData = reshape(dec2hex(fileData)', 1, []);% Convert to a single row

%%
% Create the SQL query
sqlquery = sprintf('INSERT INTO Test (FileID, FileName, FileData) VALUES (%d, ''%s'', 0x%s)', fileID, fileName, hexFileData);

% Execute the SQL query
exec(conn, sqlquery);

%% Test if row was added to table in SQL

sqltest = 'SELECT * FROM Test';
test = fetch(conn, sqltest);
disp(test)

%%

% Close the database connection
close(conn);
%% Create HDF5 file

% HDF5 file name
h5FileName = 'myStructData3.h5';

data = poddata ;

% Iterate through the fields of the struct
fields = fieldnames(data);
for i = 1:numel(fields)
    fieldName = fields{i};
    fieldData = data.(fieldName);
    
    if isstruct(fieldData)
        nestedFields = fieldnames(fieldData);
        flatData = struct() ;
        for u = 1:numel(nestedFields)
            flatData.(nestedFields{u}) = cell(999, 1);
        end
        for j = 1:length(data)
            for k = 1:numel(nestedFields)
                flatData.(nestedFields{k})(j) = data(j).(fieldName).(nestedFields{k});
            end
        end
    else
        if isdatetime(fieldData)
            dateArray = [data.(fieldName)];
            dateArray = posixtime(dateArray);

            % Create the dataset in the HDF5 file
            h5create(h5FileName, '/datetime', size(dateArray));

            % Write the POSIX time data to the HDF5 file
            h5write(h5FileName, '/datetime', dateArray);
        else 
            % Determine the size of the data
            dataSize = size(fieldData);
            % Create the dataset in the HDF5 file
            h5create(h5FileName, ['/' fieldName], dataSize);
    
            % Write the data to the HDF5 file
            h5write(h5FileName, ['/' fieldName], fieldData);
        end
    end
    
end

% Display the result
disp(['Data written to ' h5FileName]);


%%
% Supported file extensions
            supportedExtensions = {'.CP1', '.CP3', '.FP1', '.FP3'};

            % Initialize file pairs
            cp1Files = {};
            cp3Files = {};
            fp1Files = {};
            fp3Files = {};

            % Check each file
            for i = 1:length(files)
                [~, name, ext] = fileparts(files{i});

                % Check if the file extension is supported
                if ~ismember(upper(ext), supportedExtensions)
                    uialert(app.UIFigure, ...
                        sprintf('Wrong file type selected - type selected: %s. The formats supported are .CP1, .CP3, .FP1, or .FP3.', ext), ...
                        'File Type Error');
                    return;
                end

                % add the file names to correct array for validation later
                switch ext
                    case '.CP1'
                        cp1Files{end+1} = name;
                    case '.CP3'
                        cp3Files{end+1} = name;
                    case '.FP1'
                        fp1Files{end+1} = name;
                    case '.FP3'
                        fp3Files{end+1} = name;
                end
            end