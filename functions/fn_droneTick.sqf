// Server-dispatched, unscheduled owner tick. Flight scripts run only on this owner.
params ["_drone"];
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {};
if (isNull _drone || {!local _drone} || {!alive _drone} ||
    {_drone getVariable ["CLDW_Orphaned",false]}) exitWith {};
if ([_drone] call CLDW_fnc_watchdog) exitWith {};
if (!alive driver _drone) exitWith {};
if ((_drone getVariable ["CLDW_CollisionOwner", -1]) != clientOwner) then {
    _drone setVariable ["CLDW_CollisionOwner", clientOwner, true];
    {
        if (_x != _drone && {alive _x} && {_x getVariable ["CLDW_AI_Spawned", false]}) then {
            _drone disableCollisionWith _x;
        };
    } forEach allUnitsUAV;
};
if ([_drone] call CLDW_fnc_getEWState) exitWith {};
if ([_drone] call CLDW_fnc_playerPiloting) exitWith {};
if (!scriptDone (_drone getVariable ["CLDW_Controller", scriptNull])) exitWith {};
private _op = _drone getVariable ["CLDW_CurrentOperator", objNull];
if (_drone getVariable ["CLDW_Disengaged", false]) exitWith {
    [_drone, "RETURN", [_drone, getPosASLVisual _drone, _op]] call CLDW_fnc_startController;
};
if (time < (_drone getVariable ["CLDW_RecoveryUntil", 0])) exitWith {};
private _intent = _drone getVariable ["CLDW_ControlIntent", []];
if !(_intent isEqualTo []) then {
    private _mode = _intent param [0,""];
    private _args = _intent param [1,[]];
    private _intentTarget = _args param [1,objNull];
    if ((_mode == "GUIDE" && {
            isNull _intentTarget || {!alive _intentTarget} ||
            {!([_drone,_intentTarget] call CLDW_fnc_hasVisualTarget) &&
                {(_drone getVariable ["CLDW_LastSeenTarget",objNull]) != _intentTarget ||
                    {time - (_drone getVariable ["CLDW_LastSeenTime",-100]) > 10}}}
        }) ||
        {_mode == "RETURN" && {!(_drone getVariable ["CLDW_Disengaged",false])}} ||
        {_mode == "SEARCH" && {time >= (_drone getVariable ["CLDW_SearchUntil",0])}}) then {
        if (_mode == "SEARCH") then {_drone setVariable ["CLDW_Disengaged",true,true];};
        _intent = [];
        _drone setVariable ["CLDW_ControlIntent",[],true];
    };
};
if !(_intent isEqualTo []) exitWith {
    [_drone, _intent select 0, _intent select 1] call CLDW_fnc_startController;
};
private _role = [_drone] call CLDW_fnc_getDroneRole;
private _target = _drone getVariable ["CLDW_CurrentTarget", objNull];
if (!isNull _target && {!alive _target || {!([_drone, _target] call CLDW_fnc_isEnemy)} ||
    {!([_drone,_target] call CLDW_fnc_hasVisualTarget) &&
        {(_drone getVariable ["CLDW_LastSeenTarget",objNull]) != _target ||
            {time - (_drone getVariable ["CLDW_LastSeenTime",-100]) > 10}}}}) then {
    if (_target getVariable ["CLDW_AssignedDrone",objNull] == _drone) then {
        _target setVariable ["CLDW_AssignedDrone",objNull,true];
    };
    _target = objNull;
    _drone setVariable ["CLDW_CurrentTarget",objNull,true];
};
if (diag_tickTime >= (_drone getVariable ["CLDW_NextAcquire", 0])) then {
    _drone setVariable ["CLDW_NextAcquire", diag_tickTime + 2 + random 0.5];
    if (isNull _target && {_role != "NONCOMBAT"}) then {
        private _targets = if (_role == "SUICIDE") then {
            [_drone, missionNamespace getVariable ["CLDW_Setting_MaxRange", 750]] call CLDW_fnc_getTargetsAT
        } else {
            [_drone, missionNamespace getVariable ["CLDW_Setting_MaxRange", 750]] call CLDW_fnc_getSoftTargets
        };
        if !(_targets isEqualTo []) then {_target = _targets select 0;};
    };
};
if (!isNull _target && {_role == "SUICIDE" || {_role == "DROPPER" && {_drone getVariable ["ddtHasAmmo", true]} && {!isNil "DDT_fnc_GuideToTarget2"} && {!isNil "DDT_fnc_GuideToTarget3"}}}) exitWith {
    _drone setVariable ["CLDW_CurrentTarget", _target, true];
    _drone setVariable ["CLDW_Disengaged", false, true];
    if (_role == "SUICIDE") then {
        [_drone, _target, 0, 0.1] call CLDW_fnc_guideToTarget;
    } else {
        _drone setVariable ["ddtBusy", true, true];
        [_drone, "BOMBER", [_drone, _target]] call CLDW_fnc_startController;
    };
};
_drone setVariable ["CLDW_CurrentTarget", objNull, true];
private _alt = switch (_role) do {case "DROPPER": {80}; case "NONCOMBAT": {40}; default {35};};
private _loiterCenter = if (!isNull _op && {alive _op}) then {getPosATL _op} else {getPosATL _drone};
[_drone, _loiterCenter, "LOITER"] call CLDW_fnc_move;
if ((getPosATL _drone select 2) > _alt + 60) then {
    _drone forceSpeed -1;
    _drone flyInHeight _alt;
    private _velocity = velocity _drone;
    if ((_velocity select 2) > 2) then {_drone setVelocity [_velocity select 0, _velocity select 1, 0];};
    private _pos = if (!isNull _op && {alive _op}) then {getPosATL _op} else {getPosATL _drone};
    _pos set [2, _alt];
    (driver _drone) doMove _pos;
};
