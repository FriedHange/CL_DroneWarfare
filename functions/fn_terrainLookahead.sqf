// Sample a short horizontal flight corridor before committing to a low pass.
// Returns [minimum safe ASL altitude at the highest sampled ridge, ridge range].
params [["_from",[0,0,0]],["_to",[0,0,0]],["_speed",0],["_clearance",3]];
private _range = _from distance2D _to;
if (_range < 1) exitWith {[-1,_range]};
private _horizon = _range min (35 max (_speed * 2.5));
private _highest = -1e6;
private _ridgeRange = _horizon;
for "_i" from 1 to 6 do {
    private _distance = _horizon * _i / 6;
    private _factor = _distance / _range;
    private _x = (_from select 0) + ((_to select 0) - (_from select 0)) * _factor;
    private _y = (_from select 1) + ((_to select 1) - (_from select 1)) * _factor;
    private _safe = (getTerrainHeightASL [_x,_y]) + _clearance;
    if (_safe > _highest) then {
        _highest = _safe;
        _ridgeRange = _distance;
    };
};
[_highest,_ridgeRange]
