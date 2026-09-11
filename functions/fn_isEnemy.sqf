/*
    File: fn_isEnemy.sqf
    Author: Carl Lorenzo
    Description:
        Evaluates whether a target is a valid, living hostile enemy for a drone or operator.
        Enforces crew checks: vehicles and static weapon proxies without active, living AI/player crew are NEVER considered hostile enemies.
*/

params [["_source", objNull], ["_target", objNull]];

if (isNull _source || {isNull _target} || {!alive _target}) exitWith { false };
if (_target == _source) exitWith { false };
if (unitIsUAV _target || {_target isKindOf "UAV"} || {_target getVariable ["CLDW_IsDroneCrew", false]}) exitWith { false };

// Determine source combat side
private _sourceSide = sideUnknown;
if (!isNull _source) then {
    _sourceSide = _source getVariable ["CLDW_DroneSide", sideUnknown];
    if (_sourceSide == sideUnknown || {_sourceSide == civilian}) then {
        private _op = _source getVariable ["CLDW_CurrentOperator", objNull];
        if (!isNull _op && {alive _op}) then {
            _sourceSide = side group _op;
        } else {
            private _opGrp = _source getVariable ["CLDW_OperatorGroup", grpNull];
            if (!isNull _opGrp) then {
                _sourceSide = side _opGrp;
            };
        };
    };
    if (_sourceSide == sideUnknown || {_sourceSide == civilian}) then {
        if (_source isKindOf "Man") then {
            _sourceSide = side group _source;
        } else {
            private _drv = driver _source;
            if (!isNull _drv && {alive _drv}) then {
                _sourceSide = side group _drv;
            } else {
                private _crew = (crew _source) select { alive _x };
                if (count _crew > 0) then {
                    _sourceSide = side group (_crew select 0);
                } else {
                    _sourceSide = side _source;
                };
            };
        };
    };
};

if (_sourceSide == sideUnknown || {_sourceSide == civilian}) exitWith { false };

// Determine target combat side and validate active crew for vehicles / static weapons
private _targetSide = sideUnknown;
if (_target isKindOf "CAManBase") then {
    private _grp = group _target;
    _targetSide = if (!isNull _grp) then { side _grp } else { side _target };
} else {
    // Target is a vehicle or static weapon proxy (e.g., StaticMGWeapon, StaticMortar, etc.)
    private _aliveCrew = (crew _target) select { alive _x };
    // Strict Requirement: Ensure count (crew _veh) > 0 and AI/player crew is active and alive
    if (count _aliveCrew == 0) exitWith { false };
    private _cUnit = _aliveCrew select 0;
    private _grp = group _cUnit;
    _targetSide = if (!isNull _grp) then { side _grp } else { side _cUnit };
};

if (_targetSide == sideUnknown || {_targetSide == civilian} || {_targetSide == sideLogic}) exitWith { false };

// Check hostility
(([_sourceSide, _targetSide] call BIS_fnc_areFriendly) isEqualTo false) || 
{ (_sourceSide getFriend _targetSide < 0.6) || (_targetSide getFriend _sourceSide < 0.6) }
