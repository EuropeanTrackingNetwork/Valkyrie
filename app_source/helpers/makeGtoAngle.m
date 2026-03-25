function GtoAngle = makeGtoAngle()
% Because the byte go from 0-255 and that 1 radian angle is equal to 57.3
% it is faster to do a lookup array that calculate the values (this is
% internally in the POD how it is coded). So to extract the correct angle
% we need to do something similar, where we first create the lookup array.
% The POD code:
% GtoAngle[0]:= 0;
% for count:= 1 to 254 do GtoAngle[count]:= 180 - Round(arccos(count/128 - 1) * 57.3);
% GtoAngle[255]:= 180;

% Create lookup table equivalent to developer's Pascal code
roundDelphi = @(x) floor(x + 0.5) - mod(floor(x + 0.5),2) .* (mod(x,1)==0.5);

GtoAngle = zeros(256,1);


counts = 1:256;
GtoAngle(1:256) = 180 - roundDelphi( acos( counts /128 - 1) * 57.3 );

% OBS: it only gives the correct values for the lookup if first the table
% is created and then 0 and 180 is enforced.

GtoAngle(1)   = 0;
GtoAngle(256) = 180;
end