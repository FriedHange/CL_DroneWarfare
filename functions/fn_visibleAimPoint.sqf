// Return a genuinely visible body point, or [] when cover hides every sample.
params [["_observer",objNull],["_target",objNull]];
if (isNull _observer || {isNull _target} || {!alive _target}) exitWith {[]};
private _start = eyePos _observer;
if (_start isEqualTo [0,0,0]) then {_start = (getPosASLVisual _observer) vectorAdd [0,0,0.4];};
private _points = if (_target isKindOf "CAManBase") then {
    [eyePos _target,
        AGLToASL (_target modelToWorldVisual [0,0,1.25]),
        AGLToASL (_target modelToWorldVisual [0,0,0.75])]
} else {
    [(getPosASLVisual _target) vectorAdd [0,0,1]]
};
private _answer = [];
{
    if !(_x isEqualTo [0,0,0]) then {
        if (!terrainIntersectASL [_start,_x] &&
            {(lineIntersectsSurfaces [_start,_x,_observer,_target,true,1,"VIEW","GEOM"]) isEqualTo []} &&
            {[_observer,"VIEW",_target] checkVisibility [_start,_x] >= (if (_target isKindOf "CAManBase") then {0.2} else {0.1})}) exitWith {
            _answer = _x;
        };
    };
} forEach _points;
_answer
