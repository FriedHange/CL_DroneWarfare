// The server marks a lost-operator drone; its current owner retires the AI.
params [["_drone",objNull]];
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {};
if (isNull _drone || {!(_drone getVariable ["CLDW_AI_Spawned",false])} ||
    {!(_drone getVariable ["CLDW_Orphaned",false])}) exitWith {};
if (!local _drone) exitWith {
    if (isServer) then {_this remoteExecCall ["CLDW_fnc_retireOrphan",_drone];};
};
if (_drone getVariable ["CLDW_OrphanFinalized",false]) exitWith {};

private _target = _drone getVariable ["CLDW_CurrentTarget",objNull];
if (!isNull _target && {_target getVariable ["CLDW_AssignedDrone",objNull] == _drone}) then {
    _target setVariable ["CLDW_AssignedDrone",objNull,true];
};
private _flight = _drone getVariable ["CLDW_Controller",scriptNull];
if (!scriptDone _flight) then {terminate _flight;};
private _idle = _drone getVariable ["CLDW_IdleHandle",scriptNull];
if (!scriptDone _idle) then {terminate _idle;};
_drone setVariable ["CLDW_Controller",scriptNull];
_drone setVariable ["CLDW_IdleHandle",scriptNull];
_drone setVariable ["CLDW_CurrentTarget",objNull,true];
_drone setVariable ["CLDW_ControlIntent",[],true];
_drone setVariable ["CLDW_SearchUntil",0,true];
_drone setVariable ["CLDW_LoiterActive",false];
_drone setVariable ["ddtExclude",true,true];
_drone setVariable ["CLDW_FPV_Running",0,true];
{
    if (alive _x && {!isPlayer _x} && {local _x}) then {_x setDamage 1;};
} forEach crew _drone;
if (({alive _x && {!isPlayer _x}} count (crew _drone)) == 0) then {
    _drone setVariable ["CLDW_OrphanFinalized",true,true];
    diag_log format ["CLDW [Orphan]: Retired crew of %1 after assigned operator loss.",typeOf _drone];
};
