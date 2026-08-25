params [["_man", objNull], ["_rangeInput", 2000]];

// If _man is a group, resolve it to the group leader unit
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

private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500];
private _range = _maxRangeSetting;
if (!isNil "_rangeInput" && { _rangeInput isEqualType 0 } && { _rangeInput > 0 }) then {
    _range = _rangeInput min (round _maxRangeSetting);
};

private _opGrp = if (!isNull _operator && {_operator isKindOf "Man"}) then { group _operator } else { grpNull };
private _manSide = if (!isNull _opGrp) then { side _opGrp } else { side _operator };
if (_manSide == sideUnknown && {!isNull _uav}) then {
    private _uavGrp = group (driver _uav);
    if (!isNull _uavGrp) then { _manSide = side _uavGrp; } else { _manSide = side _uav; };
};
if (_manSide == sideUnknown) then { _manSide = civilian; };

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

private _out = [];

{
    private _v = _x;
    if (alive _v) then {
        private _isDrone = (_v isKindOf "UAV") || {unitIsUAV _v} || {_v getVariable ["CLDW_IsDroneCrew", false]} || {_v getVariable ["USED", false]};
        if (!_isDrone) then {
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
                    private _vPosATL = getPosATL _v;
                    private _isGroundTarget = if (_v isKindOf "Ship") then {
                        true
                    } else {
                        (_vPosATL select 2) < 5 || isTouchingGround _v
                    };

                    if (_isGroundTarget) then {
                        private _isSoftTarget = false;
                        if (_v isKindOf "CAManBase") then {
                            _isSoftTarget = true;
                        } else {
                            private _armor = getNumber (configFile >> "CfgVehicles" >> (typeOf _v) >> "armor");
                            private _isSoftVehicle = (_v isKindOf "Car") || {_v isKindOf "Truck"} || {_v isKindOf "Motorcycle"} || {_v isKindOf "Ship"} || {_armor <= (_threshold max 150)};
                            private _isHeavyArmor = (_v isKindOf "Tank") || {_v isKindOf "APC"} || {_v isKindOf "Wheeled_APC_F"};
                            if (_isSoftVehicle && !_isHeavyArmor) then {
                                _isSoftTarget = true;
                            };
                        };

                        if (_isSoftTarget) then {
                            private _eyeStart = if (!isNull _uav) then {
                                (getPosASL _uav) vectorAdd [0, 0, 0.5]
                            } else {
                                eyePos _operator
                            };
                            if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _operator) vectorAdd [0,0,1.5]; };

                            private _eyeEnd = if (_v isKindOf "CAManBase") then {
                                eyePos _v
                            } else {
                                (getPosASL _v) vectorAdd [0, 0, 1.0]
                            };
                            if (_eyeEnd isEqualTo [0,0,0]) then { _eyeEnd = (getPosASL _v) vectorAdd [0,0,1.2]; };

                            private _losBlocked = terrainIntersectASL [_eyeStart, _eyeEnd];
                            if (!_losBlocked) then {
                                private _ignore1 = if (!isNull _uav) then { _uav } else { _operator };
                                private _intersections = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _ignore1, _v, true, 1, "VIEW", "GEOM"];
                                if (count _intersections > 0) then {
                                    private _hitObj = (_intersections select 0) select 2;
                                    if (!isNull _hitObj && { _hitObj isKindOf "Building" || _hitObj isKindOf "House" || _hitObj isKindOf "Wall" }) then {
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
