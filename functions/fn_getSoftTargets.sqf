/*
    File: fn_getSoftTargets.sqf
    Author: Carl Lorenzo
    Description:
        Target acquisition for anti-personnel (AP) and light vehicle drone engagements.
        Features:
        1. Supports hostile infantry, soft-skinned ground vehicles, light naval craft, and airborne targets.
        2. Strict anti-wallhack raycast LOS validation against terrain, buildings, and structures.
        3. Unified speed integration.
*/

params [["_man", objNull], ["_rangeInput", -1]];

if (_man isEqualType grpNull) then { _man = leader _man; };
if (isNull _man) exitWith { [] };

private _operator = objNull;
private _uav = objNull;

// Resolve _uav and _operator from _man
if (_man isKindOf "AllVehicles" && {!(_man isKindOf "Man")}) then {
    _uav = _man;
    _operator = _uav getVariable ["CLDW_CurrentOperator", objNull];
    if (isNull _operator) then {
        private _ownerVar = _uav getVariable ["ddtOwner", objNull];
        if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
            _operator = _ownerVar;
        } else {
            if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
                { if (str _x == _ownerVar) exitWith { _operator = _x; }; } forEach allUnits;
            };
        };
    };
    if (isNull _operator) then {
        private _crew = crew _uav;
        if (count _crew > 0) then {
            _operator = leader (group (_crew select 0));
        } else {
            _operator = driver _uav;
        };
    };
} else {
    if (vehicle _man != _man) then {
        _uav = vehicle _man;
        _operator = _uav getVariable ["CLDW_CurrentOperator", _man];
    } else {
        _operator = _man;
        _uav = getConnectedUAV _operator;
        if (isNull _uav) then {
            private _allUAVs = vehicles select { alive _x && { _x isKindOf "UAV" || _x isKindOf "Air" } };
            {
                private _opVar = _x getVariable ["CLDW_CurrentOperator", objNull];
                private _ownerVar = _x getVariable ["ddtOwner", objNull];
                if (_opVar == _operator || 
                    {_ownerVar isEqualTo _operator} || 
                    {(_ownerVar isEqualType "") && {_ownerVar == str _operator}}) exitWith {
                    _uav = _x;
                };
            } forEach _allUAVs;
        };
    };
};

if (isNull _operator && isNull _uav) exitWith { [] };
if (isNull _operator) then { _operator = _uav; };

private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000];
private _range = _maxRangeSetting;

private _opGrp = if (!isNull _operator && {_operator isKindOf "Man"}) then { group _operator } else { grpNull };
private _manSide = if (!isNull _opGrp) then { side _opGrp } else { side _operator };
if (_manSide == sideUnknown && {!isNull _uav}) then {
    private _uavGrp = group (driver _uav);
    if (!isNull _uavGrp) then { _manSide = side _uavGrp; } else { _manSide = side _uav; };
};
if (_manSide == sideUnknown) then { _manSide = civilian; };

private _threshold = missionNamespace getVariable ["ddtSoftThreshold", 100];

// Gather potential targets based on actual detection and vehicle signatures
private _candidates = [];

if (!isNull _operator && {_operator isKindOf "Man"}) then {
    _candidates append (_operator targets [true, _range]);
    if (!isNull (leader group _operator) && {leader group _operator != _operator}) then {
        _candidates append ((leader group _operator) targets [true, _range]);
    };
};

if (!isNull _uav) then {
    private _pilot = driver _uav;
    if (!isNull _pilot) then {
        _candidates append (_pilot targets [true, _range]);
    };
    // Vehicles (engines, metal, heat signatures) can be detected within full range
    private _nearVehicles = (getPosATL _uav) nearEntities [["LandVehicle", "Ship", "Air"], _range];
    _candidates append _nearVehicles;
    // Infantry without prior knowledge can only be spotted visually within direct visual search radius (max 600m)
    private _nearInfantry = (getPosATL _uav) nearEntities ["CAManBase", 600 min _range];
    _candidates append _nearInfantry;
} else {
    if (!isNull _operator && {_operator isKindOf "Man"}) then {
        // Ground operator scans vehicles within threat range
        private _nearVehicles = (getPosATL _operator) nearEntities [["LandVehicle", "Ship", "Air"], _range min 1000];
        _candidates append _nearVehicles;
    };
};

// Deduplicate candidates
private _uniqueTargets = [];
{
    private _veh = vehicle _x;
    if (!isNull _veh && {!(_veh in _uniqueTargets)}) then {
        _uniqueTargets pushBack _veh;
    };
} forEach _candidates;

private _out = [];

{
    private _v = _x;
    if (alive _v) then {
        private _isDrone = (_v isKindOf "UAV") || {unitIsUAV _v} || {_v getVariable ["CLDW_IsDroneCrew", false]} || {_v getVariable ["USED", false]};
        if (!_isDrone && {_v != _uav}) then {
            private _vSide = sideUnknown;
            if (_v isKindOf "CAManBase") then {
                _vSide = side (group _v);
            } else {
                private _crew = crew _v;
                if (count _crew > 0) then {
                    _vSide = side (group (_crew select 0));
                } else {
                    _vSide = side _v;
                };
            };

            private _isHostile = false;
            if (_vSide != civilian && {_vSide != sideUnknown} && {_vSide != sideLogic}) then {
                _isHostile = ([_manSide, _vSide] call BIS_fnc_areFriendly) isEqualTo false || 
                             { (_manSide getFriend _vSide < 0.6) || (_vSide getFriend _manSide < 0.6) };
            };

            if (_isHostile) then {
                private _dist = if (!isNull _uav) then { _uav distance _v } else { _operator distance _v };
                if (_dist <= _range) then {
                    private _isSoftTarget = false;
                    if (_v isKindOf "CAManBase") then {
                        _isSoftTarget = true;
                    } else {
                        private _armor = getNumber (configFile >> "CfgVehicles" >> (typeOf _v) >> "armor");
                        private _isSoftVehicle = (_v isKindOf "Car") || {_v isKindOf "Truck"} || {_v isKindOf "Motorcycle"} || {_v isKindOf "Ship"} || {_v isKindOf "Air"} || {_armor <= (_threshold max 150)};
                        private _isHeavyArmor = (_v isKindOf "Tank") || {_v isKindOf "APC"} || {_v isKindOf "Wheeled_APC_F"};
                        if (_isSoftVehicle && !_isHeavyArmor) then {
                            _isSoftTarget = true;
                        };
                    };

                    // Antistasi Petros / Rebel HQ Commander Protection
                    private _isPetros = (_v == (missionNamespace getVariable ["petros", objNull])) ||
                                        {_v getVariable ["isPetros", false]} ||
                                        {(toLower (name _v)) find "petros" > -1};
                    if (_isPetros) then {
                        // In Antistasi, Petros is the rebel commander at the secret HQ.
                        // He must never be targeted by ambient FPV drones unless an enemy squad has direct, close-quarters confirmed contact.
                        private _opGrp = if (!isNull _operator && {_operator isKindOf "Man"}) then { group _operator } else { grpNull };
                        private _knowsAbout = if (!isNull _opGrp) then { _opGrp knowsAbout _v } else { 0 };
                        if (_dist > 400 || _knowsAbout < 1.5) then {
                            _isSoftTarget = false;
                        };
                    };

                    if (_isSoftTarget) then {
                        // Strict Raycast LOS & Engine Visibility validation (anti-wallhack & foliage check)
                        private _eyeStart = if (!isNull _uav) then {
                            (getPosASL _uav) vectorAdd [0, 0, 0.4]
                        } else {
                            eyePos _operator
                        };
                        if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _operator) vectorAdd [0,0,1.5]; };

                        private _eyeEnd = if (_v isKindOf "CAManBase") then {
                            eyePos _v
                        } else {
                            (getPosASL _v) vectorAdd [0, 0, 0.8]
                        };
                        if (_eyeEnd isEqualTo [0,0,0]) then { _eyeEnd = (getPosASL _v) vectorAdd [0,0,1.0]; };

                        // 1. Terrain occlusion check
                        private _losBlocked = terrainIntersectASL [_eyeStart, _eyeEnd];
                        if (!_losBlocked) then {
                            private _ignore1 = if (!isNull _uav) then { _uav } else { _operator };
                            // 2. Engine visibility check (handles trees, bushes, forests, viewing obstacles)
                            private _vis = [_ignore1, "VIEW", _v] checkVisibility [_eyeStart, _eyeEnd];
                            if (_vis < 0.2) then {
                                _losBlocked = true;
                            } else {
                                // 3. Surface intersection check (buildings, walls, rocks, structures, objects)
                                private _intersections = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _ignore1, _v, true, 1, "VIEW", "GEOM"];
                                if (count _intersections > 0) then {
                                    _losBlocked = true;
                                };
                            };
                        };

                        if (!_losBlocked) then {
                            _out pushBackUnique _v;
                        };
                    };
                };
            };
        };
    };
} forEach _uniqueTargets;

if !(_out isEqualTo []) then {
    if (!isNull _uav) then {
        private _closestTarget = objNull;
        private _minDist = 999999;
        private _refPos = getPosASL _uav;
        {
            private _d = _refPos distance (getPosASL _x);
            if (_d < _minDist) then {
                _minDist = _d;
                _closestTarget = _x;
            };
        } forEach _out;
        
        if (!isNull _closestTarget) then {
            _uav setVariable ["CLDW_CurrentTarget", _closestTarget, true];
            _uav setVariable ["CLDW_CurrentOperator", _operator, true];
        };
    };
};

_out
