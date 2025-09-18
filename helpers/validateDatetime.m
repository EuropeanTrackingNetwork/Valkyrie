function [errorMsg, formattedDate] = validateDatetime(inputStr,minDate,dtFormats)
%======================================
% Function to validate datetime format
%======================================
% OBS: the datetime format requested by ETN is ISO8601
% (yyyy-MM-ddTHH:mm:ssZ)

% Prepare strings 
    errorMsg = '';
    formattedDate = ''; 
            
    % Specify common format for datetime that might have been used
    commonFormats = dtFormats;

 % test the datetime in the metadata against each of the common types of
 % format
    for i = 1:numel(commonFormats)
        try
            % Try to use the datetime function directly
            dt = datetime(inputStr, 'InputFormat', commonFormats{i}, 'TimeZone', 'UTC');

            % check if the datetime in metadata occurs before the minimum
            % expected date
            if dt < minDate
                errorMsg = [errorMsg," Check that date is added correctly."];
            end
            
            % OBS: have silenced this as users will often set a system to
            % start at midnight
            % If all times are equal to zero throw an error
            % if hour(dt) == 0 && minute(dt) == 0 && second(dt) == 0
            %     errorMsg = [errorMsg," Check that the time is added correctly."];
            % end

            formattedDate = dt; % save formatted date 
            return; % will return as soon at the correct format has been found - without an error message generated
        catch
            % try next format if the correct hasn't been found
        end
    end

    if isempty(formattedDate)
        formattedDate = NaT;
    end
    % If none of the formats worked
    errorMsg = [errorMsg,"- Invalid datetime format. Please use format: yyyy-MM-dd HH:mm:ss."];

end
