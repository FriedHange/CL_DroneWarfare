params [["_drone", objNull], ["_target", objNull], ["_speed", 20], ["_minDistanceToTarget", 0.1]];

if (isNull _drone || {isNull _target}) exitWith {};

// If the drone is a specialized bomber drone and original DDT guide exists, delegate to it
private _droneType = typeOf _drone;
private _lowerType = toLower _droneType;
private _isWS = (_lowerType find "uav_02_ied" > -1) || {_lowerType find "tura_uav" > -1};
private _isVanilla = (_lowerType find "uas_06" > -1) || {_lowerType find "uav_01" > -1};
private _isFPV = ((_lowerType find "crocus" > -1) || 
                 {_lowerType find "kvn" > -1} || 
                 {_lowerType find "uafpv" > -1} || 
                 {_lowerType find "rc40" > -1} || 
                 {_lowerType find "rc-40" > -1} ||
                 {_lowerType find "fpv" > -1}) && {!_isWS};

if (!_isFPV && {!isNil "CLDW_original_GuideToTarget"}) exitWith {
    _this call CLDW_original_GuideToTarget;
};

private _AP = false;
private _crocus = false;
private _crocusAP = [
    "b_kvn_ap", "o_kvn_ap", "i_kvn_ap", "b_kvn_ap_ti", "o_kvn_ap_ti", "i_kvn_ap_ti",
    "b_crocus_ap", "o_crocus_ap", "i_crocus_ap", "b_crocus_ap_ti", "o_crocus_ap_ti", "i_crocus_ap_ti",
    "b_kvn_ap_f", "o_kvn_ap_f", "i_kvn_ap_f", "b_kvn_ap_ti_f", "o_kvn_ap_ti_f", "i_kvn_ap_ti_f",
    "b_crocus_ap_f", "o_crocus_ap_f", "i_crocus_ap_f", "b_crocus_ap_ti_f", "o_crocus_ap_ti_f", "i_crocus_ap_ti_f"
];
private _crocusAT = [
    "b_kvn_at", "o_kvn_at", "i_kvn_at", "b_kvn_at_ti", "o_kvn_at_ti", "i_kvn_at_ti",
    "b_crocus_at", "o_crocus_at", "i_crocus_at", "b_crocus_at_ti", "o_crocus_at_ti", "i_crocus_at_ti",
    "b_kvn_at_f", "o_kvn_at_f", "i_kvn_at_f", "b_kvn_at_ti_f", "o_kvn_at_ti_f", "i_kvn_at_ti_f",
    "b_crocus_at_f", "o_crocus_at_f", "i_crocus_at_f", "b_crocus_at_ti_f", "o_crocus_at_ti_f", "i_crocus_at_ti_f"
];

private _droneSpeedSetting = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 125]) / 3.6;

if (_lowerType in _crocusAT) then {
    _crocus = true;
    _speed = _droneSpeedSetting;
};
if (_lowerType in _crocusAP) then {
    _crocus = true;
    _AP = true;
    _speed = _droneSpeedSetting;
    _minDistanceToTarget = 1;
};

// Generic AP detection for mod drones
if (!_AP && {
    ("_ap" in _lowerType) || 
    ("rkg" in _lowerType) || 
    ("og7v" in _lowerType) || 
    ("rc40_he" in _lowerType) ||
    ("_he" in _lowerType) ||
    ("frag" in _lowerType) ||
    ("personnel" in _lowerType)
}) then {
    if (!("_at" in _lowerType) && !("pg7" in _lowerType)) then {
        _AP = true;
        _minDistanceToTarget = 1;
    };
};

// UAFPV drones (Tom's Ukraine FPV and BIG GUY edits)
if (!_AP && { _lowerType find "uafpv" > -1 }) then {
    if !(_lowerType find "_at" > -1) then {
        _AP = true;
        _minDistanceToTarget = 1;
    };
};

// RC-40 HE = AP loitering munition
if (!_AP && { ["rc40_he", _lowerType] call BIS_fnc_inString }) then {
    _AP = true;
    _minDistanceToTarget = 1.2;
};

if (!_AP) then {
    _minDistanceToTarget = 3.8; // Vehicles have 3-5m bounding boxes
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

// Split drone crew from the operator group during attack run
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

private _pilotGrp = group (driver _drone);
if (!isNull _pilotGrp) then {
    _pilotGrp setCombatMode "BLUE";
    _pilotGrp setBehaviour "CARELESS";
};
_drone forceSpeed -1; // Disable speed limits to allow manual FPV velocity overrides

// Setup tracking variables
private _targetLostTime = 0;
private _maxTargetDistance = (missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500]) + 1500;
private _maxTimeWithoutLOS = 4.0;   // Seconds of lost LOS before disengaging
private _commitDistance    = 25;    // Within this range the drone ignores LOS and commits to the attack

private _deltaTime = 0.05;
private _targetPos = getPosASLVisual _target;
private _lastValidTargetPos = getPosASLVisual _target;
private _dist = 9999;

// Minimum AGL altitude below which we won't attempt to pull out
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
    private _uavEye = eyePos _drone;
    if (_uavEye isEqualTo [0,0,0]) then { _uavEye = _currentPos vectorAdd [0,0,0.5]; };
    private _targetEye = eyePos _target;
    if (_targetEye isEqualTo [0,0,0]) then { _targetEye = _targetPos vectorAdd [0,0,1]; };

    private _losBlocked = false;
    if (_dist > _commitDistance) then {
        private _intersections = lineIntersectsSurfaces [_uavEye, _targetEye, _drone, vehicle _target, true, 1, "VIEW", "GEOM"];
        if (count _intersections > 0) then {
            private _hitObj = (_intersections select 0) select 2;
            if (!isNull _hitObj && { _hitObj isKindOf "Building" || _hitObj isKindOf "House" || _hitObj isKindOf "Wall" }) then {
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
        _lastValidTargetPos = _targetPos;
    };

    // 2.1 OBSTACLE DETECTION (COLLISION GUARD)
    if (_dist > 40) then {
        private _forwardVector = velocity _drone;
        if (_forwardVector isNotEqualTo [0,0,0]) then {
            private _normalizedForward = vectorNormalized _forwardVector;
            private _checkDist = (_speed * 0.2) max 6;
            private _pathEnd = _currentPos vectorAdd (_normalizedForward vectorMultiply _checkDist);
            private _intersections = lineIntersectsSurfaces [_currentPos, _pathEnd, _drone, _target, true, 1, "VIEW", "GEOM"];
            if (count _intersections > 0) then {
                private _intersection = _intersections select 0;
                private _intersectObj = _intersection select 2;
                if (!isNull _intersectObj) then {
                    private _isSolidStructure = (_intersectObj isKindOf "Building" || _intersectObj isKindOf "House" || _intersectObj isKindOf "Wall");
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
        _effectiveSpeed = _speed max (_targetSpeedMS + 8.5);
    };

    // 3. FILTERED LEAD PURSUIT
    private _targetVel = velocity (vehicle _target);
    private _timeToTarget = _dist / (_effectiveSpeed max 1);
    private _leadTime = _timeToTarget min 3.5;
    private _rawPredictedPos = _targetPos vectorAdd (_targetVel vectorMultiply _leadTime);

    _smoothedInterceptPos = (_smoothedInterceptPos vectorMultiply 0.7) vectorAdd (_rawPredictedPos vectorMultiply 0.3);

    private _currentDir = vectorDirVisual _drone;
    private _effectiveTargetPos = if (_losBlocked) then { _lastValidTargetPos } else { _smoothedInterceptPos };
    private _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);

    private _cos = _currentDir vectorDotProduct _desiredDir;
    _cos = (_cos min 1) max -1;
    private _angle = acos _cos;

    // 4. REALISTIC TURN RATE LIMITING
    private _maxTurnRate = if (_AP) then { 55 } else { 42 };
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
    private _yawDemand = (_currentDir select 0) * (_desiredDir select 1) - (_currentDir select 1) * (_desiredDir select 0);
    private _maxBankAngle = if (_AP) then { 50 } else { 40 };
    private _targetRollDeg = ((-_yawDemand min 1) max -1) * _maxBankAngle;

    private _maxRollStep = 120 * _deltaTime;
    private _rollDelta = (_targetRollDeg - _currentRollDeg) min _maxRollStep max (-_maxRollStep);
    _currentRollDeg = _currentRollDeg + _rollDelta;

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
    
    private _radRoll = _currentRollDeg * (pi / 180);
    private _upBanked = (_normalUp vectorMultiply (cos _radRoll)) vectorAdd (_rightVector vectorMultiply (sin _radRoll));

    _drone setVectorDirAndUp [_newDir, _upBanked];

    // 6. REALISTIC ACCELERATION & FLIGHT INERTIA
    private _accelRate = if (_AP) then { 28 } else { 35 };
    private _maxSpeedChange = _accelRate * _deltaTime;
    private _targetSpeed = _currentSpeed;

    if (_currentSpeed < _effectiveSpeed) then {
        _targetSpeed = (_currentSpeed + _maxSpeedChange) min _effectiveSpeed;
    } else {
        _targetSpeed = (_currentSpeed - _maxSpeedChange) max _effectiveSpeed;
    };

    private _currentVelDir = vectorNormalized _currentVelocity;
    if (_currentVelDir isEqualTo [0,0,0]) then { _currentVelDir = _newDir; };

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

    if (_crocus && {!isNil "DB_fnc_fpv_onDestroy"}) then {
        _drone call DB_fnc_fpv_onDestroy;
    };

    // Trigger universal impact detonation
    if (alive _drone) then {
        private _pos = getPosATL _drone;
        if (_AP) then {
            "DemoCharge_Remote_Ammo_Scripted" createVehicle _pos;
        } else {
            "M_Titan_AT" createVehicle _pos;
        };
        _drone setDamage 1;
    };
} else {
    if (_targetDied && {_lowAlt}) then {
        // Target died while the drone is too low to recover safely – crash it
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Drone: Target died, too low to recover, crashing.";
        };
        _drone setFuel 0;

        private _operator = _drone getVariable ["CLDW_CurrentOperator", objNull];
        if (!isNull _operator) then {
            private _nearUnits = nearestObjects [_drone, ["CAManBase"], 15];
            {
                _x setVariable ["CLDW_LastDroneAttacker", _operator, true];
                _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
                _x setVariable ["CLDW_LastDroneAttackerSide", side group _operator, true];
            } forEach _nearUnits;
        };

        if (_crocus && {!isNil "DB_fnc_fpv_onDestroy"}) then {
            _drone call DB_fnc_fpv_onDestroy;
        };
        if (alive _drone) then { _drone setDamage 1; };
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
                if (_crocus && {!isNil "DB_fnc_fpv_onDestroy"}) then { _drone call DB_fnc_fpv_onDestroy; };
                if (alive _drone) then { _drone setDamage 1; };
            };
        } else {
            // LOS lost but target is still within range – search locally
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
                    
                    // Only disengage and return to squad if search timeout expired
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
