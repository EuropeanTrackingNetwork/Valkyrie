function [type] = species2flag(speciestring)
%SPECIES2FLAG Converts a species to a numeric flag
%   Detailed explanation goes here
type=-1;
switch (speciestring)
    case 'NBHF'
        type = 1;
    case 'DOLPHIN'
        type = 2;
    case 'SONAR'
        type=3;
end
    
end

