function [errorMsg, formattedDate] = validateDatetime(inputStr,minDate)
%======================================
% Function to validate datetime format
%======================================
% OBS: the datetime format requested by ETN is ISO8601
% (yyyy-MM-ddTHH:mm:ssZ)
    % minDate = datetime(1990, 1, 1,'TimeZone', 'UTC');
    errorMsg = '';
    formattedDate = ''; 
            
    commonFormats = {
        'yyyy-MM-dd HH:mm:ss','yyyy-MM-dd''T''HH:mm:ss''Z''','dd-MM-yyyy HH:mm:ss', ...
        'MM/dd/yyyy HH:mm:ss', 'dd/MM/yyyy HH:mm:ss', 'yyyy/MM/dd HH:mm:ss', ...
        'yyyy-MM-dd''T''HH:mm:ss'
    };

 
    for i = 1:length(commonFormats)
        try
            dt = datetime(inputStr, 'InputFormat', commonFormats{i}, 'TimeZone', 'UTC');

            if dt < minDate
                errorMsg = [errorMsg,"- Check that date is added correctly."];
            end
            
            if hour(dt) == 0 && minute(dt) == 0 && second(dt) == 0
                errorMsg = [errorMsg,"- Check that the time is added correctly."];
            end

            formattedDate = dt;
            return; % will return as soon at the correct format has been found - without an error message generated
        catch
            % try next format
        end
    end
    % If none of the formats worked
    errorMsg = [errorMsg,"- Invalid datetime format. Please use format: yyyy-MM-dd HH:mm:ss."];

end
