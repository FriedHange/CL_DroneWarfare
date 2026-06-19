params [["_drone", objNull], ["_pos", [0,0,0]]];

if (isNull _drone) exitWith { [0,0,0] };

// Check if the target is too far (teleport guard)
private _maxRange = (missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500]) + 300; 
private _target = _drone getVariable ["CLDW_CurrentTarget", objNull];

private _isTooFar = false;
if (!isNull _target) then {
    if ((_drone distance _target) > _maxRange) then {
        _isTooFar = true;
    };
} else {
    if ((_drone distance _pos) > _maxRange) then {
        _isTooFar = true;
    };
};

if (_isTooFar) exitWith {
    if (missionNamespace getVariable ["CLDW_Setting_EnableMod", true]) then {
        private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
        if (alive _drone && !isNull _man) then {
            // Spawn disengage logic, using current drone position as last seen target position
            [_drone, getPosASLVisual _drone, _man] spawn CLDW_fnc_disengage;
        } else {
            _drone setFuel 0;
            _drone call DB_fnc_fpv_onDestroy;
        };
    };
    _pos
};

// Standard move behavior from Drongos Drone Tweaks
private _grp = group _drone;
private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
private _isMerged = (!isNull _man && {group _man == _grp});

if (!_isMerged) then {
    {deleteWaypoint _x} forEach (wayPoints _grp);
    _grp addWaypoint [_pos, 0];
    {_x setWaypointType "MOVE"} forEach (wayPoints _grp);
};
_drone doMove _pos;
_drone setSpeedMode "FULL";
_pos
