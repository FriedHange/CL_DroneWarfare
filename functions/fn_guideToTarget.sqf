params [["_drone", objNull], ["_target", objNull], ["_speed", 20], ["_minDistanceToTarget", 0.1]];

if (isNull _drone || {isNull _target}) exitWith {};

// If the drone is not a suicide FPV drone (e.g. it's a bomber/utility drone like Western Sahara IED or AL-6),
// delegate to the original DDT guide function so that it can perform its native bombing run.
private _droneType = typeOf _drone;
private _lowerType = toLower _droneType;
private _isWS = (_lowerType find "uav_02_ied" > -1) || {_lowerType find "tura_uav" > -1};
private _isVanilla = (_lowerType find "uas_06" > -1) || {_lowerType find "uav_01" > -1};
private _isFPV = ((_lowerType find "crocus" > -1) || 
                 {_lowerType find "kvn" > -1} || 
                 {_lowerType find "uafpv" > -1} || 
                 {_lowerType find "rc40" > -1} || 
                 {_lowerType find "rc-40" > -1}) && {!_isWS} && {!_isVanilla};

if (!_isFPV) exitWith {
    if (!isNil "CLDW_original_GuideToTarget") then {
        _this call CLDW_original_GuideToTarget;
    };
};

private _AP = false;
private _crocus = false;
private _crocusAP = [
    "B_KVN_AP", "O_KVN_AP", "I_KVN_AP", "B_KVN_AP_TI", "O_KVN_AP_TI", "I_KVN_AP_TI",
    "B_CROCUS_AP", "O_CROCUS_AP", "I_CROCUS_AP", "B_CROCUS_AP_TI", "O_CROCUS_AP_TI", "I_CROCUS_AP_TI",
    "B_KVN_AP_F", "O_KVN_AP_F", "I_KVN_AP_F", "B_KVN_AP_TI_F", "O_KVN_AP_TI_F", "I_KVN_AP_TI_F",
    "B_CROCUS_AP_F", "O_CROCUS_AP_F", "I_CROCUS_AP_F", "B_CROCUS_AP_TI_F", "O_CROCUS_AP_TI_F", "I_CROCUS_AP_TI_F"
];
private _crocusAT = [
    "B_KVN_AT", "O_KVN_AT", "I_KVN_AT", "B_KVN_AT_TI", "O_KVN_AT_TI", "I_KVN_AT_TI",
    "B_CROCUS_AT", "O_CROCUS_AT", "I_CROCUS_AT", "B_CROCUS_AT_TI", "O_CROCUS_AT_TI", "I_CROCUS_AT_TI",
    "B_KVN_AT_F", "O_KVN_AT_F", "I_KVN_AT_F", "B_KVN_AT_TI_F", "O_KVN_AT_TI_F", "I_KVN_AT_TI_F",
    "B_CROCUS_AT_F", "O_CROCUS_AT_F", "I_CROCUS_AT_F", "B_CROCUS_AT_TI_F", "O_CROCUS_AT_TI_F", "I_CROCUS_AT_TI_F"
];

private _droneSpeedSetting = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 125]) / 3.6;
private _droneType = typeOf _drone;
private _droneTypeLower = toLower _droneType;

if ((toUpper _droneType) in _crocusAT) then {
    _crocus = true;
    _speed = _droneSpeedSetting;
};
if ((toUpper _droneType) in _crocusAP) then {
    _crocus = true;
    _AP = true;
    _speed = _droneSpeedSetting;
    _minDistanceToTarget = 1;
};

// Generic AP detection for mod drones
if (!_AP && {
    ("_ap" in _droneTypeLower) || 
    ("rkg" in _droneTypeLower) || 
    ("og7v" in _droneTypeLower) || 
    ("rc40_he" in _droneTypeLower) ||
    ("_he" in _droneTypeLower) ||
    ("frag" in _droneTypeLower) ||
    ("personnel" in _droneTypeLower)
}) then {
    if (!("_at" in _droneTypeLower) && !("pg7" in _droneTypeLower)) then {
        _AP = true;
        _minDistanceToTarget = 1;
    };
};

// UAFPV drones (Tom's Ukraine FPV and BIG GUY edits) — detect AP vs AT for turn rate/inertia tuning
if (!_AP && { _droneTypeLower find "uafpv" > -1 }) then {
    if !(_droneTypeLower find "_at" > -1) then {
        _AP = true;
        _minDistanceToTarget = 1;
    };
};

// RC-40 HE = AP loitering munition
if (!_AP && { ["rc40_he", _droneTypeLower] call BIS_fnc_inString }) then {
    _AP = true;
    _minDistanceToTarget = 1.2;
};

if (!_AP) then {
    _minDistanceToTarget = 3.8; // Vehicles have 3-5m bounding boxes; detonate when within 3.8m of vehicle origin
} else {
    _minDistanceToTarget = 1.2;
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
private _maxTargetDistance = (missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500]) + 1500;
private _maxTimeWithoutLOS = 4.0;   // Seconds of lost LOS before disengaging (was 1.5)
private _commitDistance    = 25;    // Within this range the drone ignores LOS and commits to the attack

private _deltaTime = 0.05;
private _targetPos = getPosASLVisual _target;
private _lastValidTargetPos = getPosASLVisual _target;
private _dist = 9999;

// Minimum AGL altitude below which we won't attempt to pull out (not enough room to recover)
private _minRecoveryAlt = 15;

private _smoothedInterceptPos = _targetPos;
private _currentRollDeg = 0;

private _playerTookControl = false;
while {!isNull _drone && {!isNull _target} && {alive _drone} && {alive _target}} do {
    if ((count (crew _drone)) < 1) exitWith {};

    // If player takes control of the drone, exit/abort the loop to allow full manual control
    private _controller = uavControl _drone select 0;
    if (!isNull _controller && {isPlayer _controller}) exitWith {
        _playerTookControl = true;
    };
    
    private _currentPos = getPosASLVisual _drone;
    _targetPos = getPosASLVisual _target;
    
    _dist = _currentPos distance _targetPos;

    // Dynamically scale detonation distance based on frame velocity step so high-speed dives always detonate before physical ground impact
    private _currentVelocity = velocity _drone;
    private _currentSpeed = vectorMagnitude _currentVelocity;
    private _frameStep = (_currentSpeed * _deltaTime) max 2.5;
    private _detonationDistance = (_minDistanceToTarget + _frameStep) max 3.5;

    // Also check ground terrain proximity when diving near target
    private _droneAGL = (getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone));
    private _terrainThreat = (_droneAGL < 2.0 && {_dist < 30});

    if (_dist <= _detonationDistance || _terrainThreat) exitWith {};

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
        private _intersections = lineIntersectsSurfaces [_uavEye, _targetEye, _drone, vehicle _target, true, 1, "VIEW", "GEOM"];
        if (count _intersections > 0) then {
            private _hitObj = (_intersections select 0) select 2;
            if (!isNull _hitObj && { _hitObj isKindOf "Building" || _hitObj isKindOf "House" }) then {
                _losBlocked = true;
            };
        };
        if (!_losBlocked) then {
            _losBlocked = terrainIntersectASL [_uavEye, _targetEye];
        };
    };

    if (_losBlocked) then {
        _targetLostTime = _targetLostTime + _deltaTime;
    } else {
        _targetLostTime = 0;
        _lastValidTargetPos = _targetPos; // Keep refreshing last known position while we have sight
    };

    // 2.1 OBSTACLE DETECTION (COLLISION GUARD): Check if a solid building/structure is directly in our flight path (disabled near target)
    if (_dist > 40) then {
        private _forwardVector = velocity _drone;
        if (_forwardVector isNotEqualTo [0,0,0]) then {
            private _normalizedForward = vectorNormalized _forwardVector;
            private _checkDist = (_speed * 0.2) max 6; // Check ahead by 0.2 seconds of flight
            private _pathEnd = _currentPos vectorAdd (_normalizedForward vectorMultiply _checkDist);
            private _intersections = lineIntersectsSurfaces [_currentPos, _pathEnd, _drone, _target, true, 1, "VIEW", "FIRE"];
            if (count _intersections > 0) then {
                private _intersection = _intersections select 0;
                private _intersectObj = _intersection select 2;
                if (!isNull _intersectObj) then {
                    // Only abort for solid buildings/houses or map structures, NOT foliage/trees/bushes/vehicles
                    private _isSolidStructure = (_intersectObj isKindOf "Building" || _intersectObj isKindOf "House");
                    if (_isSolidStructure) then {
                        _targetLostTime = 99; // Abort dive to avoid crashing into a solid building
                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                            systemChat "Collision threat (building) detected! Aborting dive.";
                        };
                    };
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

    // Dynamic pursuit speed boost if target vehicle is driving fast
    private _targetSpeedMS = (speed (vehicle _target)) / 3.6;
    private _effectiveSpeed = _speed;
    if (_targetSpeedMS > 0) then {
        // Ensure drone speed is at least 8.5 m/s (~30 km/h) faster than the target vehicle to catch up
        _effectiveSpeed = _speed max (_targetSpeedMS + 8.5);
    };

    // 3. FILTERED LEAD PURSUIT (Oscillation Prevention)
    // Lead prediction for moving targets: aim where the target will be when the drone intercepts it
    private _targetVel = velocity (vehicle _target);
    private _timeToTarget = _dist / (_effectiveSpeed max 1);
    private _leadTime = _timeToTarget min 3.5; // Lead up to 3.5 seconds ahead for fast moving vehicles
    private _rawPredictedPos = _targetPos vectorAdd (_targetVel vectorMultiply _leadTime);

    // Smooth intercept position exponentially to avoid rapid nose jittering
    _smoothedInterceptPos = (_smoothedInterceptPos vectorMultiply 0.7) vectorAdd (_rawPredictedPos vectorMultiply 0.3);

    // When LOS is blocked steer toward last KNOWN position so the drone keeps committing
    private _currentDir = vectorDirVisual _drone;
    private _effectiveTargetPos = if (_losBlocked) then { _lastValidTargetPos } else { _smoothedInterceptPos };
    private _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);

    private _cos = _currentDir vectorDotProduct _desiredDir;
    _cos = (_cos min 1) max -1;
    private _angle = acos _cos;

    // 4. REALISTIC TURN RATE LIMITING
    // Cap angular turn rate (degrees per second) so high speeds produce realistic wide turning arcs
    private _maxTurnRate = if (_AP) then { 55 } else { 42 }; // degrees/second
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

    // 5. AIRCRAFT BANKING (ROLL INTO TURNS)
    // Calculate steering yaw demand on the horizontal plane
    private _yawDemand = (_currentDir select 0) * (_desiredDir select 1) - (_currentDir select 1) * (_desiredDir select 0);
    private _maxBankAngle = if (_AP) then { 50 } else { 40 }; // Maximum roll angle in degrees
    private _targetRollDeg = ((-_yawDemand min 1) max -1) * _maxBankAngle;

    // Smoothly interpolate roll angle (wing bank rate ~120 deg/sec)
    private _maxRollStep = 120 * _deltaTime;
    private _rollDelta = (_targetRollDeg - _currentRollDeg) min _maxRollStep max (-_maxRollStep);
    _currentRollDeg = _currentRollDeg + _rollDelta;

    // Compute banked 3D orientation vectors (Dir and Up) with gimbal-lock safety for steep dives
    private _refUp = [0, 0, 1];
    if (abs (_newDir select 2) > 0.85) then {
        _refUp = vectorUpVisual _drone;
        if ((_refUp vectorCrossProduct _newDir) isEqualTo [0,0,0]) then {
            _refUp = [0, 1, 0];
        };
    };
    private _rightVector = vectorNormalized (_newDir vectorCrossProduct _refUp);
    if (_rightVector isEqualTo [0,0,0]) then { _rightVector = [1,0,0]; };
    private _normalUp = vectorNormalized (_rightVector vectorCrossProduct _newDir);
    
    // Rotate _normalUp around _newDir by _currentRollDeg
    private _radRoll = _currentRollDeg * (pi / 180);
    private _upBanked = (_normalUp vectorMultiply (cos _radRoll)) vectorAdd (_rightVector vectorMultiply (sin _radRoll));

    _drone setVectorDirAndUp [_newDir, _upBanked];

    // 6. REALISTIC ACCELERATION & FLIGHT INERTIA
    // Drones accelerate towards target pursuit speed at a realistic quadcopter rate (~28-35 m/s²)
    private _accelRate = if (_AP) then { 28 } else { 35 }; // m/s² acceleration rate
    private _maxSpeedChange = _accelRate * _deltaTime;
    private _targetSpeed = _currentSpeed;

    if (_currentSpeed < _effectiveSpeed) then {
        _targetSpeed = (_currentSpeed + _maxSpeedChange) min _effectiveSpeed;
    } else {
        _targetSpeed = (_currentSpeed - _maxSpeedChange) max _effectiveSpeed;
    };

    private _currentVelDir = vectorNormalized _currentVelocity;
    if (_currentVelDir isEqualTo [0,0,0]) then { _currentVelDir = _newDir; };

    // Blend flight direction (steering vector), then scale by ramped speed
    private _inertiaBlend = if (_AP) then { 0.22 } else { 0.15 };
    private _newVelDir = vectorNormalized ((_currentVelDir vectorMultiply (1 - _inertiaBlend)) vectorAdd (_newDir vectorMultiply _inertiaBlend));

    private _newVelocity = _newVelDir vectorMultiply _targetSpeed;
    _drone setVelocity _newVelocity;

    sleep _deltaTime;
};

if (isNull _drone) exitWith {};

if (_playerTookControl) exitWith {
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "Player took control of drone; guiding aborted.";
    };
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
    _drone setVariable ["CLDW_Disengaged", false, true];
};

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
// If drone distance <= detonationDistance OR if physical collision/death occurred within 15m of target, treat as successful detonation!
private _closeEnough   = (_dist <= (_minDistanceToTarget + 4.0)) || (!alive _drone && {_dist < 15});
private _lowAlt        = ((getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone)) < _minRecoveryAlt);

if (_closeEnough) then {
    // Normal impact detonation
    _drone setFuel 0;

    // Tag target and nearby units before detonation for RIS scoring
    private _operator = _drone getVariable ["CLDW_CurrentOperator", objNull];
    if (!isNull _operator) then {
        _target setVariable ["CLDW_LastDroneAttacker", _operator, true];
        _target setVariable ["CLDW_LastDroneAttackerTime", time, true];
        _target setVariable ["CLDW_LastDroneAttackerSide", side group _operator, true];
        
        private _nearUnits = nearestObjects [_target, ["CAManBase"], 15];
        {
            _x setVariable ["CLDW_LastDroneAttacker", _operator, true];
            _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
            _x setVariable ["CLDW_LastDroneAttackerSide", side group _operator, true];
        } forEach _nearUnits;
    };

    if (_crocus) then { _drone call DB_fnc_fpv_onDestroy; };
} else {
    if (_targetDied && {_lowAlt}) then {
        // Target died while the drone is too low to recover safely – crash it
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Drone: Target died, too low to recover, crashing.";
        };
        _drone setFuel 0;

        // Tag nearby units before detonation for RIS scoring
        private _operator = _drone getVariable ["CLDW_CurrentOperator", objNull];
        if (!isNull _operator) then {
            private _nearUnits = nearestObjects [_drone, ["CAManBase"], 15];
            {
                _x setVariable ["CLDW_LastDroneAttacker", _operator, true];
                _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
                _x setVariable ["CLDW_LastDroneAttackerSide", side group _operator, true];
            } forEach _nearUnits;
        };

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
            // LOS lost but target is still within range – do NOT fly back to squad!
            // Maintain drone's local pursuit from UAV perspective and attempt re-acquisition.
            if (alive _drone && {!isNull _man}) then {
                if (missionNamespace getVariable ["ddtDebug", false]) then {
                    systemChat "Drone: LOS lost, searching locally for target...";
                };
                
                [_drone, _man, _lastValidTargetPos, _droneSpeedSetting, _minDistanceToTarget] spawn {
                    params ["_drone", "_man", "_lastPos", "_speed", "_minDist"];
                    if (isNull _drone || {!alive _drone}) exitWith {};
                    
                    _drone enableAI "PATH";
                    _drone enableAI "MOVE";
                    _drone flyInHeightASL [45, 45, 45];
                    (driver _drone) doMove (ASLToAGL _lastPos);
                    
                    private _reacquired = false;
                    private _searchTimeout = time + 8;
                    
                    while {alive _drone && {time < _searchTimeout} && {!_reacquired}} do {
                        sleep 0.5;
                        if (isNull _drone || {!alive _drone}) exitWith {};
                        
                        // Check targets from UAV's own perspective (high altitude vision)
                        private _foundTargets = [_drone, 1500] call CLDW_fnc_getTargetsAT;
                        if (count _foundTargets > 0) then {
                            private _newTarget = _foundTargets select 0;
                            if (!isNull _newTarget && {alive _newTarget}) then {
                                _reacquired = true;
                                _drone setVariable ["CLDW_Disengaged", false, true];
                                _drone setVariable ["CLDW_CurrentTarget", _newTarget, true];
                                if (missionNamespace getVariable ["ddtDebug", false]) then {
                                    systemChat format ["Drone re-acquired target: %1!", typeOf _newTarget];
                                };
                                [_drone, _newTarget, _speed, _minDist] spawn CLDW_fnc_guideToTarget;
                            };
                        };
                    };
                    
                    // Only disengage and return to squad if 8 seconds elapsed with zero targets anywhere in range
                    if (!_reacquired && {alive _drone}) then {
                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                            systemChat "Drone: Search timeout expired with no targets. Disengaging to squad.";
                        };
                        _drone setVariable ["CLDW_Disengaged", true, true];
                        [_drone, _lastPos, _man] spawn CLDW_fnc_disengage;
                    };
                };
            };
        };
    };
};
