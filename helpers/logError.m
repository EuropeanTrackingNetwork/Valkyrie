% helpers/logError.m
function logError(logFile, ME, context)
    if isempty(logFile)
        warning('No log file defined.');
        return;
    end

    fid = fopen(logFile, 'a');
    if fid == -1
        warning('Could not open log file for writing.');
        return;
    end

    fprintf(fid, '--- ERROR at %s ---\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Context: %s\n', context);
    fprintf(fid, 'Message: %s\n', ME.message);
    fprintf(fid, 'Identifier: %s\n', ME.identifier);
    fprintf(fid, 'Stack trace:\n');
    for k = 1:length(ME.stack)
        fprintf(fid, '   > %s (line %d)\n', ME.stack(k).name, ME.stack(k).line);
    end
    fprintf(fid, '\n');
    fclose(fid);
end
