// Read-only aggregate; never opt out of native EW, repair crew, or force an engine on.
params ["_drone"];
if (isNull _drone) exitWith {true};
private _cached = _drone getVariable ["CLDW_EWCache", [-1, false]];
if (diag_tickTime < (_cached select 0)) exitWith {_cached select 1};
private _blocked = _drone getVariable ["CLDW_EWSuppressed", false];
{
    if ([_drone] call _y) exitWith {_blocked = true;};
} forEach (missionNamespace getVariable ["CLDW_ewAdapters", createHashMap]);
_drone setVariable ["CLDW_EWCache", [diag_tickTime + 0.1, _blocked]];
_blocked
