/*
    File: fn_disengage.sqf
    Author: Carl Lorenzo
    Description:
        Guarantees reliable, uninterrupted return flight for disengaging drones back to their squad/operator.
*/

params [["_drone", objNull], ["_lastSeenPos", [0,0,0]], ["_man", objNull]];

if (isNull _drone || {!alive _drone}) exitWith {};
private _assigned = _drone getVariable ["CLDW_AssignedOperator",objNull];
if (_drone getVariable ["CLDW_Orphaned",false] ||
    {_drone getVariable ["CLDW_OperatorBound",false] && {isNull _assigned || {!alive _assigned}}}) exitWith {};
if (_drone getVariable ["CLDW_OperatorBound",false]) then {_man = _assigned;};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};

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
if (isNull _grp || {!isNull _opGrp && {_grp == _opGrp} &&
    {!(_drone getVariable ["CLDW_RecoveryJoined",false])}}) then {
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
private _lowerType = toLower (typeOf _drone);
private _scriptedReturn = (_lowerType find "kvn" > -1) || {_lowerType find "uafpv" > -1};
_drone setVariable ["CLDW_ReturnFallback",false];
private _lastProgressPos = getPosASLVisual _drone;
private _lastProgressTime = time;
private _returnBuilding = nearestBuilding (ASLToAGL _lastSeenPos);
private _returnRoofASL = -1e9;
private _returnBuildingRadius = 0;
if (!isNull _returnBuilding) then {
    private _box = boundingBoxReal _returnBuilding;
    if (count _box >= 2) then {
        private _hi = _box select 1;
        private _lo = _box select 0;
        _returnRoofASL = (AGLToASL (_returnBuilding modelToWorld [0,0,_hi select 2])) select 2;
        private _extentX = (abs (_lo select 0)) max (abs (_hi select 0));
        private _extentY = (abs (_lo select 1)) max (abs (_hi select 1));
        _returnBuildingRadius = sqrt (_extentX * _extentX + _extentY * _extentY) + 12;
    };
};
if (_scriptedReturn) then {
    (driver _drone) disableAI "PATH";
    _drone disableAI "PATH";
    _drone forceSpeed -1;
};

private _timeout = time + (60 max (((_drone distance2D _man) / (_cruiseSpeed max 1)) * 2 + 15));

while {alive _drone && {!isNull _drone} && {alive _man} && {!isNull _man} && {time < _timeout}} do {
    if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
    // Check if player took manual control
    if ([_drone] call CLDW_fnc_playerPiloting) exitWith {
        _drone setVariable ["CLDW_Disengaged", false, true];
    };

    private _dronePos = getPosASLVisual _drone;
    private _manPosASL = getPosASLVisual _man;
    private _distToMan = _dronePos distance2D _manPosASL;
    if (_dronePos distance2D _lastProgressPos >= 5) then {
        _lastProgressPos = _dronePos;
        _lastProgressTime = time;
    };
    if (!_scriptedReturn && {time - _lastProgressTime >= 6}) then {
        _scriptedReturn = true;
        _drone setVariable ["CLDW_ReturnFallback",true];
        (driver _drone) disableAI "PATH";
        _drone disableAI "PATH";
        _drone forceSpeed -1;
        diag_log format ["CLDW [ReturnFallback]: %1 ignored native return orders; continuing physical flight.",typeOf _drone];
    };

    // Reached squad formation zone (< 25m)
    if (_distToMan <= 25) exitWith {};

    if (_scriptedReturn) then {
        private _terrain = getTerrainHeightASL _dronePos;
        private _goalHeight = ((_manPosASL select 2) + _cruiseAlt) max (_terrain + 15);
        private _ridge = [_dronePos,_manPosASL,_cruiseSpeed,12] call CLDW_fnc_terrainLookahead;
        _goalHeight = _goalHeight max (_ridge select 0);
        if (_returnRoofASL > -1e8 && {_drone distance2D _returnBuilding < _returnBuildingRadius}) then {
            _goalHeight = _goalHeight max (_returnRoofASL + 5);
        };
        private _climbing = false;
        private _goal = [_manPosASL select 0,_manPosASL select 1,_goalHeight];
        _drone setVariable ["CLDW_ProgressGoalASL",_goal];
        private _horizontal = vectorNormalized [(_manPosASL select 0) - (_dronePos select 0),
            (_manPosASL select 1) - (_dronePos select 1),0];
        if !([_dronePos,_dronePos vectorAdd (_horizontal vectorMultiply 4),
            _drone,objNull,0.5] call CLDW_fnc_clearFlightPath) then {
            _horizontal = [0,0,0];
            _climbing = true;
            _goalHeight = (_dronePos select 2) + 8;
            _drone setVariable ["CLDW_ProgressGoalASL",[_dronePos select 0,_dronePos select 1,_goalHeight]];
        };
        private _speedForRidge = _cruiseSpeed;
        private _ridgeClimb = (_ridge select 0) - (_dronePos select 2);
        if (_ridgeClimb > 1) then {
            _speedForRidge = _speedForRidge min ((((_ridge select 1) - 4) max 2) * 4 / _ridgeClimb) max 2.5;
        };
        private _verticalDemand = ((_goalHeight - (_dronePos select 2)) * 0.6) min 4 max -4;
        private _verticalNow = (velocity _drone) select 2;
        private _vertical = ((_verticalDemand min (_verticalNow + 0.6)) max
            (_verticalNow - 0.6)) min 4 max -4;
        _drone setVariable ["CLDW_ReturnCommandedUp",_vertical];
        private _velocity = [(_horizontal select 0) * _speedForRidge,(_horizontal select 1) * _speedForRidge,_vertical];
        private _direction = vectorNormalized _velocity;
        if (_climbing) then {
            _direction = vectorDirVisual _drone;
            _direction set [2,0];
            _direction = vectorNormalized _direction;
            if (_direction isEqualTo [0,0,0]) then {_direction = [0,1,0];};
        };
        private _right = vectorNormalized (_direction vectorCrossProduct [0,0,1]);
        if (_right isEqualTo [0,0,0]) then {_right = [1,0,0];};
        private _up = vectorNormalized (_right vectorCrossProduct _direction);
        _drone setVectorDirAndUp [_direction,_up];
        _drone setVelocity _velocity;
        sleep 0.1;
    } else {
    _drone setVariable ["CLDW_ProgressGoalASL",[_manPosASL select 0,_manPosASL select 1,
        (_manPosASL select 2) + _cruiseAlt]];

    // Altitude guard: flyInHeight is only a floor and the low forceSpeed governor can make the
    // vanilla AI pilot pitch up and climb during the return flight; pull the drone back down
    // if it drifts too far above its cruise altitude. forceSpeed is never re-asserted inside
    // this loop, so a single correction persists for the whole return flight.
    if (((getPosATL _drone) select 2) > (_cruiseAlt + 60)) then {
        _drone forceSpeed -1;
        _drone flyInHeight _cruiseAlt;
        private _vel = velocity _drone;
        if ((_vel select 2) > 2) then {
            _drone setVelocity [_vel select 0, _vel select 1, (_vel select 2) * 0.2];
        };
        private _descentPos = getPosATL _man;
        _descentPos set [2, _cruiseAlt];
        (driver _drone) doMove _descentPos;
        _drone doMove _descentPos;
    };

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
};

if (_scriptedReturn && {!isNull _drone} && {local _drone}) then {
    (driver _drone) enableAI "PATH";
    _drone enableAI "PATH";
};
if (!isNull _drone) then {_drone setVariable ["CLDW_ReturnFallback",false];};
if (!isNull _drone) then {_drone setVariable ["CLDW_ProgressGoalASL",[]];};
if (!alive _drone || isNull _drone) exitWith {};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
if (_drone distance2D _man > 35) exitWith {
    diag_log format ["CLDW [Disengage]: '%1' still %2m from squad; retrying return.", typeOf _drone, round (_drone distance2D _man)];
    // Keep CLDW_Disengaged true; the next owner tick retries the return.
};

// Successfully back with the squad
diag_log format ["CLDW [Disengage]: '%1' returned to squad formation near '%2'.", typeOf _drone, if (!isNull _man) then { name _man } else { "unknown" }];
_drone setVariable ["CLDW_Disengaged", false, true];
_drone setVariable ["CLDW_CurrentTarget", objNull, true];
_drone setVariable ["ddtOwner", _man, true];

_drone setVariable ["CLDW_CurrentOperator", _man, true];
if (_drone getVariable ["CLDW_RecoveryJoined",false]) then {
    if (isServer) then {[_drone,true] call CLDW_fnc_rejoinSquad;}
    else {[_drone,true] remoteExecCall ["CLDW_fnc_rejoinSquad",2];};
};

// Settle into formation hover above squad
_drone flyInHeight _cruiseAlt;
_drone setSpeedMode _speedMode;
_drone forceSpeed _cruiseSpeed;
[_drone, getPosATL _man, "LOITER"] call CLDW_fnc_move;
