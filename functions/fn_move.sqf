/*
    File: fn_move.sqf
    Author: Carl Lorenzo
    Description:
        Handles cruising, squad-following, and waypoint navigation for UAVs using pure Vanilla AI flight.
        Eliminates scripted velocity fighting, rubber-banding, and jitter.
*/

params [["_drone", objNull], ["_pos", [0,0,0]]];

if (isNull _drone || {!alive _drone}) exitWith { [0,0,0] };

private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
if (isNull _man || {!alive _man}) then {
    private _ownerVar = _drone getVariable ["ddtOwner", objNull];
    if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
        _man = _ownerVar;
    } else {
        if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
            { if (str _x == _ownerVar) exitWith { _man = _x; }; } forEach allUnits;
        };
    };
    if (isNull _man) then {
        private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
        if (!isNull _opGrp) then {
            private _aliveUnits = (units _opGrp) select { alive _x };
            if (count _aliveUnits > 0) then { _man = leader _opGrp; };
        };
    };
};

// Fallback for invalid/empty coordinates
if (_pos isEqualTo [0,0,0] || {count _pos < 2}) then {
    if (!isNull _man && {alive _man}) then {
        _pos = getPosATL _man;
    } else {
        _pos = getPosATL _drone;
    };
};

// Range guard: prevent runaway drones from staying active indefinitely
private _target = _drone getVariable ["CLDW_CurrentTarget", objNull];
private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000];
private _maxRange = _maxRangeSetting;

private _isTooFar = false;
if (!isNull _target && {alive _target}) then {
    if ((_drone distance _target) > _maxRange) then {
        _isTooFar = true;
    };
} else {
    if (!isNull _man && {(_drone distance _man) > _maxRange}) then {
        _isTooFar = true;
    };
};

if (_isTooFar) exitWith {
    if (missionNamespace getVariable ["CLDW_Setting_EnableMod", true]) then {
        if (alive _drone && !isNull _man) then {
            [_drone, getPosASLVisual _drone, _man] spawn CLDW_fnc_disengage;
        } else {
            _drone setFuel 0;
            _drone setDamage 1;
        };
    };
    _pos
};

// 1. Cruise Speed Configuration
private _cruiseSpeed = ((missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6) * 0.65; // Cruise at 65% of configured top speed

// 2. Pure Native Vanilla AI Piloting (Zero Script Fighting / Zero Jitter)
_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone setSpeedMode "FULL";
_drone forceSpeed _cruiseSpeed;

// Maintain cruising altitude smoothly
private _targetHeight = if (count _pos > 2) then { _pos select 2 } else { 35 };
if (_targetHeight < 25) then { _targetHeight = 35; };
_drone flyInHeight _targetHeight;

// 3. Update Waypoints with Rate-Limiting
private _lastMovePos = _drone getVariable ["CLDW_LastMoveCmdPos", [0,0,0]];
private _lastMoveTime = _drone getVariable ["CLDW_LastMoveCmdTime", 0];

if ((_pos distance _lastMovePos > 5) || (time - _lastMoveTime > 1.5)) then {
    _drone setVariable ["CLDW_LastMoveCmdPos", _pos];
    _drone setVariable ["CLDW_LastMoveCmdTime", time];

    private _grp = group (driver _drone);
    private _isMerged = (!isNull _man && {group _man == _grp});

    if (!_isMerged && {!isNull _grp}) then {
        { deleteWaypoint _x; } forEach (waypoints _grp);
        private _wp = _grp addWaypoint [_pos, 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed "FULL";
    };

    (driver _drone) doMove _pos;
    _drone doMove _pos;
};

_pos
