// Short, owner-local approach probe for covered infantry and last-known positions.
// Returns [reachable goal ASL, clear short final corridor] or [].
params [["_drone",objNull],["_aim",[]],["_target",objNull],["_visible",false]];
if (isNull _drone || {count _aim != 3}) exitWith {[]};
private _here = getPosASLVisual _drone;
private _distance = _here distance _aim;
if (_distance < 1) exitWith {[]};
private _ignore = if (_visible) then {_target} else {objNull};
private _finalClear = _visible && {_distance <= 90} &&
    {[_here,_aim,_drone,_ignore,0.4] call CLDW_fnc_clearFlightPath} &&
    {(lineIntersectsSurfaces [_here,_aim,_drone,_ignore,true,1,"VIEW","NONE"]) isEqualTo []};
if (_finalClear) exitWith {[_aim,true]};

private _bearing = _here getDir _aim;
private _step = (_here distance2D _aim) min 7 max 3;
private _ground = getTerrainHeightASL _here;
private _cruiseZ = (_here select 2) max (_ground + 3);
private _preferred = _drone getVariable ["CLDW_ApproachSide",0];
private _best = [];
private _bestScore = 1e9;
private _bestSide = _preferred;
{
    private _offset = _x;
    private _direction = (_bearing + _offset + 360) mod 360;
    private _xPos = (_here select 0) + (sin _direction) * _step;
    private _yPos = (_here select 1) + (cos _direction) * _step;
    private _goal = [_xPos,_yPos,_cruiseZ max ((getTerrainHeightASL [_xPos,_yPos]) + 3)];
    // VIEW keeps the drone out of tree canopies; the swept GEOM rays protect its hull.
    if ([_here,_goal,_drone,objNull,0.4] call CLDW_fnc_clearFlightPath &&
        {(lineIntersectsSurfaces [_here,_goal,_drone,objNull,true,1,"VIEW","NONE"]) isEqualTo []}) then {
        private _side = if (_offset < 0) then {-1} else {if (_offset > 0) then {1} else {0}};
        private _futureView = !terrainIntersectASL [_goal,_aim] &&
            {(lineIntersectsSurfaces [_goal,_aim,_drone,_ignore,true,1,"VIEW","NONE"]) isEqualTo []};
        private _score = (_goal distance2D _aim) + (abs _offset) * 0.045 +
            (if (_futureView) then {-12} else {0}) +
            (if (_preferred != 0 && {_side != 0} && {_side != _preferred}) then {4} else {0});
        if (_score < _bestScore) then {
            _bestScore = _score;
            _best = [_goal,false];
            if (_side != 0) then {_bestSide = _side;};
        };
    };
} forEach [0,-35,35,-70,70];
if !(_best isEqualTo []) exitWith {
    _drone setVariable ["CLDW_ApproachSide",_bestSide];
    _best
};
// A small rise can clear a low fence, but never becomes a repeated pull-up.
private _ceiling = _ground + 10;
private _up = [_here select 0,_here select 1,((_here select 2) + 2) min _ceiling];
if ((_up select 2) > ((_here select 2) + 0.5) &&
    {[_here,_up,_drone,objNull,0.4] call CLDW_fnc_clearFlightPath} &&
    {(lineIntersectsSurfaces [_here,_up,_drone,objNull,true,1,"VIEW","NONE"]) isEqualTo []}) then {
    [_up,false]
} else {[]}
