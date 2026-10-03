// Owner-local progress guard for CLDW-deployed FPV drones. Repairs the same
// hull and crew instead of consuming squad stock when flight gets stuck.
params [["_drone",objNull]];
if (isNull _drone || {!local _drone} || {!alive _drone} ||
    {!(_drone getVariable ["CLDW_AI_Spawned",false])} ||
    {_drone getVariable ["CLDW_Orphaned",false]}) exitWith {false};

if ([_drone] call CLDW_fnc_playerPiloting) exitWith {
    _drone setVariable ["CLDW_StallState",[]];
    _drone setVariable ["CLDW_PilotLostAt",-1];
    false
};

private _now = diag_tickTime;
if ([_drone] call CLDW_fnc_getEWState ||
    {_drone getVariable ["CLDW_EWReturnPending",false]}) exitWith {
    _drone setVariable ["CLDW_StallState",[]];
    _drone setVariable ["CLDW_PilotLostAt",-1];
    false
};

private _repair = {
    params ["_reason"];
    if (isNull _drone || {!local _drone}) exitWith {true};
    diag_log format ["CLDW [Watchdog]: Replacing %1 pilot in place (%2); retaining drone and stock.",typeOf _drone,_reason];
    private _idle = _drone getVariable ["CLDW_IdleHandle",scriptNull];
    if (!scriptDone _idle) then {terminate _idle;};
    _drone setVariable ["CLDW_IdleHandle",scriptNull];
    private _flight = _drone getVariable ["CLDW_Controller",scriptNull];
    if (!scriptDone _flight) then {terminate _flight;};
    _drone setVariable ["CLDW_Controller",scriptNull];
    private _target = _drone getVariable ["CLDW_CurrentTarget",objNull];
    if (!isNull _target && {_target getVariable ["CLDW_AssignedDrone",objNull] == _drone}) then {
        _target setVariable ["CLDW_AssignedDrone",objNull,true];
    };
    _drone setVariable ["CLDW_CurrentTarget",objNull,true];
    _drone setVariable ["CLDW_ControlIntent",[],true];
    _drone setVariable ["CLDW_SearchUntil",0,true];
    _drone setVariable ["CLDW_SearchWindowUntil",0];
    _drone setVariable ["CLDW_SearchFallback",false];
    _drone setVariable ["CLDW_Disengaged",false,true];
    _drone setVariable ["CLDW_LoiterActive",false];
    _drone setVariable ["CLDW_RecoveryUntil",0];
    _drone setVariable ["CLDW_RecoveryJoined",false,true];
    private _op = _drone getVariable ["CLDW_CurrentOperator",objNull];
    private _opGroup = _drone getVariable ["CLDW_OperatorGroup",grpNull];
    if (isNull _op || {!alive _op}) then {
        if (!isNull _opGroup) then {
            private _available = (units _opGroup) select {alive _x && {!(_x getVariable ["CLDW_IsDroneCrew",false])}};
            if !(_available isEqualTo []) then {_op = _available select 0;};
        };
    };
    {_drone deleteVehicleCrew _x} forEach crew _drone;
    createVehicleCrew _drone;
    {
        _x setVariable ["CLDW_IsDroneCrew",true,true];
        _x setVariable ["CLDW_DroneCrewUsed",true,true];
        _x setVariable ["CLDW_CurrentOperator",_op,true];
        _x setVariable ["A3A_isIrrelevant",true,true];
        if (_x in switchableUnits) then {removeSwitchableUnit _x;};
    } forEach (crew _drone);
    if (!isNull _op && {alive _op}) then {
        _drone setVariable ["CLDW_CurrentOperator",_op,true];
        _drone setVariable ["CLDW_OperatorGroup",group _op,true];
    };
    _drone enableSimulationGlobal true;
    _drone engineOn true;
    if (alive driver _drone) then {
        (driver _drone) enableAI "PATH";
        (driver _drone) enableAI "MOVE";
    };
    _drone enableAI "PATH";
    _drone enableAI "MOVE";
    _drone forceSpeed -1;
    _drone limitSpeed false;
    _drone setVariable ["CLDW_PilotLostAt",-1];
    private _idleRepair = _reason == 'idle pilot ignored orders';
    if (_idleRepair) then {
        _drone setVariable ['CLDW_IdleRepairCount',
            (_drone getVariable ['CLDW_IdleRepairCount',0]) + 1];
    };
    _drone setVariable ["CLDW_Disengaged",!_idleRepair,true];
    _drone setVariable ["CLDW_StallState",[getPosASLVisual _drone,diag_tickTime,
        if (_idleRepair) then {-1} else {diag_tickTime},if (_idleRepair) then {-1} else {1}]];
    true
};

if (!alive driver _drone) exitWith {
    private _lostAt = _drone getVariable ["CLDW_PilotLostAt",-1];
    if (_lostAt < 0) then {
        _drone setVariable ["CLDW_PilotLostAt",_now];
    } else {
        if (_now - _lostAt >= 5) then {["pilot lost"] call _repair;};
    };
    true
};
_drone setVariable ["CLDW_PilotLostAt",-1];

if (([_drone] call CLDW_fnc_getDroneRole) != "SUICIDE") exitWith {
    _drone setVariable ["CLDW_StallState",[]];
    false
};

private _pos = getPosASLVisual _drone;
private _state = _drone getVariable ["CLDW_StallState",[]];
if (count _state < 3) exitWith {
    _drone setVariable ["CLDW_StallState",[_pos,_now,-1]];
    false
};
_state params ["_anchor","_lastProgress","_recoveryAt"];
private _phase = _state param [3,-1];
private _goal = _drone getVariable ["CLDW_ProgressGoalASL",[]];
private _closing = count _goal == 3 && {(_anchor distance _goal) - (_pos distance _goal) >= 4};
if (_pos distance2D _anchor >= 8 || {_closing}) exitWith {
    _drone setVariable ["CLDW_StallState",[_pos,_now,-1,-1]];
    _drone setVariable ['CLDW_IdleRepairCount',0];
    false
};

if (_phase == 3 && {_recoveryAt >= 0}) exitWith {
    if (_now - _recoveryAt < 10) exitWith {false};
    if ((_drone getVariable ['CLDW_IdleRepairCount',0]) == 0) exitWith {
        ['idle pilot ignored orders'] call _repair
    };
    if !(_drone getVariable ['CLDW_RecoveryJoined',false]) exitWith {
        diag_log format ['CLDW [Watchdog]: %1 idle pilot still stalled; trying operator group.',typeOf _drone];
        _drone setVariable ['CLDW_RecoveryJoined',true,true];
        if (isServer) then {[_drone] call CLDW_fnc_rejoinSquad}
        else {[_drone] remoteExecCall ['CLDW_fnc_rejoinSquad',2]};
        _drone setVariable ['CLDW_LoiterActive',false];
        _drone setVariable ['CLDW_StallState',[_pos,_now,-1,-1]];
        false
    };
    _drone setVariable ['CLDW_Disengaged',true,true];
    _drone setVariable ['CLDW_StallState',[_pos,_now,-1,-1]];
    false
};

if (_recoveryAt < 0 && {_now - _lastProgress >= 12} &&
    {_drone getVariable ['CLDW_LoiterActive',false]} &&
    {isNull (_drone getVariable ['CLDW_CurrentTarget',objNull])}) exitWith {
    // Retry the native pilot and waypoint before replacing crew. No scripted
    // velocity or orientation is applied to a loitering drone.
    diag_log format ['CLDW [Watchdog]: %1 idle pilot ignored waypoint; retrying native loiter.',typeOf _drone];
    (driver _drone) enableAI 'PATH';
    (driver _drone) enableAI 'MOVE';
    _drone enableAI 'PATH';
    _drone enableAI 'MOVE';
    _drone setVariable ['CLDW_LoiterActive',false];
    private _op = _drone getVariable ['CLDW_CurrentOperator',objNull];
    private _center = if (!isNull _op && {alive _op}) then {getPosATL _op} else {getPosATL _drone};
    [_drone,_center,'LOITER'] call CLDW_fnc_move;
    _drone setVariable ['CLDW_StallState',[_pos,_now,_now,3]];
    false
};

if (_recoveryAt < 0 && {_now - _lastProgress >= 12} &&
    {((_drone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE"}) exitWith {
    diag_log format ["CLDW [Watchdog]: %1 attack path stalled; disengaging without vertical impulse.",typeOf _drone];
    private _target = _drone getVariable ["CLDW_CurrentTarget",objNull];
    if (!isNull _target && {_target getVariable ["CLDW_AssignedDrone",objNull] == _drone}) then {
        _target setVariable ["CLDW_AssignedDrone",objNull,true];
    };
    _drone setVariable ["CLDW_CurrentTarget",objNull,true];
    _drone setVariable ["CLDW_Disengaged",true,true];
    private _op = _drone getVariable ["CLDW_CurrentOperator",objNull];
    [_drone,"RETURN",[_drone,getPosASLVisual _drone,_op]] call CLDW_fnc_startController;
    _drone setVariable ["CLDW_StallState",[_pos,_now,_now,0]];
    false
};

if (_recoveryAt < 0 && {_now - _lastProgress >= 12}) exitWith {
    diag_log format ["CLDW [Watchdog]: %1 has not moved 8m in 12s; attempting return recovery.",typeOf _drone];
    private _idle = _drone getVariable ["CLDW_IdleHandle",scriptNull];
    if (!scriptDone _idle) then {terminate _idle;};
    _drone setVariable ["CLDW_IdleHandle",scriptNull];
    private _flight = _drone getVariable ["CLDW_Controller",scriptNull];
    if (!scriptDone _flight) then {terminate _flight;};
    _drone setVariable ["CLDW_Controller",scriptNull];
    private _target = _drone getVariable ["CLDW_CurrentTarget",objNull];
    if (!isNull _target && {_target getVariable ["CLDW_AssignedDrone",objNull] == _drone}) then {
        _target setVariable ["CLDW_AssignedDrone",objNull,true];
    };
    _drone setVariable ["CLDW_CurrentTarget",objNull,true];
    _drone setVariable ["CLDW_ControlIntent",[],true];
    _drone setVariable ["CLDW_SearchUntil",0,true];
    _drone setVariable ["CLDW_SearchWindowUntil",0];
    _drone setVariable ["CLDW_SearchFallback",false];
    _drone setVariable ["CLDW_LoiterActive",false];
    _drone setVariable ["CLDW_Disengaged",true,true];
    (driver _drone) enableAI "PATH";
    _drone enableAI "PATH";
    _drone forceSpeed -1;
    _drone limitSpeed false;
    _drone setVariable ["CLDW_StallState",[_pos,_now,_now,0]];
    false
};

if (_phase == 0 && {_recoveryAt >= 0} && {_now - _recoveryAt >= 15}) exitWith {
    ["no movement after return recovery"] call _repair
};
if (_phase == 1 && {_recoveryAt >= 0} && {_now - _recoveryAt >= 8}) exitWith {
    diag_log format ["CLDW [Watchdog]: %1 still stalled; temporarily joining its operator squad.",typeOf _drone];
    _drone setVariable ["CLDW_RecoveryJoined",true,true];
    if (isServer) then {[_drone] call CLDW_fnc_rejoinSquad;}
    else {[_drone] remoteExecCall ["CLDW_fnc_rejoinSquad",2];};
    private _flight = _drone getVariable ["CLDW_Controller",scriptNull];
    if (!scriptDone _flight) then {terminate _flight;};
    _drone setVariable ["CLDW_Controller",scriptNull];
    _drone setVariable ["CLDW_ControlIntent",[],true];
    _drone setVariable ["CLDW_Disengaged",true,true];
    _drone setVariable ["CLDW_StallState",[_pos,_now,_now,2]];
    true
};
if (_phase == 2 && {_recoveryAt >= 0} && {_now - _recoveryAt >= 10}) then {
    // Never relocate a living drone. Give the physical return another chance.
    (driver _drone) enableAI "PATH";
    _drone enableAI "PATH";
    _drone setVariable ["CLDW_StallState",[_pos,_now,_now,2]];
};
false
