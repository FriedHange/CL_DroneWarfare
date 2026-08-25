params [["_man", objNull], ["_rangeInput", 2000]];

// If _man is a group, resolve it to the group leader unit
if (_man isEqualType grpNull) then { _man = leader _man; };
if (isNull _man) exitWith { [] };

private _operator = objNull;
private _uav = objNull;

// Resolve _uav and _operator from _man
if (_man isKindOf "AllVehicles" && {!(_man isKindOf "Man")}) then {
    // _man was passed as the UAV object
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
    // _man is a unit (either operator or UAV pilot)
    if (vehicle _man != _man) then {
        _uav = vehicle _man;
        _operator = _uav getVariable ["CLDW_CurrentOperator", _man];
    } else {
        _operator = _man;
        // Find UAV associated with _operator
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

private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500];
private _range = _maxRangeSetting;
if (!isNil "_rangeInput" && { _rangeInput isEqualType 0 } && { _rangeInput > 0 }) then {
    _range = _rangeInput min (round _maxRangeSetting);
};

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
        ("rc40_he" in _uavClass) ||
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
        if (("uafpv" in _uavClass) && !("_at" in _uavClass) && !("pg7" in _uavClass)) then {
            _isAPDrone = true;
        };
    };
} else {
    // If UAV is null, check operator backpack or ratio
    private _bp = toLower (backpack _operator);
    if (("_ap" in _bp) || ("rkg" in _bp) || ("og7v" in _bp) || ("frag" in _bp)) then {
        _isAPDrone = true;
    };
};

private _atTargetsInfantry = missionNamespace getVariable ["CLDW_Setting_ATTargetsInfantry", false];
private _threshold = missionNamespace getVariable ["ddtSoftThreshold", 100];

// Gather all raw potential target candidates
private _candidates = [];

// 1. Perceived targets from operator / squad
if (!isNull _operator && {_operator isKindOf "Man"}) then {
    _candidates append (_operator targets [true, _range]);
    if (!isNull (leader group _operator) && {leader group _operator != _operator}) then {
        _candidates append ((leader group _operator) targets [true, _range]);
    };
};

// 2. Perceived targets from UAV pilot
if (!isNull _uav) then {
    private _pilot = driver _uav;
    if (!isNull _pilot) then {
        _candidates append (_pilot targets [true, _range]);
    };
    // 3. Physical near entities around the drone's position
    private _nearAroundUAV = (getPosATL _uav) nearEntities [["CAManBase", "LandVehicle", "Ship"], _range];
    _candidates append _nearAroundUAV;
} else {
    if (!isNull _operator && {_operator isKindOf "Man"}) then {
        private _nearAroundOp = (getPosATL _operator) nearEntities [["CAManBase", "LandVehicle", "Ship"], _range];
        _candidates append _nearAroundOp;
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
        // Exclude drones, virtual drone crew, and decorative units
        private _isDrone = (_t isKindOf "UAV") || {unitIsUAV _t} || {_t getVariable ["CLDW_IsDroneCrew", false]} || {_t getVariable ["USED", false]};
        if (!_isDrone) then {
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

            // Check if hostile
            private _isHostile = false;
            if (_tSide != civilian && {_tSide != sideUnknown} && {_tSide != sideLogic}) then {
                _isHostile = ([_manSide, _tSide] call BIS_fnc_areFriendly) isEqualTo false || 
                             { (_manSide getFriend _tSide < 0.6) || (_tSide getFriend _manSide < 0.6) };
            };

            if (_isHostile) then {
                private _dist = if (!isNull _uav) then { _uav distance _t } else { _operator distance _t };
                if (_dist <= _range) then {
                    // Check altitude/ground validity (exclude airborne planes/helicopters)
                    private _tPosATL = getPosATL _t;
                    private _isGroundTarget = if (_t isKindOf "Ship") then {
                        true
                    } else {
                        (_tPosATL select 2) < 5 || isTouchingGround _t
                    };

                    if (_isGroundTarget) then {
                        // Check payload suitability
                        private _isTargetValidType = false;
                        private _isInfantry = _t isKindOf "CAManBase";
                        private _isVehicle = (_t isKindOf "LandVehicle") || (_t isKindOf "Ship");

                        if (_isAPDrone) then {
                            if (_isInfantry) then {
                                _isTargetValidType = true;
                            } else {
                                if (_isVehicle) then {
                                    private _armor = getNumber (configFile >> "CfgVehicles" >> (typeOf _t) >> "armor");
                                    private _isSoft = (_t isKindOf "Car") || {_t isKindOf "Truck"} || {_t isKindOf "Motorcycle"} || {_t isKindOf "Ship"} || {_armor <= (_threshold max 150)};
                                    private _isHeavy = (_t isKindOf "Tank") || {_t isKindOf "APC"} || {_t isKindOf "Wheeled_APC_F"};
                                    if (_isSoft && !_isHeavy) then {
                                        _isTargetValidType = true;
                                    };
                                };
                            };
                        } else {
                            // AT Drone
                            if (_isVehicle) then {
                                _isTargetValidType = true;
                            } else {
                                if (_isInfantry && _atTargetsInfantry) then {
                                    _isTargetValidType = true;
                                };
                            };
                        };

                        if (_isTargetValidType) then {
                            // Line of sight check
                            private _eyeStart = if (!isNull _uav) then {
                                (getPosASL _uav) vectorAdd [0, 0, 0.5]
                            } else {
                                eyePos _operator
                            };
                            if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _operator) vectorAdd [0,0,1.5]; };

                            private _eyeEnd = if (_isInfantry) then {
                                eyePos _t
                            } else {
                                (getPosASL _t) vectorAdd [0, 0, 1.0]
                            };
                            if (_eyeEnd isEqualTo [0,0,0]) then { _eyeEnd = (getPosASL _t) vectorAdd [0,0,1.2]; };

                            private _losBlocked = terrainIntersectASL [_eyeStart, _eyeEnd];
                            if (!_losBlocked) then {
                                private _ignore1 = if (!isNull _uav) then { _uav } else { _operator };
                                private _intersections = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _ignore1, _t, true, 1, "VIEW", "GEOM"];
                                if (count _intersections > 0) then {
                                    private _hitObj = (_intersections select 0) select 2;
                                    if (!isNull _hitObj && { _hitObj isKindOf "Building" || _hitObj isKindOf "House" || _hitObj isKindOf "Wall" }) then {
                                        _losBlocked = true;
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
    };
} forEach _uniqueTargets;

if (_validTargets isEqualTo []) exitWith {
    if (!isNull _uav && {alive _uav}) then {
        private _uavAlt = (getPosATL _uav) select 2;
        private _uavSpeed = speed _uav;
        if (_uavAlt < 3 && _uavSpeed < 2) then {
            private _launchPos = (getPosATL _uav) vectorAdd [0, 0, 50];
            _uav flyInHeightASL [50, 50, 50];
            private _cruiseSpeed = (missionNamespace getVariable ["CLDW_Setting_CruiseSpeed", 85]) / 3.6;
            _uav forceSpeed _cruiseSpeed;
            (driver _uav) doMove _launchPos;
        };
    };
    []
};

// Select closest target from UAV (or operator)
private _closestTarget = objNull;
private _minDist = 999999;
private _refPos = if (!isNull _uav) then { getPosASL _uav } else { getPosASL _operator };

{
    private _d = _refPos distance (getPosASL _x);
    if (_d < _minDist) then {
        _minDist = _d;
        _closestTarget = _x;
    };
} forEach _validTargets;

if (isNull _closestTarget) exitWith { [] };

if (!isNull _operator && {_operator isKindOf "Man"}) then {
    _operator reveal [_closestTarget, 4];
};

if (!isNull _uav) then {
    _uav reveal [_closestTarget, 4];
    _uav doWatch _closestTarget;
    
    _uav setVariable ["CLDW_CurrentTarget", _closestTarget, true];
    _uav setVariable ["CLDW_CurrentOperator", _operator, true];
    
    private _targetPos = getPosATL _closestTarget;
    if !(_targetPos isEqualTo [0,0,0]) then {
        (group (driver _uav)) setBehaviour "COMBAT";
        if (_isAPDrone) then {
            _uav flyInHeightASL [35, 35, 35];
        } else {
            _uav flyInHeightASL [45, 45, 45];
        };
        (driver _uav) doMove _targetPos;
    };
};

[_closestTarget]