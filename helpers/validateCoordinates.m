function [errorMsg] = validateCoordinates(lat,lon)
%===================================================
% Fucntion to validate latitude and longitude inputs
%===================================================
    latitude = str2double(lat);
    longitude = str2double(lon);

    isValidLat = ~isnan(latitude) && latitude >= -90 && latitude <= 90;
    isValidLon = ~isnan(longitude) && longitude >= -180 && longitude <= 180;

    % Prepare string
    errorMsg = '';
    
    % If the latitude or longitude is invalid throw an error 
    if ~isValidLat && isValidLon % latitude is invalid but longitude is valid
        errorMsg = [errorMsg,"- Invalid latitude."];
    elseif ~isValidLon && isValidLat % longitude is invalid but latitude is valid
        errorMsg = [errorMsg,"- Invalid longitude."];
    elseif ~isValidLat && ~isValidLon % both latitude and longitude are invalid
        errorMsg = [errorMsg,"- Invalid latitude and longitude."];
    end
end
