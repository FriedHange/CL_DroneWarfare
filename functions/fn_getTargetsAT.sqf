params [["_man", objNull], ["_rangeInput", 2000]];

// If _man is a group, resolve it to the group leader unit
if (_man isEqualType grpNull) then { _man = leader _man; };
if (isNull _man) exitWith { [] };

// If _man is a vehicle (e.g. UAV itself), resolve it to its crew or driver
if (_man isKindOf "AllVehicles" && {!(_man isKindOf "Man")}) then {
    private _crew = crew _man;
    if (count _crew > 0) then {
        _man = _crew select 0;
    } else {
        _man = driver _man;
    };
};
if (isNull _man) exitWith { [] };

private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500];
private _range = _maxRangeSetting;
if (!isNil "_rangeInput" && { _rangeInput isEqualType 0 }) then {
    _range = _rangeInput min (round _maxRangeSetting);
};
DDT_fnc_getTargetsAT_version = 3;

missionNamespace setVariable ["ddtCooldownValue", 0, true];
missionNamespace setVariable ["ddtCycleAttack", 5, true];

private _man_side = side _man;
private _uav = objNull;
if (vehicle _man != _man) then {
    _uav = vehicle _man;
} else {
    _uav = getConnectedUAV _man;
};

if (isNull _uav) then {
    private _manStr = str _man;
    private _nearUAVs = vehicles select { 
        (_x isKindOf "UAV" || _x isKindOf "Air") && 
        { (_x getVariable ["ddtOwner", ""]) == _manStr } 
    };
    if (count _nearUAVs > 0) then {
        _uav = _nearUAVs select 0;
    };
};
private _isAPDrone = false;

if (!isNull _uav) then {
    private _uavClass = typeOf _uav;
    if (_uavClass == "B_Crocus_AP_F" || _uavClass == "O_Crocus_AP_F" || _uavClass == "I_Crocus_AP_F" || ["_AP_", _uavClass] call BIS_fnc_inString || ["UAFPV_IED_AP", _uavClass] call BIS_fnc_inString || ["UAFPV_OG7V_AP", _uavClass] call BIS_fnc_inString || ["UAFPV_RKG_AP", _uavClass] call BIS_fnc_inString) then {
        _isAPDrone = true;
    };
};

private _rawTargets = _man targets [true, _range];
private _validTargets = [];

{
    private _t = vehicle _x;
    if ((_man distance _t) <= _range && { (side _t) getFriend _man_side < 0.6 }) then {
        // Line of sight check from operator or UAV
        private _hasLOS = false;
        private _eyeStart = eyePos _man;
        if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _man) vectorAdd [0,0,1.5]; };
        if (!isNull _uav) then { 
            _eyeStart = eyePos _uav; 
            if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _uav) vectorAdd [0,0,0.5]; }; 
        };
        private _eyeEnd = eyePos _t;
        if (_eyeEnd isEqualTo [0,0,0]) then { _eyeEnd = (getPosASL _t) vectorAdd [0,0,1]; };
        
        private _blocked = terrainIntersectASL [_eyeStart, _eyeEnd] || {
            private _intersections = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _uav, _t, true, 1, "VIEW", "FIRE"];
            count _intersections > 0
        };
        
        if (!_blocked) then {
            if (_isAPDrone) then {
                if (_t isKindOf "MAN") then { _validTargets pushBackUnique _t; };
            } else {
                if (_t isKindOf "Tank" || _t isKindOf "Car" || _t isKindOf "Wheeled_APC_F") then {
                    if (isTouchingGround _t) then { _validTargets pushBackUnique _t; };
                };
            };
        };
    };
} forEach _rawTargets;

// EMERGENCY FALLBACK
if (_validTargets isEqualTo []) then {
    _validTargets = _rawTargets select {
        private _t = vehicle _x;
        if ((_man distance _t) <= _range && { ((side _t) getFriend _man_side < 0.6) && {isTouchingGround _t || _t isKindOf "MAN"} }) then {
            // Apply same LOS check for fallback targets to prevent cheating
            private _eyeStart = eyePos _man;
            if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _man) vectorAdd [0,0,1.5]; };
            if (!isNull _uav) then { 
                _eyeStart = eyePos _uav; 
                if (_eyeStart isEqualTo [0,0,0]) then { _eyeStart = (getPosASL _uav) vectorAdd [0,0,0.5]; }; 
            };
            private _eyeEnd = eyePos _t;
            if (_eyeEnd isEqualTo [0,0,0]) then { _eyeEnd = (getPosASL _t) vectorAdd [0,0,1]; };
            
            !(terrainIntersectASL [_eyeStart, _eyeEnd]) && {
                private _intersections = lineIntersectsSurfaces [_eyeStart, _eyeEnd, _uav, _t, true, 1, "VIEW", "FIRE"];
                (count _intersections) isEqualTo 0
            }
        } else {
            false
        };
    };
};

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

private _closestTarget = objNull;
private _minDist = 999999;
{
    private _d = _man distance _x;
    if (_d < _minDist) then {
        _minDist = _d;
        _closestTarget = _x;
    };
} forEach _validTargets;

if (isNull _closestTarget) exitWith { [] };

_man reveal [_closestTarget, 4];

if (!isNull _uav) then {
    _uav reveal [_closestTarget, 4];
    _uav doWatch _closestTarget;
    
    // Store target on UAV for tracking checks in Move and GuideToTarget
    _uav setVariable ["CLDW_CurrentTarget", _closestTarget, true];
    _uav setVariable ["CLDW_CurrentOperator", _man, true];
    
    if (CLDW_Setting_ForceDirectMove) then {
        private _targetPos = getPosATL _closestTarget;
        if !(_targetPos isEqualTo [0,0,0]) then {
            (group _uav) setBehaviour "COMBAT";
            if (_isAPDrone) then {
                _uav flyInHeightASL [35, 35, 35];
            } else {
                _uav flyInHeightASL [45, 45, 45];
            };
            (driver _uav) doMove _targetPos;
        };
    };
};

[_closestTarget]