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
private _range = if (_rangeInput > 0) then { _rangeInput min _maxRangeSetting } else { _maxRangeSetting };

// Determine combat side
private _droneSide = if (!isNull _uav) then { _uav getVariable ["CLDW_DroneSide", sideUnknown] } else { sideUnknown };
private _opGrp = if (!isNull _operator && {_operator isKindOf "Man"} && {alive _operator}) then {
    group _operator
} else {
    if (!isNull _uav) then { _uav getVariable ["CLDW_OperatorGroup", grpNull] } else { grpNull }
};

private _manSide = sideUnknown;
if (!isNull _opGrp) then {
    _manSide = side _opGrp;
};
if ((_manSide == sideUnknown || {_manSide == civilian}) && {!isNull _operator} && {alive _operator}) then {
    _manSide = side _operator;
};
if ((_manSide == sideUnknown || {_manSide == civilian}) && {_droneSide != sideUnknown} && {_droneSide != civilian}) then {
    _manSide = _droneSide;
};
if ((_manSide == sideUnknown || {_manSide == civilian}) && {!isNull _uav}) then {
    private _pilot = driver _uav;
    if (!isNull _pilot && {alive _pilot}) then {
        private _uavGrp = group _pilot;
        if (!isNull _uavGrp) then { _manSide = side _uavGrp; } else { _manSide = side _pilot; };
    } else {
        private _crew = (crew _uav) select { alive _x };
        if (count _crew > 0) then {
            _manSide = side (group (_crew select 0));
        } else {
            _manSide = side _uav;
        };
    };
};
if ((_manSide == sideUnknown || {_manSide == civilian}) && {!isNull _uav}) then {
    private _cfgSideNum = getNumber (configFile >> "CfgVehicles" >> (typeOf _uav) >> "side");
    switch (_cfgSideNum) do {
        case 0: { _manSide = east; };
        case 1: { _manSide = west; };
        case 2: { _manSide = independent; };
    };
};
if (_manSide == sideUnknown) then { _manSide = civilian; };
if (!isNull _uav && {_droneSide == sideUnknown || {_droneSide == civilian}} && {_manSide != civilian}) then {
    _uav setVariable ["CLDW_DroneSide", _manSide, true];
};

private _threshold = missionNamespace getVariable ["ddtSoftThreshold", 100];

// Gather potential targets based on actual detection and vehicle signatures
private _candidates = [];

// 1. Full squad target acquisition (all squad members, leadership nearTargets, and active squad combat enemies)
if (!isNull _opGrp) then {
    {
        if (alive _x) then {
            _candidates append (_x targets [true, _range]);
            private _ne = _x findNearestEnemy _x;
            if (!isNull _ne) then { _candidates pushBackUnique (vehicle _ne); };
        };
    } forEach (units _opGrp);

    private _leader = leader _opGrp;
    if (!isNull _leader) then {
        {
            private _tObj = _x select 4;
            if (!isNull _tObj && {alive _tObj}) then {
                _candidates pushBackUnique (vehicle _tObj);
            };
        } forEach (_leader nearTargets _range);
    };
} else {
    if (!isNull _operator && {_operator isKindOf "Man"}) then {
        _candidates append (_operator targets [true, _range]);
        private _ne = _operator findNearestEnemy _operator;
        if (!isNull _ne) then { _candidates pushBackUnique (vehicle _ne); };
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
    // Infantry detection within configured search range
    private _nearInfantry = (getPosATL _uav) nearEntities ["CAManBase", _range];
    _candidates append _nearInfantry;
} else {
    if (!isNull _operator && {_operator isKindOf "Man"}) then {
        // Ground operator scans vehicles within threat range
        private _nearVehicles = (getPosATL _operator) nearEntities [["LandVehicle", "Ship", "Air"], _range];
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
        private _isDrone = (_v isKindOf "UAV") || {unitIsUAV _v} || {_v getVariable ["CLDW_IsDroneCrew", false]};
        if (!_isDrone && {_v != _uav}) then {
            private _isInfantry = _v isKindOf "CAManBase";
            private _isVehicle = (_v isKindOf "LandVehicle") || (_v isKindOf "Ship") || (_v isKindOf "Air") || (_v isKindOf "StaticWeapon");

            // Ignore anything that is neither infantry nor a recognized vehicle type
            if (!_isInfantry && !_isVehicle) then { continue; };

            private _aliveCrew = if (_isVehicle) then { (crew _v) select { alive _x } } else { [] };

            // Ignore empty/neutral vehicles and static weapon proxies without active crew
            if (_isVehicle && {count _aliveCrew == 0}) then {
                private _prioritizeDismounted = missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true];
                if (_prioritizeDismounted) then {
                    private _nearDismounted = (getPosATL _v) nearEntities ["CAManBase", 75];
                    {
                        private _cand = _x;
                        if (alive _cand && {!(_cand in _uniqueTargets)}) then {
                            _uniqueTargets pushBack _cand;
                        };
                    } forEach _nearDismounted;
                };
                continue; // Strictly NEVER target empty vehicles or unmanned static proxies
            };

            // Determine target side safely
            private _vSide = sideUnknown;
            if (_isInfantry) then {
                private _grp = group _v;
                _vSide = if (!isNull _grp) then { side _grp } else { side _v };
            } else {
                if (count _aliveCrew > 0) then {
                    private _cUnit = _aliveCrew select 0;
                    private _grp = group _cUnit;
                    _vSide = if (!isNull _grp) then { side _grp } else { side _cUnit };
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
                    private _prioritizeDismounted = missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true];
                    if (_isInfantry) then {
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

                        // 1. Check if target is actively spotted or engaged by the squad
                        private _isSquadTarget = (!isNull _opGrp && { _opGrp knowsAbout _v >= 0.8 }) ||
                                                (!isNull _operator && { _operator knowsAbout _v >= 0.8 });

                        private _checkStart = _eyeStart;
                        if (!isNull _uav) then {
                            // Drone climbs to 70m approach altitude upon launch; evaluate terrain LOS from vantage height
                            private _uavATL = getPosATL _uav;
                            private _climbNeeded = (70 - (_uavATL select 2)) max 0;
                            _checkStart = (getPosASL _uav) vectorAdd [0, 0, _climbNeeded min 50];
                        };

                        // 2. Terrain occlusion check
                        private _losBlocked = terrainIntersectASL [_checkStart, _eyeEnd];
                        if (!_losBlocked) then {
                            private _ignore1 = if (!isNull _uav) then { _uav } else { _operator };
                            private _intersections = lineIntersectsSurfaces [_checkStart, _eyeEnd, _ignore1, _v, true, 1, "VIEW", "GEOM"];
                            if (count _intersections > 0) then {
                                private _hitObj = (_intersections select 0) select 2;
                                if (!isNull _hitObj && {_hitObj isKindOf "Building" || _hitObj isKindOf "House" || _hitObj isKindOf "Wall"}) then {
                                    _losBlocked = true;
                                };
                            };
                            if (!_losBlocked && !_isSquadTarget) then {
                                private _vis = [_ignore1, "VIEW", _v] checkVisibility [_checkStart, _eyeEnd];
                                if (_vis < 0.05) then {
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
            private _isDismounted = (_x isKindOf "CAManBase") && {
                (!isNull (assignedVehicle _x)) || 
                { count ((getPosATL _x) nearEntities [["LandVehicle", "Ship", "Air"], 75]) > 0 }
            };
            private _dismountBonus = if (_isDismounted && {missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true]}) then { -150 } else { 0 };
            private _score = _d + _dismountBonus;
            if (_score < _minDist) then {
                _minDist = _score;
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
