/*
    File: fn_getTargetsAT.sqf
    Author: Carl Lorenzo
    Description:
        Target acquisition for anti-tank and combat drones.
        Features:
        1. Unified speed integration.
        2. Supports moving ground vehicles, naval craft, and hostile air targets (helicopters/aircraft).
        3. Strict anti-wallhack raycast LOS checks against terrain and building structures.
        4. Automatic infantry fallback for AT drones when no hostile vehicles are available.
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

DDT_fnc_getTargetsAT_version = 3;
missionNamespace setVariable ["ddtCooldownValue", 0, true];
missionNamespace setVariable ["ddtCycleAttack", 5, true];

// Determine combat side
private _opGrp = if (!isNull _operator && {_operator isKindOf "Man"}) then { group _operator } else { grpNull };
private _manSide = if (!isNull _opGrp) then { side _opGrp } else { side _operator };
if (_manSide == sideUnknown && {!isNull _uav}) then {
    private _uavGrp = group (driver _uav);
    if (!isNull _uavGrp) then { _manSide = side _uavGrp; } else { _manSide = side _uav; };
};
if (_manSide == sideUnknown) then { _manSide = civilian; };

// Determine drone payload (AP vs AT)
private _isAPDrone = false;
if (!isNull _uav) then {
    private _uavClass = toLower (typeOf _uav);
    if (
        ("_ap" in _uavClass) || 
        ("rkg" in _uavClass) || 
        ("og7v" in _uavClass) || 
        ("rc40" in _uavClass) || 
        ("rc-40" in _uavClass) || 
        ("_he" in _uavClass) ||
        ("frag" in _uavClass) ||
        ("personnel" in _uavClass) ||
        ("crocus_ap" in _uavClass) ||
        ("kvn_ap" in _uavClass)
    ) then {
        if (!("_at" in _uavClass) && !("pg7" in _uavClass)) then {
            _isAPDrone = true;
        };
    } else {
        if (("uafpv" in _uavClass || "fpv" in _uavClass) && !("_at" in _uavClass) && !("pg7" in _uavClass)) then {
            _isAPDrone = true;
        };
    };
} else {
    private _bp = toLower (backpack _operator);
    if (("_ap" in _bp) || ("rkg" in _bp) || ("og7v" in _bp) || ("frag" in _bp)) then {
        _isAPDrone = true;
    };
};

private _atTargetsInfantry = missionNamespace getVariable ["CLDW_Setting_ATTargetsInfantry", false];
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

// Deduplicate candidate objects
private _uniqueTargets = [];
{
    private _veh = vehicle _x;
    if (!isNull _veh && {!(_veh in _uniqueTargets)}) then {
        _uniqueTargets pushBack _veh;
    };
} forEach _candidates;

private _validTargets = [];

{
    private _t = _x;
    if (alive _t) then {
        private _isDrone = (_t isKindOf "UAV") || {unitIsUAV _t} || {_t getVariable ["CLDW_IsDroneCrew", false]} || {_t getVariable ["USED", false]};
        if (!_isDrone && {_t != _uav}) then {
            // Determine target side
            private _tSide = sideUnknown;
            if (_t isKindOf "CAManBase") then {
                _tSide = side (group _t);
            } else {
                private _crew = crew _t;
                if (count _crew > 0) then {
                    _tSide = side (group (_crew select 0));
                } else {
                    _tSide = side _t;
                };
            };

            // Check hostility
            private _isHostile = false;
            if (_tSide != civilian && {_tSide != sideUnknown} && {_tSide != sideLogic}) then {
                _isHostile = ([_manSide, _tSide] call BIS_fnc_areFriendly) isEqualTo false || 
                             { (_manSide getFriend _tSide < 0.6) || (_tSide getFriend _manSide < 0.6) };
            };

            if (_isHostile) then {
                private _dist = if (!isNull _uav) then { _uav distance _t } else { _operator distance _t };
                if (_dist <= _range) then {
                    private _isInfantry = _t isKindOf "CAManBase";
                    // Support land, naval, and airborne vehicles (helicopters / planes)
                    private _isVehicle = (_t isKindOf "LandVehicle") || (_t isKindOf "Ship") || (_t isKindOf "Air");
                    private _prioritizeDismounted = missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true];
                    private _aliveCrew = if (_isVehicle) then { (crew _t) select { alive _x } } else { [] };
                    private _isEmptyVehicle = _isVehicle && {(count _aliveCrew) == 0};

                    // If vehicle is empty, search around it for dismounted passengers / hostiles and queue them
                    if (_isEmptyVehicle && _prioritizeDismounted) then {
                        private _nearDismounted = (getPosATL _t) nearEntities ["CAManBase", 75];
                        {
                            private _cand = _x;
                            if (alive _cand && {!(_cand in _uniqueTargets)}) then {
                                _uniqueTargets pushBack _cand;
                            };
                        } forEach _nearDismounted;
                    };

                    private _isTargetValidType = false;

                    if (_isAPDrone) then {
                        if (_isInfantry) then {
                            _isTargetValidType = true;
                        } else {
                            if (_isVehicle && !(_isEmptyVehicle && _prioritizeDismounted)) then {
                                private _armor = getNumber (configFile >> "CfgVehicles" >> (typeOf _t) >> "armor");
                                private _isSoft = (_t isKindOf "Car") || {_t isKindOf "Truck"} || {_t isKindOf "Motorcycle"} || {_t isKindOf "Ship"} || {_t isKindOf "Air"} || {_armor <= (_threshold max 150)};
                                private _isHeavy = (_t isKindOf "Tank") || {_t isKindOf "APC"} || {_t isKindOf "Wheeled_APC_F"};
                                if (_isSoft && !_isHeavy) then {
                                    _isTargetValidType = true;
                                };
                            };
                        };
                    } else {
                        // AT Drone: combat vehicles with crew are primary; empty vehicles are excluded if setting enabled
                        if (_isVehicle && !(_isEmptyVehicle && _prioritizeDismounted)) then {
                            _isTargetValidType = true;
                        } else {
                            // Dismounted passengers from combat vehicles are valid targets for AT drones
                            private _isDismounted = _isInfantry && {
                                (!isNull (assignedVehicle _t)) || 
                                { count ((getPosATL _t) nearEntities [["LandVehicle", "Ship", "Air"], 75]) > 0 }
                            };
                            if (_isInfantry && (_atTargetsInfantry || (_prioritizeDismounted && _isDismounted))) then {
                                _isTargetValidType = true;
                            };
                        };
                    };

                    // Antistasi Petros / Rebel HQ Commander Protection
                    private _isPetros = (_t == (missionNamespace getVariable ["petros", objNull])) ||
                                        {_t getVariable ["isPetros", false]} ||
                                        {(toLower (name _t)) find "petros" > -1};
                    if (_isPetros) then {
                        // In Antistasi, Petros is the rebel commander at the secret HQ.
                        // He must never be targeted by ambient FPV drones unless an enemy squad has direct, close-quarters confirmed contact.
                        private _opGrp = if (!isNull _operator && {_operator isKindOf "Man"}) then { group _operator } else { grpNull };
                        private _knowsAbout = if (!isNull _opGrp) then { _opGrp knowsAbout _t } else { 0 };
                        if (_dist > 400 || _knowsAbout < 1.5) then {
                            _isTargetValidType = false;
                        };
                    };

                    if (_isTargetValidType) then {
                        // Strict Raycast LOS & Engine Visibility validation (anti-wallhack & foliage check)
                        private _eyeStart = if (!isNull _uav) then {
                            (getPosASL _uav) vectorAdd [0, 0, 0.4]
                        } else {
                            eyePos _operator
                        };
                        if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _operator) vectorAdd [0,0,1.5]; };

                        private _eyeEnd = if (_isInfantry) then {
                            eyePos _t
                        } else {
                            (getPosASL _t) vectorAdd [0, 0, 0.8]
                        };
                        if (_eyeEnd isEqualTo [0,0,0]) then { _eyeEnd = (getPosASL _t) vectorAdd [0,0,1.0]; };

                        // 1. Check if target is actively spotted or engaged by the squad
                        private _isSquadTarget = (!isNull _opGrp && { _opGrp knowsAbout _t >= 0.8 }) ||
                                                (!isNull _operator && { _operator knowsAbout _t >= 0.8 });

                        private _checkStart = _eyeStart;
                        if (_isSquadTarget && {!isNull _uav}) then {
                            // Drone climbs to 70m approach altitude upon launch; evaluate terrain LOS from vantage height
                            private _uavATL = getPosATL _uav;
                            private _climbNeeded = (70 - (_uavATL select 2)) max 0;
                            _checkStart = (getPosASL _uav) vectorAdd [0, 0, _climbNeeded min 50];
                        };

                        // 2. Terrain occlusion check
                        private _losBlocked = terrainIntersectASL [_checkStart, _eyeEnd];
                        if (!_losBlocked) then {
                            private _ignore1 = if (!isNull _uav) then { _uav } else { _operator };
                            if (_isSquadTarget) then {
                                private _intersections = lineIntersectsSurfaces [_checkStart, _eyeEnd, _ignore1, _t, true, 1, "VIEW", "GEOM"];
                                if (count _intersections > 0) then {
                                    private _hitObj = (_intersections select 0) select 2;
                                    if (!isNull _hitObj && {_hitObj isKindOf "Building" || _hitObj isKindOf "House" || _hitObj isKindOf "Wall"}) then {
                                        _losBlocked = true;
                                    };
                                };
                            } else {
                                // Direct visibility check for ambient unspotted targets
                                private _vis = [_ignore1, "VIEW", _t] checkVisibility [_eyeStart, _eyeEnd];
                                if (_vis < 0.2) then {
                                    _losBlocked = true;
                                } else {
                                    private _intersections = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _ignore1, _t, true, 1, "VIEW", "GEOM"];
                                    if (count _intersections > 0) then {
                                        _losBlocked = true;
                                    };
                                };
                            };
                        };

                        if (!_losBlocked) then {
                            _validTargets pushBackUnique _t;
                        };
                    };
                };
            };
        };
    };
} forEach _uniqueTargets;

// Fallback for AT drones when no enemy vehicles are found: engage infantry with strict LOS check
if (!_isAPDrone && _validTargets isEqualTo []) then {
    {
        private _t = _x;
        if (alive _t && {_t isKindOf "CAManBase"}) then {
            private _isDrone = (_t getVariable ["CLDW_IsDroneCrew", false]) || {_t getVariable ["USED", false]};
            if (!_isDrone) then {
                private _isPetros = (_t == (missionNamespace getVariable ["petros", objNull])) ||
                                    {_t getVariable ["isPetros", false]} ||
                                    {(toLower (name _t)) find "petros" > -1};
                private _tSide = side (group _t);
                private _isHostile = (_tSide != civilian && {_tSide != sideUnknown} && {_tSide != sideLogic}) && 
                                     { ([_manSide, _tSide] call BIS_fnc_areFriendly) isEqualTo false || { (_manSide getFriend _tSide < 0.6) || (_tSide getFriend _manSide < 0.6) } };
                if (_isHostile && !_isPetros) then {
                    private _dist = if (!isNull _uav) then { _uav distance _t } else { _operator distance _t };
                    if (_dist <= _range) then {
                        private _eyeStart = if (!isNull _uav) then { (getPosASL _uav) vectorAdd [0,0,0.4] } else { eyePos _operator };
                        private _eyeEnd = eyePos _t;
                        private _isSquadTarget = (!isNull _opGrp && { _opGrp knowsAbout _t >= 0.8 }) ||
                                                (!isNull _operator && { _operator knowsAbout _t >= 0.8 });
                        private _checkStart = _eyeStart;
                        if (_isSquadTarget && {!isNull _uav}) then {
                            private _uavATL = getPosATL _uav;
                            private _climbNeeded = (70 - (_uavATL select 2)) max 0;
                            _checkStart = (getPosASL _uav) vectorAdd [0, 0, _climbNeeded min 50];
                        };
                        if (!terrainIntersectASL [_checkStart, _eyeEnd]) then {
                            private _ignore1 = if (!isNull _uav) then { _uav } else { _operator };
                            if (_isSquadTarget) then {
                                private _hits = lineIntersectsSurfaces [_checkStart, _eyeEnd, _ignore1, _t, true, 1, "VIEW", "GEOM"];
                                if (count _hits == 0) then {
                                    _validTargets pushBackUnique _t;
                                };
                            } else {
                                private _vis = [_ignore1, "VIEW", _t] checkVisibility [_eyeStart, _eyeEnd];
                                if (_vis >= 0.2) then {
                                    private _hits = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _ignore1, _t, true, 1, "VIEW", "GEOM"];
                                    if (count _hits == 0) then {
                                        _validTargets pushBackUnique _t;
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };
    } forEach _uniqueTargets;
};

if (_validTargets isEqualTo []) exitWith {
    if (!isNull _uav && {alive _uav}) then {
        private _uavAlt = (getPosATL _uav) select 2;
        private _uavSpeed = speed _uav;
        if (_uavAlt < 3 && _uavSpeed < 2) then {
            private _launchPos = (getPosATL _uav) vectorAdd [0, 0, 45];
            _uav flyInHeight 45;
            private _speed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6;
            _uav forceSpeed _speed;
            (driver _uav) doMove _launchPos;
        };
    };
    []
};

// Select optimal target with deconfliction penalty so multiple drones distribute among different enemies
private _selectedTarget = objNull;
private _bestScore = 999999;
private _refPos = if (!isNull _uav) then { getPosASL _uav } else { getPosASL _operator };

{
    private _d = _refPos distance (getPosASL _x);
    // Deconfliction: if another active drone is already hunting this target, add a 400m distance penalty
    private _assignedDrone = _x getVariable ["CLDW_AssignedDrone", objNull];
    private _penalty = if (!isNull _assignedDrone && {alive _assignedDrone} && {_assignedDrone != _uav}) then { 400 } else { 0 };

    // Dismounted priority bonus: prioritize dismounted passengers and crew
    private _isDismounted = (_x isKindOf "CAManBase") && {
        (!isNull (assignedVehicle _x)) || 
        { count ((getPosATL _x) nearEntities [["LandVehicle", "Ship", "Air"], 75]) > 0 }
    };
    private _dismountBonus = if (_isDismounted && {missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true]}) then { -150 } else { 0 };
    private _score = _d + _penalty + _dismountBonus;

    if (_score < _bestScore) then {
        _bestScore = _score;
        _selectedTarget = _x;
    };
} forEach _validTargets;

if (isNull _selectedTarget) exitWith { [] };

if (!isNull _operator && {_operator isKindOf "Man"}) then {
    _operator reveal [_selectedTarget, 4];
};

if (!isNull _uav) then {
    _uav reveal [_selectedTarget, 4];
    _uav doWatch _selectedTarget;
    
    _selectedTarget setVariable ["CLDW_AssignedDrone", _uav, true];
    _uav setVariable ["CLDW_CurrentTarget", _selectedTarget, true];
    _uav setVariable ["CLDW_CurrentOperator", _operator, true];
};

[_selectedTarget]
