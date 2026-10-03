// Group mutation stays on the server, including when the vehicle is HC-owned.
params [["_drone",objNull],["_detach",false]];
if (!isServer || {isNull _drone} || {!alive _drone} ||
    {!(_drone getVariable ["CLDW_AI_Spawned",false])}) exitWith {};
if (isRemoteExecuted && {remoteExecutedOwner != owner _drone}) exitWith {};
private _op = _drone getVariable ["CLDW_CurrentOperator",objNull];
if (isNull _op || {!alive _op}) exitWith {};
private _squad = group _op;
if (isNull _squad || {side _squad != (_drone getVariable ["CLDW_DroneSide",sideUnknown])}) exitWith {};
private _crew = (crew _drone) select {alive _x};
if (_crew isEqualTo []) exitWith {};
if (_detach) exitWith {
    private _uavGroup = createGroup [side _squad,true];
    _crew joinSilent _uavGroup;
    _uavGroup deleteGroupWhenEmpty true;
    _drone setVariable ["CLDW_RecoveryJoined",false,true];
    diag_log format ["CLDW [Watchdog]: %1 reached operator; crew resumed its own UAV group.",typeOf _drone];
};
if !(_drone getVariable ["CLDW_RecoveryJoined",false]) exitWith {};
_crew joinSilent _squad;
diag_log format ["CLDW [Watchdog]: Rejoined %1 crew to operator squad %2.",typeOf _drone,_squad];
