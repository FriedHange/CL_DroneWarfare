// Single owner-local controller. Remote requests are accepted only from the server.
params ["_drone", "_mode", "_args"];
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {};
if (isNull _drone || {!alive _drone} ||
    {_drone getVariable ["CLDW_Orphaned",false]}) exitWith {};
private _assigned = _drone getVariable ["CLDW_AssignedOperator",objNull];
if (_drone getVariable ["CLDW_OperatorBound",false] &&
    {isNull _assigned || {!alive _assigned}}) exitWith {};
if (!local _drone) exitWith {
    if (isServer) then {_this remoteExecCall ["CLDW_fnc_startController", _drone];};
};
if (!alive driver _drone || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
if ([_drone] call CLDW_fnc_playerPiloting) exitWith {};
if (_mode == 'GUIDE' && {_drone getVariable ['CLDW_RecoveryJoined',false]}) then {
    if (isServer) then {[_drone,true] call CLDW_fnc_rejoinSquad}
    else {[_drone,true] remoteExecCall ['CLDW_fnc_rejoinSquad',2]};
};
private _code = switch (_mode) do {
    case "GUIDE": {CLDW_fnc_guideFlight};
    case "RETURN": {CLDW_fnc_returnFlight};
    case "BOMBER": {CLDW_fnc_bomberFlight};
    case "SEARCH": {CLDW_fnc_searchFlight};
    default {{}};
};
if !(_mode in ["GUIDE", "RETURN", "BOMBER", "SEARCH"]) exitWith {};
if (_mode == "GUIDE") then {
    // Preserve the route seen at acquisition. A moving FPV can lose the window
    // ray between this call and the first scheduled guidance tick.
    private _target = _args param [1,objNull];
    if (!isNull _target) then {_drone setVariable ["CLDW_CurrentTarget",_target,true];};
    if (!isNull _target && {alive _target} &&
        {[_drone,_target] call CLDW_fnc_hasVisualTarget}) then {
        private _seenPos = if (_target isKindOf 'CAManBase') then {eyePos _target}
            else {getPosASLVisual _target};
        _drone setVariable ["CLDW_LastSeenTarget",_target];
        _drone setVariable ["CLDW_LastSeenPosASL",_seenPos];
        _drone setVariable ["CLDW_LastSeenVelocity",velocity (vehicle _target)];
        _drone setVariable ["CLDW_LastSeenTime",time];
    };
    private _plan = [];
    if (!isNull _target && {alive _target} && {_target isKindOf "CAManBase"}) then {
        private _point = [_drone,_target] call CLDW_fnc_visibleAimPoint;
        if !(_point isEqualTo []) then {
            private _candidate = [_drone,_target,_point] call CLDW_fnc_planAttack;
            if (_candidate param [3,false]) then {_plan = _candidate;};
        };
    };
    _drone setVariable ["CLDW_InitialAttackPlan",_plan];
} else {
    _drone setVariable ["CLDW_InitialAttackPlan",[]];
    _drone setVariable ["CLDW_AttackPhase",-1];
};
if (_mode != "SEARCH") then {
    _drone limitSpeed false;
    _drone setVariable ["CLDW_SearchLeg",[]];
    _drone setVariable ["CLDW_SearchFallback",false];
    _drone setVariable ["CLDW_BuildingSearch",false];
    _drone setVariable ["CLDW_InspectionBuilding",objNull];
    _drone setVariable ["CLDW_ProgressGoalASL",[]];
};
if (_mode == "RETURN") then {
    _drone setVariable ["CLDW_SearchWindowUntil",0];
    _drone setVariable ["CLDW_ApproachSide",0];
};
if (_mode in ["GUIDE", "RETURN"]) then {_drone setVariable ["CLDW_RecoveryUntil", 0];};
private _idle = _drone getVariable ["CLDW_IdleHandle",scriptNull];
if (!scriptDone _idle) then {terminate _idle;};
_drone setVariable ["CLDW_IdleHandle",scriptNull];
_drone enableAI "PATH";
(driver _drone) enableAI "PATH";
private _old = _drone getVariable ["CLDW_Controller", scriptNull];
if (!scriptDone _old) then {terminate _old;};
_drone setVariable ["CLDW_LoiterActive", false];
private _crewGroup = group driver _drone;
private _operator = _drone getVariable ["CLDW_CurrentOperator",objNull];
if (isNull _operator || {group _operator != _crewGroup}) then {
    {deleteWaypoint _x} forEach (waypoints _crewGroup);
};
private _firedEH = _drone getVariable ["CLDW_BomberFiredEH", -1];
if (_firedEH >= 0) then {
    _drone removeEventHandler ["Fired", _firedEH];
    _drone setVariable ["CLDW_BomberFiredEH", -1];
};
_drone setVariable ["CLDW_ControlIntent", [_mode, _args], true];
private _token = (_drone getVariable ["CLDW_ControllerToken", 0]) + 1;
_drone setVariable ["CLDW_ControllerToken", _token];
private _handle = [_drone, _args, _code, _mode, _token] spawn {
    params ["_drone", "_args", "_code", "_mode", "_token"];
    if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
    _args call _code;
    if (!isNull _drone && {local _drone} && {_drone getVariable ["CLDW_ControllerToken", -1] == _token}) then {
private _firedEH = _drone getVariable ["CLDW_BomberFiredEH", -1];
if (_firedEH >= 0) then {
    _drone removeEventHandler ["Fired", _firedEH];
    _drone setVariable ["CLDW_BomberFiredEH", -1];
};
        _drone setVariable ["CLDW_ControlIntent", [], true];
        if (_mode == "BOMBER") then {_drone setVariable ["ddtBusy", false, true];};
    };
};
_drone setVariable ["CLDW_Controller", _handle];
if (isNil "CLDW_controllers") then {CLDW_controllers = [];};
CLDW_controllers pushBack [_drone, _handle];
_handle
