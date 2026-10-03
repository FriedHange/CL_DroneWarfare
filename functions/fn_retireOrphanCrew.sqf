// Server request to kill an orphaned UAV pilot on the pilot's own machine.
params [["_drone",objNull],["_pilot",objNull]];
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {};
if (isNull _drone || {isNull _pilot} || {!local _pilot} ||
    {!(_drone getVariable ["CLDW_Orphaned",false])} ||
    {vehicle _pilot != _drone} || {isPlayer _pilot}) exitWith {};
if (alive _pilot) then {_pilot setDamage 1;};
