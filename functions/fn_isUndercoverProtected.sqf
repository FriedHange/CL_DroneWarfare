/*
    File: fn_isUndercoverProtected.sqf
    Author: Carl Lorenzo
    Description:
        Returns true when a target must NOT be engaged by this drone because the mission marked
        it as undercover / non-hostile. Antistasi and Antistasi Ultimate mark undercover players
        with `setCaptive true` (cleared when compromised), so `captive` is the live undercover state.
        Vehicles carrying any undercover crew member are protected as a whole so drones never
        detonate on civilian cars with undercover passengers. Captive-marked (surrendered) AI are
        likewise protected, so drones never finish off surrendered units.
        Deliberate exception: Antistasi Ultimate's RIVALS faction recognises its own and keeps
        hunting undercover operatives for extra difficulty. Rival units carry the mission-assigned
        `isRival` variable and a `loadouts_riv_` unit-type prefix, which distinguishes them from
        conventional Occupants/Invaders even though Rivals share the east engine side with Invaders.
    Params:
        0: OBJECT - the drone (or operator) evaluating the target; used to detect the Rivals faction
        1: OBJECT - the candidate target unit or vehicle
    Returns:
        BOOL - true if the target is undercover-protected and must not be engaged
*/

params [["_source", objNull], ["_target", objNull]];

if (isNull _target) exitWith { false };

// Collect the man-units relevant to the target (the unit itself, or the vehicle's crew)
private _crew = if (_target isKindOf "CAManBase") then { [_target] } else { (crew _target) select { alive _x } };
if (_crew isEqualTo []) exitWith { false };

// Undercover state in Antistasi / Antistasi Ultimate is setCaptive true
if ({ captive _x } count _crew == 0) exitWith { false };

// Resolve the operator behind the source (drone or man) to identify the drone's faction
private _operator = objNull;
if (!isNull _source) then {
    if (_source isKindOf "CAManBase") then {
        _operator = _source;
    } else {
        _operator = _source getVariable ["CLDW_CurrentOperator", objNull];
        if (isNull _operator) then {
            private _ownerVar = _source getVariable ["ddtOwner", objNull];
            if (_ownerVar isEqualType objNull) then {
                _operator = _ownerVar;
            } else {
                if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
                    { if (str _x == _ownerVar) exitWith { _operator = _x; }; } forEach allUnits;
                };
            };
        };
    };
};

// Antistasi Ultimate RIVALS: they recognise their own and ignore undercover status
private _isRival = false;
if (!isNull _operator) then {
    _isRival = _operator getVariable ["isRival", false];
    if (!_isRival) then {
        _isRival = "loadouts_riv_" in (toLower (_operator getVariable ["unitType", ""]));
    };
    if (!_isRival) then {
        private _grp = group _operator;
        if (!isNull _grp) then {
            _isRival = { _x getVariable ["isRival", false] } count (units _grp) > 0;
        };
    };
};
if (_isRival) exitWith { false };

// Undercover-protected: do not engage this target
true
