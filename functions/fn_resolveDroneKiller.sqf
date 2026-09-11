/*
    File: fn_resolveDroneKiller.sqf
    Author: Carl Lorenzo
    Description:
        Resolves the true human or AI soldier operator responsible for a kill when a drone or explosive detonation causes death.
        Prevents death cameras (such as in RIS) from focusing on deleted drone hulls, vehicle wrecks, or map coordinate [0,0,0].
    Parameters:
        0: OBJECT - Victim unit that died
        1: OBJECT - Killer unit reported by engine (optional)
        2: OBJECT - Instigator unit reported by engine (optional)
    Returns:
        OBJECT - The living/valid soldier operator (CAManBase), or objNull if no valid human/AI attacker exists.
*/

params [["_victim", objNull], ["_killer", objNull], ["_instigator", objNull]];

private _resolved = objNull;

// Helper to determine if an object is a drone, drone crew, or drone wreckage
private _fnc_isDrone = {
    params ["_obj"];
    if (isNull _obj) exitWith { false };
    if (_obj isKindOf "UAV" || {unitIsUAV _obj} || {_obj getVariable ["CLDW_IsDroneCrew", false]}) exitWith { true };
    if (_obj getVariable ["ddtDrone", false] || {!isNull (_obj getVariable ["ddtOwner", objNull])} || {!isNull (_obj getVariable ["CLDW_CurrentOperator", objNull])}) exitWith { true };
    private _type = toLower (typeOf _obj);
    ((_type find "crocus" > -1) || 
     (_type find "kvn" > -1) || 
     (_type find "uafpv" > -1) || 
     (_type find "rc40" > -1) || 
     (_type find "rc-40" > -1) || 
     (_type find "uav_02_ied" > -1) || 
     (_type find "tura_uav" > -1) || 
     (_type find "uav_06" > -1) ||
     (_type find "uas_06" > -1) ||
     (_type find "drone" > -1) || 
     (_type find "fpv" > -1))
};

// 1. Check if the victim was recently tagged by an FPV drone attack
if (!isNull _victim) then {
    private _lastAttacker = _victim getVariable ["CLDW_LastDroneAttacker", objNull];
    private _lastTime = _victim getVariable ["CLDW_LastDroneAttackerTime", -999];
    if (!isNull _lastAttacker && {time - _lastTime < 30.0} && {alive _lastAttacker} && {_lastAttacker isKindOf "CAManBase"} && {(_lastAttacker distance [0,0,0]) > 150}) then {
        _resolved = _lastAttacker;
    };
};

// 2. Check if _killer is a drone or drone crew
if (isNull _resolved && {!isNull _killer}) then {
    if (_killer call _fnc_isDrone) then {
        private _op = _killer getVariable ["CLDW_CurrentOperator", objNull];
        if (isNull _op) then { _op = _killer getVariable ["ddtOwner", objNull]; };
        if (!isNull _op && {alive _op} && {_op isKindOf "CAManBase"} && {(_op distance [0,0,0]) > 150}) then { _resolved = _op; };
    } else {
        if (_killer getVariable ["CLDW_IsDroneCrew", false] || {typeOf _killer in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]}) then {
            private _veh = vehicle _killer;
            private _op = _veh getVariable ["CLDW_CurrentOperator", objNull];
            if (isNull _op) then { _op = _killer getVariable ["CLDW_CurrentOperator", objNull]; };
            if (isNull _op) then { _op = _veh getVariable ["ddtOwner", objNull]; };
            if (!isNull _op && {alive _op} && {_op isKindOf "CAManBase"} && {(_op distance [0,0,0]) > 150}) then { _resolved = _op; };
        };
    };
};

// 3. Check _instigator if provided
if (isNull _resolved && {!isNull _instigator}) then {
    if (_instigator call _fnc_isDrone) then {
        private _op = _instigator getVariable ["CLDW_CurrentOperator", objNull];
        if (isNull _op) then { _op = _instigator getVariable ["ddtOwner", objNull]; };
        if (!isNull _op && {alive _op} && {_op isKindOf "CAManBase"} && {(_op distance [0,0,0]) > 150}) then { _resolved = _op; };
    } else {
        if (_instigator getVariable ["CLDW_IsDroneCrew", false] || {typeOf _instigator in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]}) then {
            private _veh = vehicle _instigator;
            private _op = _veh getVariable ["CLDW_CurrentOperator", objNull];
            if (isNull _op) then { _op = _instigator getVariable ["CLDW_CurrentOperator", objNull]; };
            if (isNull _op) then { _op = _veh getVariable ["ddtOwner", objNull]; };
            if (!isNull _op && {alive _op} && {_op isKindOf "CAManBase"} && {(_op distance [0,0,0]) > 150}) then { _resolved = _op; };
        };
    };
};

// 4. Fallback search: Check recently active drones targeting or near the victim
if (isNull _resolved && {!isNull _victim}) then {
    private _victimPos = getPosATL _victim;
    {
        if (!isNull _x) then {
            private _op = _x getVariable ["CLDW_CurrentOperator", objNull];
            if (isNull _op) then { _op = _x getVariable ["ddtOwner", objNull]; };
            if (!isNull _op && {alive _op} && {_op isKindOf "CAManBase"} && {(_op distance [0,0,0]) > 150}) then {
                private _target = _x getVariable ["CLDW_CurrentTarget", objNull];
                if (_target == _victim || {(_x distance _victimPos) < 50}) exitWith {
                    _resolved = _op;
                };
            };
        };
    } forEach (missionNamespace getVariable ["CLDW_activeDrones", []]);
};

// 5. If not a drone kill, check if original _killer is a valid non-drone soldier or vehicle crew
if (isNull _resolved && {!isNull _killer} && {!(_killer call _fnc_isDrone)}) then {
    if (_killer isKindOf "CAManBase" && {alive _killer} && {(_killer distance [0,0,0]) > 150}) then {
        _resolved = _killer;
    } else {
        // Vehicle kill (tank, IFV, heli): resolve to the driver or gunner
        private _crewUnit = effectiveCommander _killer;
        if (isNull _crewUnit || {!alive _crewUnit}) then { _crewUnit = gunner _killer; };
        if (!isNull _crewUnit && {alive _crewUnit} && {_crewUnit isKindOf "CAManBase"} && {(_crewUnit distance [0,0,0]) > 150}) then {
            _resolved = _crewUnit;
        };
    };
};

// 6. If _instigator is a valid non-drone soldier and _resolved is still null
if (isNull _resolved && {!isNull _instigator} && {!(_instigator call _fnc_isDrone)}) then {
    if (_instigator isKindOf "CAManBase" && {alive _instigator} && {(_instigator distance [0,0,0]) > 150}) then {
        _resolved = _instigator;
    } else {
        private _crewUnit = effectiveCommander _instigator;
        if (isNull _crewUnit || {!alive _crewUnit}) then { _crewUnit = gunner _instigator; };
        if (!isNull _crewUnit && {alive _crewUnit} && {_crewUnit isKindOf "CAManBase"} && {(_crewUnit distance [0,0,0]) > 150}) then {
            _resolved = _crewUnit;
        };
    };
};

// 7. Strict soldier validation:
// If _resolved is null, deleted, dead, not a CAManBase soldier, or located near [0,0,0],
// return objNull so death cameras remain focused on the victim's body instead of swinging to [0,0,0].
if (isNull _resolved || {!alive _resolved} || {!(_resolved isKindOf "CAManBase")} || {(_resolved distance [0,0,0]) < 150}) exitWith { objNull };

_resolved
