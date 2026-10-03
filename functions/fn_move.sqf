/*
    File: fn_move.sqf
    Author: Carl Lorenzo
    Description:
        Handles cruising, squad-following, and waypoint navigation for UAVs using pure Vanilla AI flight.
        Eliminates scripted velocity fighting, rubber-banding, and jitter.
*/

params [["_drone", objNull], ["_pos", [0,0,0]], ["_mode", "MOVE"]];

if (isNull _drone || {!alive _drone}) exitWith { [0,0,0] };
if (_drone getVariable ["CLDW_Orphaned",false]) exitWith {[0,0,0]};
private _assigned = _drone getVariable ["CLDW_AssignedOperator",objNull];
if (_drone getVariable ["CLDW_OperatorBound",false] &&
    {isNull _assigned || {!alive _assigned}}) exitWith {[0,0,0]};
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {[0,0,0]};
if (!local _drone) exitWith {
    if (isServer) then {_this remoteExecCall ["CLDW_fnc_move", _drone];};
    [0,0,0]
};
if (!alive driver _drone || {[_drone] call CLDW_fnc_getEWState}) exitWith {[0,0,0]};
if ([_drone] call CLDW_fnc_playerPiloting) exitWith {[0,0,0]};


private _man = if (_drone getVariable ["CLDW_OperatorBound",false]) then {_assigned}
    else {_drone getVariable ["CLDW_CurrentOperator", objNull]};
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
private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 750];
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

// 1. Cruise Speed Configuration based on Operational Role
private _role = [_drone] call CLDW_fnc_getDroneRole;

private _cruiseSpeed = switch (_role) do {
    case "DROPPER": {
        // Calm, realistic cruising speed for munition-dropping bomber drones (default 35 km/h = ~9.7 m/s)
        ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 12
    };
    case "NONCOMBAT": {
        // Calm utility/recon flight speed (approx 38 km/h = ~10.5 m/s)
        (38 / 3.6)
    };
    default { // "SUICIDE"
        // High-speed FPV cruise (65% of 150 km/h = ~97.5 km/h = 27 m/s)
        ((missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6) * 0.65
    };
};

private _speedMode = if (_role == "SUICIDE") then { "FULL" } else { "NORMAL" };

// 2. Pure Native Vanilla AI Piloting (Zero Script Fighting / Zero Jitter)
_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone setSpeedMode _speedMode;
_drone forceSpeed _cruiseSpeed;

// Maintain cruising altitude smoothly based on operational role
private _targetHeight = if (count _pos > 2 && {(_pos select 2) >= 20}) then {
    _pos select 2
} else {
    switch (_role) do {
        case "DROPPER": { 80 }; // Bombing/loitering altitude (safe standoff above small arms)
        case "NONCOMBAT": { 40 }; // Recon/utility altitude
        default { 35 }; // FPV approach vantage altitude
    };
};

if (_role == "DROPPER" && {_targetHeight < 60}) then { _targetHeight = 80; };
if (_role == "SUICIDE" && {_targetHeight < 25}) then { _targetHeight = 35; };

_drone flyInHeight _targetHeight;

// Keep idle movement under the native pilot on every FPV type.
if (_mode == "LOITER") exitWith {
    private _grp = group (driver _drone);
    if (isNull _grp) exitWith {_pos};
    _drone forceSpeed (_cruiseSpeed min 15);
    _drone setSpeedMode 'LIMITED';
    private _wp = _drone getVariable ["CLDW_LoiterWaypoint", []];
    private _lastCenter = _drone getVariable ["CLDW_LoiterCenter", [0,0,0]];
    private _radius = if (_role == "SUICIDE") then {80} else {60};
    private _angle = _drone getVariable ["CLDW_LoiterAngle", getDir _drone];
    private _leg = _drone getVariable ["CLDW_LoiterLeg", [0,0,0]];
    private _lastProgressPos = _drone getVariable ["CLDW_LoiterProgressPos", getPosATL _drone];
    private _lastProgressTime = _drone getVariable ["CLDW_LoiterProgressTime", time];
    private _lastOrder = _drone getVariable ["CLDW_LoiterOrderTime", -100];
    private _wasActive = _drone getVariable ["CLDW_LoiterActive", false];
    if (!_wasActive) then {
        _lastProgressTime = time;
        _drone setVariable ["CLDW_LoiterProgressPos", getPosATL _drone];
        _drone setVariable ["CLDW_LoiterProgressTime", time];
    };
    if (_drone distance2D _lastProgressPos > 5) then {
        _lastProgressTime = time;
        _drone setVariable ["CLDW_LoiterProgressPos", getPosATL _drone];
        _drone setVariable ["CLDW_LoiterProgressTime", time];
    };
    private _stalled = time - _lastProgressTime > 6;
    private _newLeg = !_wasActive ||
        {_leg isEqualTo [0,0,0]} || {_drone distance2D _leg < 25} || {_pos distance2D _lastCenter > 20};
    if (_newLeg) then {
        if (_wasActive) then {_angle = (_angle + 90) mod 360;};
        _leg = _pos vectorAdd [(sin _angle) * _radius, (cos _angle) * _radius, 0];
        _drone setVariable ["CLDW_LoiterAngle", _angle];
        _drone setVariable ["CLDW_LoiterLeg", _leg];
        _drone setVariable ["CLDW_LoiterCenter", _pos];
    };
    if (!isNull _man && {group _man == _grp}) exitWith {
        // A recovered drone can share the infantry group. Use a pilot order
        // without replacing that squad's waypoint list.
        if (_newLeg || {_stalled && {time - _lastOrder > 4}}) then {
            (driver _drone) doMove _leg;
            _drone setVariable ["CLDW_LoiterOrderTime",time];
        };
        _drone setVariable ["CLDW_LoiterActive",true];
        _pos
    };
    private _validWaypoint = count _wp > 0 && {(_wp select 0) == _grp} && {waypointType _wp == "MOVE"};
    if (!_validWaypoint) then {
        {deleteWaypoint _x} forEach (waypoints _grp);
        _wp = _grp addWaypoint [_leg, 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed 'LIMITED';
        _drone setVariable ["CLDW_LoiterWaypoint", _wp];
    } else {
        if (_newLeg) then {_wp setWaypointPosition [_leg, 0];};
    };
    _drone setVariable ["CLDW_LoiterActive", true];
    if (_newLeg || {!_validWaypoint} || {_stalled && {time - _lastOrder > 4}}) then {
        (driver _drone) doMove _leg;
        _drone doMove _leg;
        _drone setVariable ["CLDW_LoiterOrderTime", time];
    };
    _pos
};

private _idleHandle = _drone getVariable ["CLDW_IdleHandle",scriptNull];
if (!scriptDone _idleHandle) then {terminate _idleHandle;};
_drone setVariable ["CLDW_IdleHandle",scriptNull];
_drone enableAI "PATH";
(driver _drone) enableAI "PATH";
_drone setVariable ["CLDW_LoiterActive", false];

// 3. Update Waypoints with Rate-Limiting
private _lastMovePos = _drone getVariable ["CLDW_LastMoveCmdPos", [0,0,0]];
private _lastMoveTime = _drone getVariable ["CLDW_LastMoveCmdTime", 0];

if ((_pos distance _lastMovePos > 5) || (time - _lastMoveTime > 4.0)) then {
    _drone setVariable ["CLDW_LastMoveCmdPos", _pos];
    _drone setVariable ["CLDW_LastMoveCmdTime", time];

    private _grp = group (driver _drone);
    private _isMerged = (!isNull _man && {group _man == _grp});

    if (!_isMerged && {!isNull _grp}) then {
        { deleteWaypoint _x; } forEach (waypoints _grp);
        private _wp = _grp addWaypoint [_pos, 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed _speedMode;
    };

    (driver _drone) doMove _pos;
    _drone doMove _pos;
};

_pos
