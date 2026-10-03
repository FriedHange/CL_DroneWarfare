params [["_input", objNull]];
if (_input isEqualType objNull && {isNull _input}) exitWith {"NONCOMBAT"};
private _type = if (_input isEqualType "") then {_input} else {typeOf _input};
private _overrides = if (_input isEqualType "") then {[]} else {
    [_input getVariable ["CLDW_DroneRole", ""], _input getVariable ["CLDW_IsNonCombat", false], _input getVariable ["CLDW_IsDropper", false], _input getVariable ["CLDW_IsSuicide", false], _input getVariable ["ddtExclude", false]]
};
private _key = str [_type, _overrides, missionNamespace getVariable ["ddtClassesBomber", []],
    missionNamespace getVariable ["ddtClassesFPV", []], missionNamespace getVariable ["ddtClassesFPVAT", []]];
if (isNil "CLDW_roleCache") then {CLDW_roleCache = createHashMap;};
private _role = CLDW_roleCache getOrDefault [_key, ""];
if (_role == "") then {_role = [_input] call CLDW_fnc_classifyDroneRole; CLDW_roleCache set [_key, _role];};
_role
