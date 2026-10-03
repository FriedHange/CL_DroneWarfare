/*
    Local interface; register on server, HC and clients during postInit.
    [uniqueName, { params ["_drone"]; bool }] call CLDW_fnc_registerEWAdapter;
    Return true only when CLDW must yield control. Provider owns immunity, ranges,
    native suppression and recovery. Callbacks must be unscheduled and read-only.
*/
params [["_name", "", [""]], ["_callback", {}, [{}]]];
if (_name == "") exitWith {false};
if (isNil "CLDW_ewAdapters") then {CLDW_ewAdapters = createHashMap;};
CLDW_ewAdapters set [_name, _callback];
true
