// Five geometry rays approximate the drone's swept body without expensive volume queries.
params [["_from",[0,0,0]],["_to",[0,0,0]],["_drone",objNull],
    ["_target",objNull],["_radius",0.35]];
if (_from distance _to < 0.5) exitWith {true};
private _forward = vectorNormalized (_to vectorDiff _from);
private _right = vectorNormalized ([_forward select 1,-(_forward select 0),0]);
if (_right isEqualTo [0,0,0]) then {_right = [1,0,0];};
private _offsets = [[0,0,0],_right vectorMultiply _radius,
    _right vectorMultiply (-_radius),[0,0,_radius],[0,0,-_radius]];
private _clear = true;
{
    private _a = _from vectorAdd _x;
    private _b = _to vectorAdd _x;
    if (terrainIntersectASL [_a,_b] ||
        {!((lineIntersectsSurfaces [_a,_b,_drone,_target,true,1,"GEOM","NONE"]) isEqualTo [])}) exitWith {
        _clear = false;
    };
} forEach _offsets;
_clear
