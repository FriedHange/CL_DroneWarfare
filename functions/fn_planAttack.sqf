// Find a physical, low entry corridor for covered infantry. Returns
// [outer approach ASL, opening ASL, target aim ASL, indoor] or [].
params [["_drone",objNull],["_target",objNull],["_aim",[]]];
if (isNull _drone || {isNull _target} || {count _aim != 3}) exitWith {[]};
private _box = boundingBoxReal _drone;
private _extent = 0.35;
if (count _box == 2) then {
    private _lo = _box select 0;
    private _hi = _box select 1;
    _extent = (((abs (_hi select 0)) max (abs (_lo select 0))) max
        ((abs (_hi select 2)) max (abs (_lo select 2)))) max 0.25 min 0.8;
};
private _now = getPosASLVisual _drone;
private _houses = nearestObjects [ASLToAGL _aim,["House","Building"],50,true];
_houses append (nearestTerrainObjects [ASLToAGL _aim,["HOUSE","BUILDING","BUNKER","FORTRESS"],50,false,true]);
private _building = objNull;
if (_target isKindOf "CAManBase") then {
    {
        if (!isNull _x && {count (boundingBoxReal _x) == 2}) then {
            private _bounds = boundingBoxReal _x;
            private _localAim = _x worldToModelVisual (ASLToAGL _aim);
            private _low = _bounds select 0;
            private _high = _bounds select 1;
            if ((_localAim select 0) >= (_low select 0) - 2 &&
                {(_localAim select 0) <= (_high select 0) + 2} &&
                {(_localAim select 1) >= (_low select 1) - 2} &&
                {(_localAim select 1) <= (_high select 1) + 2} &&
                {(_localAim select 2) >= (_low select 2) - 1} &&
                {(_localAim select 2) <= (_high select 2) + 1}) exitWith {
                _building = _x;
            };
        };
    } forEach _houses;
};
private _indoor = !isNull _building || {insideBuilding _target > 0.25};
if (!_indoor && {_target isKindOf "CAManBase"}) then {
    private _house = nearestBuilding _target;
    if (!isNull _house && {_target distance _house < 80}) then {
        _indoor = ((_house buildingPos -1) findIf {
            _x distance (getPosATL _target) < 2.5
        }) >= 0;
        if (_indoor) then {_building = _house;};
    };
};
if (!_indoor && {_now distance _aim < 70} &&
    {[_now,_aim,_drone,_target,_extent] call CLDW_fnc_clearFlightPath}) exitWith {
    [_now,_now,_aim,false]
};
if (!_indoor) exitWith {[]};

// Sample a low ring around the target, including structures with no buildingPos.
// A visible target through a window is not enough: the swept hull must fit.
private _base = _aim getDir _now;
private _best = [];
private _bestScore = 1e10;
private _routeStats = [0,0,0];
{
    private _radius = _x;
    {
        private _bearing = (_base + _x + 360) mod 360;
        {
            private _height = (_aim select 2) + _x;
            private _stage = [(_aim select 0) + (sin _bearing) * _radius,
                (_aim select 1) + (cos _bearing) * _radius,_height];
            private _outside = true;
            if (!isNull _building) then {
                private _localStage = _building worldToModelVisual (ASLToAGL _stage);
                private _bounds = boundingBoxReal _building;
                private _lo = _bounds select 0;
                private _hi = _bounds select 1;
                _outside = (_localStage select 0) < (_lo select 0) - _extent ||
                    {(_localStage select 0) > (_hi select 0) + _extent} ||
                    {(_localStage select 1) < (_lo select 1) - _extent} ||
                    {(_localStage select 1) > (_hi select 1) + _extent};
            };
            if (_outside) then {_routeStats set [0,(_routeStats select 0) + 1];};
            if (_outside && {(_stage select 2) > (getTerrainHeightASL _stage) + _extent} &&
                {[_stage,_aim,_drone,_target,_extent] call CLDW_fnc_clearFlightPath}) then {
                _routeStats set [1,(_routeStats select 1) + 1];
                private _outer = _stage;
                private _approachClear = [_now,_stage,_drone,objNull,_extent] call CLDW_fnc_clearFlightPath;
                if (!_approachClear) then {
                    // Travel horizontally to the exterior before descending.
                    // Reuse the current height; a fixed pull-up above the roof
                    // makes an otherwise reachable opening look like a dive.
                    private _level = +_stage;
                    _level set [2,(_now select 2) max (_stage select 2)];
                    if ([_now,_level,_drone,objNull,_extent] call CLDW_fnc_clearFlightPath &&
                        {[_level,_stage,_drone,objNull,_extent] call CLDW_fnc_clearFlightPath}) then {
                        _outer = _level;
                        _approachClear = true;
                    };
                };
                if (!_approachClear) then {
                    // Approach the same opening from either side of the building.
                    private _side = [_radius * 0.55 min 16,-(_radius * 0.55 min 16)];
                    {
                        private _tangent = (_bearing + (if (_x > 0) then {90} else {-90}) + 360) mod 360;
                        private _candidate = _stage vectorAdd [(sin _tangent) * abs _x,
                            (cos _tangent) * abs _x,0];
                        if ([_now,_candidate,_drone,objNull,_extent] call CLDW_fnc_clearFlightPath &&
                            {[_candidate,_stage,_drone,objNull,_extent] call CLDW_fnc_clearFlightPath}) exitWith {
                            _outer = _candidate;
                            _approachClear = true;
                        };
                    } forEach _side;
                };
                if (_approachClear) then {
                    _routeStats set [2,(_routeStats select 2) + 1];
                    private _score = (_now distance _outer) + (_outer distance _stage) +
                        (_stage distance _aim) + abs ((_aim select 2) - _height) * 3;
                    if (_score < _bestScore) then {
                        _bestScore = _score;
                        _best = [_outer,_stage,_aim,true];
                    };
                };
            };
        } forEach [0,1.2,-0.6];
    } forEach [0,30,-30,60,-60,90,-90,120,-120,150,-150,180];
    // The nearest ring with a valid corridor is preferable; avoid probing
    // distant rings for every drone in a large battle.
    if !(_best isEqualTo []) exitWith {};
} forEach [8,16,28,40];
if (missionNamespace getVariable ["CLDW_DebugRoutes",false]) then {
    diag_log format ["CLDW [RouteProbe]: building=%1 aim=%2 extent=%3 clearCandidates=%4 best=%5",
        typeOf _building,_aim,_extent,_routeStats,_best];
};
_best
