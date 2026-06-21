params [["_drone", objNull], ["_target", objNull], ["_speed", 20], ["_minDistanceToTarget", 0.1]];

if (isNull _drone || {isNull _target}) exitWith {};

private _AP = false;
private _crocus = false;
private _crocusAP = [
    "B_KVN_AP", "O_KVN_AP", "I_KVN_AP", "B_KVN_AP_TI", "O_KVN_AP_TI", "I_KVN_AP_TI",
    "B_CROCUS_AP", "O_CROCUS_AP", "I_CROCUS_AP", "B_CROCUS_AP_TI", "O_CROCUS_AP_TI", "I_CROCUS_AP_TI"
];
private _crocusAT = [
    "B_KVN_AT", "O_KVN_AT", "I_KVN_AT", "B_KVN_AT_TI", "O_KVN_AT_TI", "I_KVN_AT_TI",
    "B_CROCUS_AT", "O_CROCUS_AT", "I_CROCUS_AT", "B_CROCUS_AT_TI", "O_CROCUS_AT_TI", "I_CROCUS_AT_TI"
];

private _droneSpeedSetting = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 125]) / 3.6;
if ((toUpper (typeOf _drone)) in _crocusAT) then {
    _crocus = true;
    _speed = _droneSpeedSetting;
};
if ((toUpper (typeOf _drone)) in _crocusAP) then {
    _crocus = true;
    _AP = true;
    _speed = _droneSpeedSetting;
    _minDistanceToTarget = 1;
};
if (_speed < _droneSpeedSetting) then {
    _speed = _droneSpeedSetting;
};

if (missionNamespace getVariable ["ddtDebug", false]) then {
    systemChat format ["FPV attack speed: %1", _speed];
};

private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
if (isNull _opGrp && {!isNull _man}) then {
    _opGrp = group _man;
};
if (isNull _man || {!alive _man}) then {
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

// Split drone crew from the operator group to prevent setting behavior/combat mode on the operator's group
private _droneCrew = crew _drone;
private _tempGrp = grpNull;
private _hasSplitGroup = false;

if (count _droneCrew > 0) then {
    private _originalGrp = group (_droneCrew select 0);
    if (!isNull _opGrp && {_originalGrp == _opGrp}) then {
        _tempGrp = createGroup (side _drone);
        _tempGrp setVariable ["daoExclude", true, true];
        _tempGrp setVariable ["dceExclude", true, true];
        _tempGrp setVariable ["Vcm_Disable", true, true];
        _droneCrew joinSilent _tempGrp;
        _hasSplitGroup = true;
    };
};

_drone setCombatMode "BLUE";
_drone setBehaviour "CARELESS";
_drone forceSpeed -1; // Disable speed limits to allow manual FPV velocity overrides


// Setup tracking variables
private _targetLostTime = 0;
private _maxTargetDistance = (missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500]) + 150;
private _maxTimeWithoutLOS = 4.0;   // Seconds of lost LOS before disengaging (was 1.5)
private _commitDistance    = 20;    // Within this range the drone ignores LOS and commits to the attack

private _deltaTime = 0.05;
private _targetPos = getPosASLVisual _target;
private _lastValidTargetPos = getPosASLVisual _target;
private _dist = 9999;

// Minimum AGL altitude below which we won't attempt to pull out (not enough room to recover)
private _minRecoveryAlt = 15;

while {!isNull _drone && {!isNull _target} && {alive _drone} && {alive _target}} do {
    if ((count (crew _drone)) < 1) exitWith {};
    
    private _currentPos = getPosASLVisual _drone;
    _targetPos = getPosASLVisual _target;
    
    _dist = _currentPos distance _targetPos;
    if (_dist <= _minDistanceToTarget) exitWith {};

    // 1. TELEPORT / RANGE GUARD: Break lock if target teleports away
    if (_dist > _maxTargetDistance) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Target lost: Teleport or out of range";
        };
    };

    // 2. LINE OF SIGHT CHECK (with grace period + commit zone)
    // Within _commitDistance the drone ignores LOS entirely and commits to the attack.
    private _uavEye = eyePos _drone;
    if (_uavEye isEqualTo [0,0,0]) then { _uavEye = _currentPos vectorAdd [0,0,0.5]; };
    private _targetEye = eyePos _target;
    if (_targetEye isEqualTo [0,0,0]) then { _targetEye = _targetPos vectorAdd [0,0,1]; };

    private _losBlocked = false;
    if (_dist > _commitDistance) then {
        _losBlocked = terrainIntersectASL [_uavEye, _targetEye] || {
            private _intersections = lineIntersectsSurfaces [_uavEye, _targetEye, _drone, _target, true, 1, "VIEW", "FIRE"];
            count _intersections > 0
        };
    };

    if (_losBlocked) then {
        _targetLostTime = _targetLostTime + _deltaTime;
    } else {
        _targetLostTime = 0;
        _lastValidTargetPos = _targetPos; // Keep refreshing last known position while we have sight
    };

    // 2.1 OBSTACLE DETECTION (COLLISION GUARD): Check if a solid obstacle (building/terrain) is directly in our flight path
    private _forwardVector = velocity _drone;
    if (_forwardVector isNotEqualTo [0,0,0]) then {
        private _normalizedForward = vectorNormalized _forwardVector;
        private _checkDist = (_speed * 0.25) max 8; // Check ahead by 0.25 seconds of flight (minimum 8m)
        private _pathEnd = _currentPos vectorAdd (_normalizedForward vectorMultiply _checkDist);
        private _intersections = lineIntersectsSurfaces [_currentPos, _pathEnd, _drone, _target, true, 1, "VIEW", "FIRE"];
        if (count _intersections > 0) then {
            private _intersection = _intersections select 0;
            private _intersectObj = _intersection select 2;
            private _isTargetOrVehicle = (!isNull _intersectObj && { _intersectObj == _target || _intersectObj isKindOf "AllVehicles" });
            if (!_isTargetOrVehicle) then {
                _targetLostTime = 99; // Force immediate disengagement with distinct code
                if (missionNamespace getVariable ["ddtDebug", false]) then {
                    systemChat "Collision threat detected! Aborting dive to avoid crash.";
                };
            };
        };
    };

    if (_targetLostTime > _maxTimeWithoutLOS) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            if (_targetLostTime > 90) then {
                systemChat "Target lost: Collision threat ahead, disengaged.";
            } else {
                systemChat format ["Target lost: LOS blocked for %1s", round _targetLostTime];
            };
        };
    };

    // 3. SMOOTH TURN RATE PHYSICS
    // Lead prediction for moving targets: aim where the target will be when the drone intercepts it
    private _targetVel = velocity _target;
    private _timeToTarget = _dist / _speed;
    private _leadTime = _timeToTarget min 1.5; // Cap prediction at 1.5 seconds ahead to avoid steering issues at long range
    private _predictedPos = _targetPos vectorAdd (_targetVel vectorMultiply _leadTime);

    // When LOS is blocked steer toward last KNOWN position so the drone keeps committing
    // rather than awkwardly tracking a target it can't see through terrain.
    private _currentDir = vectorDirVisual _drone;
    private _effectiveTargetPos = if (_losBlocked) then { _lastValidTargetPos } else { _predictedPos };
    private _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);

    private _cos = _currentDir vectorDotProduct _desiredDir;
    _cos = (_cos min 1) max -1;
    private _angle = acos _cos;

    // Scale turn rate and inertia dynamically with speed to keep steering tight and prevent overshoot
    private _speedFactor = (_speed / 15) max 1;
    private _maxTurnRate = (if (_AP) then { 90 } else { 75 }) * _speedFactor;
    private _maxTurnAngle = _maxTurnRate * _deltaTime;

    private _newDir = _currentDir;
    if (_angle > 0.01) then {
        if (_angle <= _maxTurnAngle) then {
            _newDir = _desiredDir;
        } else {
            private _t = _maxTurnAngle / _angle;
            _newDir = vectorNormalized ((_currentDir vectorMultiply (1 - _t)) vectorAdd (_desiredDir vectorMultiply _t));
        };
    };

    // Up vector calculation
    private _rightVector = (_newDir vectorCrossProduct [0,0,1]) vectorMultiply -1;
    private _upVector = _newDir vectorCrossProduct _rightVector;

    _drone setVectorDirAndUp [_newDir, _upVector];

    // 4. SMOOTH VELOCITY BLENDING (INERTIA)
    private _currentVelocity = velocity _drone;
    private _desiredVelocity = _newDir vectorMultiply _speed;

    // Inertia response (AT drone is heavier/more slide, AP drone is lighter/faster response)
    private _inertiaBlend = (if (_AP) then { 0.12 } else { 0.08 }) * (_speedFactor min 2.0);
    private _newVelocity = (_currentVelocity vectorMultiply (1 - _inertiaBlend)) vectorAdd (_desiredVelocity vectorMultiply _inertiaBlend);

    _drone setVelocity _newVelocity;

    sleep _deltaTime;
};

if (isNull _drone) exitWith {};

// Check if we lost lock but the drone is still alive and has an operator
_man = _drone getVariable ["CLDW_CurrentOperator", objNull];
if (isNull _man || {!alive _man}) then {
    _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

// Determine exit reason
private _targetDied    = (!alive _target);
private _losLost       = (_targetLostTime > _maxTimeWithoutLOS);
private _outOfRange    = (_dist > _maxTargetDistance);
private _closeEnough   = (_dist <= _minDistanceToTarget);
private _lowAlt        = ((getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone)) < _minRecoveryAlt);

if (_closeEnough) then {
    // Normal impact detonation
    _drone setFuel 0;
    if (_crocus) then { _drone call DB_fnc_fpv_onDestroy; };
} else {
    if (_targetDied && {_lowAlt}) then {
        // Target died while the drone is too low to recover safely – crash it
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Drone: Target died, too low to recover, crashing.";
        };
        _drone setFuel 0;
        if (_crocus) then { _drone call DB_fnc_fpv_onDestroy; };
    } else {
        if (_outOfRange || _targetDied) then {
            // Target truly gone (out of range or dead) – disengage and fly home
            if (alive _drone && {!isNull _man}) then {
                if (missionNamespace getVariable ["ddtDebug", false]) then {
                    systemChat format ["Drone disengaging: outOfRange=%1 targetDied=%2", _outOfRange, _targetDied];
                };
                _drone setVariable ["CLDW_Disengaged", true, true];
                [_drone, _lastValidTargetPos, _man] spawn CLDW_fnc_disengage;
            } else {
                _drone setFuel 0;
                if (_crocus) then { _drone call DB_fnc_fpv_onDestroy; };
            };
        } else {
            // LOS lost but target is still within range – do NOT leave the squad.
            // Re-enable AI, head to last known position, and re-enter the
            // acquisition loop so the drone hunts the target down again.
            if (alive _drone && {!isNull _man}) then {
                if (missionNamespace getVariable ["ddtDebug", false]) then {
                    systemChat "Drone: LOS lost, re-acquiring target...";
                };
                if (_hasSplitGroup && {!isNull _opGrp}) then {
                    (crew _drone) joinSilent _opGrp;
                    deleteGroup _tempGrp;
                };
                _drone enableAI "PATH";
                _drone enableAI "MOVE";
                _drone setVariable ["CLDW_Disengaged", false, true];
                _drone setVariable ["CLDW_CurrentTarget", objNull, true];
                // Fly toward last known target position immediately
                _drone doMove (ASLToAGL _lastValidTargetPos);
                // Re-enter scan loop – will re-engage if target reappears in range
                [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
            };
        };
    };
};
