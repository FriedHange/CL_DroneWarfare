/*
    File: fn_disengage.sqf
    Author: Carl Lorenzo
    Description:
        Guarantees reliable, uninterrupted return flight for disengaging drones back to their squad/operator.
*/

params [["_drone", objNull], ["_lastSeenPos", [0,0,0]], ["_man", objNull]];

if (isNull _drone || {!alive _drone}) exitWith {};

{
    if (_x in switchableUnits) then { removeSwitchableUnit _x; };
} forEach (crew _drone);

// Mark drone as disengaging
_drone setVariable ["CLDW_Disengaged", true, true];
_drone setVariable ["CLDW_CurrentTarget", objNull, true];
diag_log format ["CLDW [Disengage]: '%1' disengaging, returning to '%2'.", typeOf _drone, if (!isNull _man && {alive _man}) then { name _man } else { "unresolved operator" }];

// Resolve operator dynamically if dead/null
if (isNull _man || {!alive _man}) then {
    private _ownerVar = _drone getVariable ["ddtOwner", objNull];
    if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
        _man = _ownerVar;
    } else {
        if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
            { if (str _x == _ownerVar) exitWith { _man = _x; }; } forEach allUnits;
        };
    };
    if (isNull _man || {!alive _man}) then {
        private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
        if (!isNull _opGrp) then {
            private _aliveUnits = (units _opGrp) select { alive _x };
            if (count _aliveUnits > 0) then {
                _man = leader _opGrp;
                _drone setVariable ["CLDW_CurrentOperator", _man, true];
                _drone setVariable ["ddtOwner", _man, true];
                _drone setVariable ["ddtOwner", str _man, true];
            };
        };
    };
    if (isNull _man || {!alive _man}) then {
        private _droneSide = _drone getVariable ["CLDW_DroneSide", side _drone];
        private _nearUnits = (getPosATL _drone) nearEntities ["CAManBase", 1500];
        private _friendlyUnits = _nearUnits select { alive _x && {side (group _x) == _droneSide || [side (group _x), _droneSide] call BIS_fnc_areFriendly} && {!isPlayer _x} };
        if (count _friendlyUnits > 0) then {
            _man = _friendlyUnits select 0;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
            _drone setVariable ["ddtOwner", _man, true];
        };
    };
};

if (isNull _man || {!alive _man}) exitWith {
    _drone setFuel 0;
};

private _side = side _drone;
private _grp = group (driver _drone);
private _opGrp = if (!isNull _man) then { group _man } else { grpNull };
if (isNull _grp || {!isNull _opGrp && {_grp == _opGrp}}) then {
    _grp = createGroup [_side, true];
    (crew _drone) joinSilent _grp;
    _grp deleteGroupWhenEmpty true;
};

_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone doWatch objNull;
_grp setBehaviour "CARELESS";
_grp setCombatMode "BLUE";

private _role = [_drone] call CLDW_fnc_getDroneRole;

private _cruiseSpeed = switch (_role) do {
    case "DROPPER": {
        // Calm, realistic speed for munition-dropping bomber drones (default 35 km/h = ~9.7 m/s)
        ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 12
    };
    case "NONCOMBAT": {
        (38 / 3.6)
    };
    default { // "SUICIDE"
        ((missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6) * 0.65
    };
};
private _speedMode = if (_role == "SUICIDE") then { "FULL" } else { "NORMAL" };
private _cruiseAlt = switch (_role) do {
    case "DROPPER": { 80 };
    case "NONCOMBAT": { 40 };
    default { 30 };
};

_drone setSpeedMode _speedMode;
_drone forceSpeed _cruiseSpeed;
_drone flyInHeight _cruiseAlt;

private _timeout = time + 60;

while {alive _drone && {!isNull _drone} && {alive _man} && {!isNull _man} && {time < _timeout}} do {
    // Check if player took manual control
    private _controller = uavControl _drone select 0;
    if (!isNull _controller && {isPlayer _controller}) exitWith {
        _drone setVariable ["CLDW_Disengaged", false, true];
    };

    private _dronePos = getPosASLVisual _drone;
    private _manPosASL = getPosASLVisual _man;
    private _distToMan = _dronePos distance2D _manPosASL;

    // Reached squad formation zone (< 25m)
    if (_distToMan <= 25) exitWith {};

    private _curManPos2D = [getPosATL _man select 0, getPosATL _man select 1, 0];
    private _lastMovePos = _drone getVariable ["CLDW_Disengage_LastPos", [0,0,0]];
    private _lastMoveTime = _drone getVariable ["CLDW_Disengage_LastTime", 0];

    if ((_curManPos2D distance _lastMovePos > 8) || (time - _lastMoveTime > 5.0)) then {
        _drone setVariable ["CLDW_Disengage_LastPos", _curManPos2D];
        _drone setVariable ["CLDW_Disengage_LastTime", time];
        (driver _drone) doMove _curManPos2D;
        _drone doMove _curManPos2D;
    };

    sleep 2.0;
};

if (!alive _drone || isNull _drone) exitWith {};

// Successfully back with the squad
diag_log format ["CLDW [Disengage]: '%1' returned to squad formation near '%2'.", typeOf _drone, if (!isNull _man) then { name _man } else { "unknown" }];
_drone setVariable ["CLDW_Disengaged", false, true];
_drone setVariable ["CLDW_CurrentTarget", objNull, true];
_drone setVariable ["ddtOwner", _man, true];
_drone setVariable ["ddtOwner", str _man, true];
_drone setVariable ["CLDW_CurrentOperator", _man, true];

// Settle into formation hover above squad
_drone flyInHeight _cruiseAlt;
_drone setSpeedMode _speedMode;
_drone forceSpeed _cruiseSpeed;
(driver _drone) doMove (getPosATL _man);

switch (_role) do {
    case "SUICIDE": {
        // Immediate target acquisition on squad rejoin for suicide drones; loiter in formation if clear
        private _targets = [_drone, missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000]] call CLDW_fnc_getTargetsAT;
        if (count _targets > 0) then {
            private _target = _targets select 0;
            private _speed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6;
            _drone setVariable ["CLDW_Disengaged", false, true];
            _drone setVariable ["CLDW_CurrentTarget", _target, true];
            [_drone, _target, _speed, 0.1] spawn CLDW_fnc_guideToTarget;
        } else {
            [_drone, getPosATL _man] call CLDW_fnc_move;
        };
    };
    case "DROPPER": {
        // Dropper drones return to high-altitude bomber routine or formation
        _drone setVariable ["CLDW_Disengaged", false, true];
        _drone flyInHeight 80;
        if (fileExists "DrongosDroneTweaks\Scripts\Drones\AI_Bomber.sqf") then {
            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Bomber.sqf";
        } else {
            [_drone, getPosATL _man] call CLDW_fnc_move;
        };
    };
    default { // "NONCOMBAT" (AL-6 Pelican, AR-2 Darter, Medical, Recon)
        // Non-combat drones return to operator or recon at safe altitude - NEVER attack or dive
        _drone setVariable ["CLDW_Disengaged", false, true];
        _drone flyInHeight 40;
        if (fileExists "DrongosDroneTweaks\Scripts\Drones\AI_Recon.sqf") then {
            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Recon.sqf";
        } else {
            [_drone, getPosATL _man] call CLDW_fnc_move;
        };
    };
};
