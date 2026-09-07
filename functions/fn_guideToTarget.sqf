/*
    File: fn_guideToTarget.sqf
    Author: Carl Lorenzo
    Description:
        Refactored drone pursuit and terminal engagement guidance.
        Features:
        1. Fast responsive acceleration reaching full top speed (e.g. 200 km/h) immediately on target acquisition.
        2. High vantage approach altitude (35m AGL) during chase phase; transitions into terminal dive within 80m.
        3. Smooth 3D velocity and orientation blending without midair stutter or freezing.
        4. Strict raycast LOS & anti-wallhack validation against terrain and building structures.
        5. Dynamic dive abortion with pull-up to pursuit altitude and unobstructed re-engagement.
        6. Mod-native destruction hooks for Crocus, KVN, UAFPV, and universal drones.
*/

params [["_drone", objNull], ["_target", objNull], ["_speedInput", 0], ["_minDistanceToTarget", 0.1]];

if (isNull _drone || {isNull _target} || {!alive _drone} || {!alive _target}) exitWith {};

// Only FPV suicide drones perform physical terminal dive guidance.
// Recon drones (Tayran 2, AR-2 Darter, UAV_01, UAV_06, AL-6, Sensor, Smoke, Mavic, Black Hornet) and Bomber drones (UAV_02, Tura) are delegated to native DDT handlers.
private _droneType = typeOf _drone;
private _lowerType = toLower _droneType;
private _isSuicide = ((_lowerType find "crocus" > -1) || 
                     {_lowerType find "kvn" > -1} || 
                     {_lowerType find "uafpv" > -1} || 
                     {_lowerType find "rc40_he" > -1} ||
                     {_lowerType find "rc-40_he" > -1} ||
                     {_lowerType find "fpv" > -1}) &&
                     {!(_lowerType find "uav_01" > -1)} &&
                     {!(_lowerType find "darter" > -1)} &&
                     {!(_lowerType find "tayran" > -1)} &&
                     {!(_lowerType find "uav_06" > -1)} &&
                     {!(_lowerType find "uas_06" > -1)} &&
                     {!(_lowerType find "al6" > -1)} &&
                     {!(_lowerType find "al-6" > -1)} &&
                     {!(_lowerType find "sensor" > -1)} &&
                     {!(_lowerType find "smoke" > -1)} &&
                     {!(_lowerType find "recon" > -1)} &&
                     {!(_lowerType find "mavic" > -1)} &&
                     {!(_lowerType find "blackhornet" > -1)} &&
                     {!(_lowerType find "ied" > -1)};

if (!_isSuicide) exitWith {
    if (!isNil "CLDW_original_GuideToTarget") then {
        _this call CLDW_original_GuideToTarget;
    };
};

// =====================================
// 1. UNIFIED SPEED & PAYLOAD CONFIGURATION
// =====================================
private _maxDiveSpeed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6; // Convert km/h to m/s
private _speed = _maxDiveSpeed;
private _fastTargetThreshold = 80;
private _fastTargetLeadOffset = 1;
private _vehicleDiveDistance = 500;
private _vehicleAimHeightOffset = -2.5; // Aim below bounding centre to hit vehicle body, not fly over the roof

private _AP = false;
if (
    ("_ap" in _lowerType) || 
    ("rkg" in _lowerType) || 
    ("og7v" in _lowerType) || 
    ("rc40" in _lowerType) || 
    ("rc-40" in _lowerType) || 
    ("_he" in _lowerType) ||
    ("frag" in _lowerType) ||
    ("personnel" in _lowerType) ||
    ("crocus_ap" in _lowerType) ||
    ("kvn_ap" in _lowerType)
) then {
    if (!("_at" in _lowerType) && !("pg7" in _lowerType)) then {
        _AP = true;
    };
};

// Detonation contact tolerance based on target bounding volume
if (!_AP) then {
    _minDistanceToTarget = 3.5; // Large vehicles (Tanks, APCs, Trucks)
} else {
    _minDistanceToTarget = 1.2; // Infantry and light vehicles
};

// Lead cap: AP targets infantry — tight, short lead (1.5s). AT targets vehicles — wider pursuit arc (2.5s).
private _predictionTimeCap = if (_AP) then { 1.5 } else { 2.5 };

if (missionNamespace getVariable ["ddtDebug", false]) then {
    systemChat format ["CLDW: FPV engaging %1 at full speed %2 km/h", typeOf _target, round (_speed * 3.6)];
};

// Operator & group resolution
private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
if (isNull _opGrp && {!isNull _man}) then { _opGrp = group _man; };
if (isNull _man || {!alive _man}) then {
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

private _droneSide = if (!isNull _opGrp) then { side _opGrp } else {
    if (!isNull _man) then { side group _man } else { side _drone }
};

// Ensure drone crew is ALWAYS isolated in its own dedicated UAV group (never mixed with infantry squads)
private _droneCrew = crew _drone;
if (count _droneCrew > 0) then {
    private _originalGrp = group (_droneCrew select 0);
    if (isNull _originalGrp || {!isNull _opGrp && {_originalGrp == _opGrp}}) then {
        private _droneGrp = createGroup [side _drone, true];
        _droneCrew joinSilent _droneGrp;
        _droneGrp deleteGroupWhenEmpty true;
    };
};

// 2. Fully script-controlled flight: disable AI speed governor so setVelocity has
// full authority. No doMove/flyInHeight in the loop to avoid AI fighting our velocity.
private _driverUnit = driver _drone;
_drone setCombatMode "BLUE";
_drone setBehaviour "CARELESS";
_drone forceSpeed -1; // -1 = no speed limit, allow setVelocity full authority
private _droneGrpLocal = group _driverUnit;
if (!isNull _droneGrpLocal && {_droneGrpLocal != _opGrp}) then {
    _droneGrpLocal setSpeedMode "FULL";
    _droneGrpLocal setBehaviour "CARELESS";
    _droneGrpLocal setCombatMode "BLUE";
};

// Disable collision between nearby UAVs to prevent mid-air team collisions
private _nearDrones = nearestObjects [_drone, ["UAV", "Air"], 300];
{
    if (_x != _drone) then {
        _drone disableCollisionWith _x;
        _x disableCollisionWith _drone;
    };
} forEach _nearDrones;

// Unique swarm lane offset to prevent multiple drones attacking the same target from flying in single-file.
// AP drones use tighter lanes (small infantry targets); AT drones spread wider to bracket vehicles.
private _droneIdNum = (parseNumber (str _drone select [count (str _drone) - 3])) max 0;
private _laneAngle = ((_droneIdNum mod 8) * 45);
private _laneDistBase = if (_AP) then { 1.5 } else { 3.0 }; // AP: 1.5–4.5m  AT: 3–9m
private _laneDist = ((_droneIdNum mod 3) + 1) * _laneDistBase;
private _laneOffset = [sin _laneAngle * _laneDist, cos _laneAngle * _laneDist];

// =====================================
// 2. TRACKING & LOS VALIDATION STATE
// =====================================
private _targetLostTime = 0;
private _maxTargetDistance = missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000];
private _maxTimeWithoutLOS = 3.5; // Seconds before aborting engagement on lost sight
// Commit distance: drone must start direct-aiming at the target early enough to correct its heading.
// At 150 km/h (41.7 m/s) and 55 deg/s turn rate, correcting a 30 deg error needs ~0.55s = ~23m.
// AP targets infantry (small hitbox) so needs a longer commit window than AT vs vehicles.
private _commitDistance = if (_AP) then { 70 } else { 40 };

private _deltaTime = 0.05;
private _lastTickTime = time;
private _losCheckInterval = 0.75; // Rate-limit obstacle raycasts to 0.75s (optimized for large battles)
private _lastLosCheckTime = -1;
private _emptyCheckInterval = 3.0; // Check vehicle occupancy every 3.0s (optimized for large battles)
private _lastEmptyCheckTime = -1;
private _losBlocked = false;
private _obstacleDistance = 9999;
private _targetPos = getPosASLVisual _target;
private _lastValidTargetPos = getPosASLVisual _target;
private _dist = 9999;
private _impactDistance = 9999;
private _minRecoveryAlt = 10;
private _currentRollDeg = 0;
private _smoothedInterceptPos = _targetPos;

private _playerTookControl = false;
private _diveAborted = false;
private _emptyVehicleDisengaged = false;

// =====================================
// 3. MAIN GUIDANCE & ENGAGEMENT LOOP
// =====================================
while {!isNull _drone && {!isNull _target} && {alive _drone} && {alive _target} && {!_diveAborted}} do {
    if ((count (crew _drone)) < 1) exitWith {};

    // Allow player to take manual control seamlessly
    private _controller = uavControl _drone select 0;
    if (!isNull _controller && {isPlayer _controller}) exitWith {
        _playerTookControl = true;
    };
    
    _deltaTime = ((time - _lastTickTime) min 0.15) max 0.02;
    _lastTickTime = time;

    private _currentPos = getPosASLVisual _drone;
    _targetPos = getPosASLVisual _target;
    _dist = _currentPos distance _targetPos;

    // Contact threshold scaled by drone speed
    private _currentVelocity = velocity _drone;
    private _currentSpeed = vectorMagnitude _currentVelocity;
    private _frameStep = (_currentSpeed * _deltaTime) max 2.5;
    private _detonationDistance = (_minDistanceToTarget + _frameStep) max 3.5;

    // Terrain proximity guard during terminal dive
    private _droneAGL = (getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone));
    private _terrainThreat = (_droneAGL < 2.0 && {_dist < 30});

    if (_dist <= _detonationDistance || _terrainThreat) exitWith {};

    // 1. Engagement Range Guard
    if (_dist > _maxTargetDistance) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "CLDW: Target exceeded maximum engagement range.";
        };
    };

    // 2. Empty Vehicle Check & Dismounted Passenger Priority (rate-limited to 3s for large battles)
    if ((time >= _lastEmptyCheckTime + _emptyCheckInterval || {_lastEmptyCheckTime < 0}) && {_dist > 25}) then {
        _lastEmptyCheckTime = time;

        if (missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true]) then {
            if (!(_target isKindOf "CAManBase")) then {
                private _targetVeh = vehicle _target;
                private _aliveCrew = (crew _targetVeh) select { alive _x };
                if (count _aliveCrew == 0) then {
                    // Target vehicle has become empty! Search for dismounted passengers / hostiles near the vehicle
                    private _nearInf = (getPosATL _targetVeh) nearEntities ["CAManBase", 75];
                    private _dismountedCandidates = _nearInf select {
                        alive _x && 
                        {!(_x getVariable ["CLDW_IsDroneCrew", false])} && 
                        {!(_x getVariable ["USED", false])} && 
                        {!(_x isKindOf "UAV")} &&
                        {
                            private _xSide = side (group _x);
                            (_xSide != civilian && {_xSide != sideUnknown} && {_xSide != sideLogic}) && 
                            { ([_droneSide, _xSide] call BIS_fnc_areFriendly) isEqualTo false || { (_droneSide getFriend _xSide < 0.6) || (_xSide getFriend _droneSide < 0.6) } }
                        } &&
                        {!(_x getVariable ["isPetros", false])}
                    };

                    if (count _dismountedCandidates > 0) then {
                        // Prioritize units that were assigned to this vehicle, with deconfliction if another drone is already targeting them
                        _dismountedCandidates = [_dismountedCandidates, [], {
                            private _isAssigned = if (assignedVehicle _x == _targetVeh) then { 0 } else { 1 };
                            private _assignedDrone = _x getVariable ["CLDW_AssignedDrone", objNull];
                            private _conflictPenalty = if (!isNull _assignedDrone && {alive _assignedDrone} && {_assignedDrone != _drone}) then { 200 } else { 0 };
                            [_isAssigned, (_currentPos distance _x) + _conflictPenalty]
                        }, "ASCEND"] call BIS_fnc_sortBy;

                        // Verify LOS to the best candidate
                        private _uavEye = eyePos _drone;
                        if (_uavEye isEqualTo [0,0,0]) then { _uavEye = _currentPos vectorAdd [0,0,0.4]; };
                        private _foundCandidate = objNull;
                        {
                            private _eyeCand = eyePos _x;
                            if (_eyeCand isEqualTo [0,0,0]) then { _eyeCand = (getPosASL _x) vectorAdd [0,0,1]; };
                            if (!terrainIntersectASL [_uavEye, _eyeCand]) exitWith {
                                _foundCandidate = _x;
                            };
                        } forEach _dismountedCandidates;

                        if (!isNull _foundCandidate) then {
                            // Smoothly switch target to dismounted passenger
                            _target setVariable ["CLDW_AssignedDrone", objNull, true];
                            _target = _foundCandidate;
                            _target setVariable ["CLDW_AssignedDrone", _drone, true];
                            _drone setVariable ["CLDW_CurrentTarget", _target, true];
                            _minDistanceToTarget = 1.2;
                            _lastValidTargetPos = getPosASLVisual _target;
                            _smoothedInterceptPos = _lastValidTargetPos;

                            diag_log format ["CLDW [Retarget]: Vehicle '%1' is empty. Retargeting to dismounted passenger '%2' at %3m.", 
                                typeOf _targetVeh, name _target, round (_currentPos distance _target)];
                            if (missionNamespace getVariable ["ddtDebug", false]) then {
                                systemChat format ["CLDW: Target vehicle empty! Retargeting to dismounted passenger %1.", name _target];
                            };
                        } else {
                            // Dismounted candidates exist but behind terrain, or no LOS; if safe distance, disengage
                            if (_dist > 25) then {
                                _emptyVehicleDisengaged = true;
                            };
                        };
                    } else {
                        // Vehicle is completely empty with no dismounted hostiles nearby
                        if (_dist > 25) then {
                            _emptyVehicleDisengaged = true;
                        };
                    };
                };
            };
        };
    };

    if (_emptyVehicleDisengaged) exitWith {};

    // 3. LOS & Obstacle Check (rate-limited to 0.75s)
    if (time >= _lastLosCheckTime + _losCheckInterval || {_lastLosCheckTime < 0}) then {
        private _losElapsed = ((time - _lastLosCheckTime) max _losCheckInterval) min 1.0;
        _lastLosCheckTime = time;

        private _uavEye = eyePos _drone;
        if (_uavEye isEqualTo [0,0,0]) then { _uavEye = _currentPos vectorAdd [0,0,0.4]; };
        private _targetEye = eyePos _target;
        if (_targetEye isEqualTo [0,0,0]) then { _targetEye = _targetPos vectorAdd [0,0,0.8]; };

        _losBlocked = false;
        _obstacleDistance = 9999;

        if (_dist > _commitDistance) then {
            private _intersections = lineIntersectsSurfaces [_uavEye, _targetEye, _drone, vehicle _target, true, 1, "VIEW", "GEOM"];
            if (count _intersections > 0) then {
                private _hitInfo = _intersections select 0;
                private _hitPos = _hitInfo select 0;
                private _hitObj = _hitInfo select 2;
                _obstacleDistance = _uavEye distance _hitPos;
                if (!isNull _hitObj && {
                    _hitObj isKindOf "Building" ||
                    _hitObj isKindOf "House" ||
                    _hitObj isKindOf "Wall" ||
                    _hitObj isKindOf "Strategic" ||
                    _hitObj isKindOf "NonStrategic"
                }) then { _losBlocked = true; };
            };
            if (!_losBlocked) then {
                _losBlocked = terrainIntersectASL [_uavEye, _targetEye];
            };
        };

        if (_losBlocked) then {
            _targetLostTime = _targetLostTime + _losElapsed;
        } else {
            _targetLostTime = 0;
            _lastValidTargetPos = _targetPos;
        };
    };

    // 3. Dive abort on corridor obstruction
    if (_losBlocked && {_dist > _commitDistance} && {_obstacleDistance < (_dist * 0.85)}) then {
        if (_droneAGL > _minRecoveryAlt) then {
            _diveAborted = true;
            diag_log format ["CLDW [Abort]: '%1' aborting dive — obstacle at %2m, target at %3m, AGL %4m.", typeOf _drone, round _obstacleDistance, round _dist, round _droneAGL];
            if (missionNamespace getVariable ["ddtDebug", false]) then {
                systemChat "CLDW: Obstacle in dive corridor! Aborting.";
            };
        };
    };

    if (_diveAborted) exitWith {};

    if (_targetLostTime > _maxTimeWithoutLOS) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat format ["CLDW: Target lost: LOS blocked for %1s.", round _targetLostTime];
        };
    };

    // =========================================================================
    // 4. DYNAMIC SPEED: boost to always be faster than the target vehicle
    // =========================================================================
    private _targetSpeedMS = (speed (vehicle _target)) / 3.6;
    private _effectiveSpeed = _speed;
    if (_targetSpeedMS > 0) then {
        // Guarantee at least 10 m/s faster than the target to always close the gap
        _effectiveSpeed = _speed max (_targetSpeedMS + 10);
    };
    _drone forceSpeed -1; // Ensure no AI speed cap overrides our velocity

    // =========================================================================
    // 5. LEAD PURSUIT with smoothed intercept prediction
    // =========================================================================
    private _dist2D = _currentPos distance2D _targetPos;
    private _targetVel = velocity (vehicle _target);
    private _timeToTarget = _dist / (_effectiveSpeed max 1);
    // Lead cap: use _predictionTimeCap (AP: 1.5s, AT: 2.5s) — previously this was
    // hardcoded to 3.5s, causing drones to aim metres ahead of stationary/slow infantry.
    private _leadTime = (_timeToTarget min _predictionTimeCap) max 0;
    private _rawPredictedPos = _targetPos vectorAdd (_targetVel vectorMultiply _leadTime);

    // Adaptive smoothing: sticky at long range (stability), fast at close range (accuracy).
    // Within 150m the aim snaps quickly to the real target position instead of lagging behind.
    private _smoothWeight = if (_dist < 150) then { 0.45 } else { 0.25 };
    _smoothedInterceptPos = (_smoothedInterceptPos vectorMultiply (1 - _smoothWeight)) vectorAdd (_rawPredictedPos vectorMultiply _smoothWeight);

    // Swarm lanes converge as the drone closes in. Start converging at 120m (was 50m)
    // so the drone is already tracking the real target centre well before the final dive.
    private _spreadWeight = if (_dist2D > 120) then { 1.0 } else { (_dist2D max 0) / 120.0 };
    private _interceptWithLane = [
        (_smoothedInterceptPos select 0) + ((_laneOffset select 0) * _spreadWeight),
        (_smoothedInterceptPos select 1) + ((_laneOffset select 1) * _spreadWeight),
        (_smoothedInterceptPos select 2)
    ];

    // =========================================================================
    // 6. ALTITUDE PROFILE: approach at height, dive into target
    // =========================================================================
    private _isVehicleOrAir = (!(_target isKindOf "CAManBase")) || {(vehicle _target) isKindOf "LandVehicle"} || {(vehicle _target) isKindOf "Air"} || {(vehicle _target) isKindOf "Ship"};
    private _profileDist = if (_isVehicleOrAir) then { _dist2D * (350 / 500) } else { _dist2D };
    private _deltaZ = switch (true) do {
        case (_profileDist >= 350): { 70.0 };
        case (_profileDist >= 300): { private _t = (_profileDist-300)/50.0; private _s = _t*_t*(3-(2*_t)); 60+(10*_s) };
        case (_profileDist >= 200): { private _t = (_profileDist-200)/100.0; private _s = _t*_t*(3-(2*_t)); 40+(20*_s) };
        case (_profileDist >= 100): { private _t = (_profileDist-100)/100.0; private _s = _t*_t*(3-(2*_t)); 20+(20*_s) };
        case (_profileDist >= 50):  { private _t = (_profileDist-50)/50.0;   private _s = _t*_t*(3-(2*_t)); 10+(10*_s) };
        case (_profileDist >= 10):  { private _t = (_profileDist-10)/40.0;   private _s = _t*_t*(3-(2*_t)); 2.5+(7.5*_s) };
        default { private _t = (_profileDist max 0)/10.0; private _s = _t*_t*(3-(2*_t)); 0.4+(2.1*_s) };
    };
    private _terrainH = getTerrainHeightASL [_interceptWithLane select 0, _interceptWithLane select 1];
    private _minAGL = if (_dist2D > 50) then { 10.0 } else { 0.3 };
    // Apply vehicle aim height correction: aim 2.5m below bounding centre so AT drones
    // hit the vehicle body instead of sailing over the roof during the terminal dive.
    private _aimHeightAdj = if (!_AP && {_isVehicleOrAir}) then { _vehicleAimHeightOffset } else { 0 };
    private _desiredAltASL = ((_targetPos select 2) + _deltaZ + _aimHeightAdj) max (_terrainH + _minAGL);
    private _desiredAimPosASL = [_interceptWithLane select 0, _interceptWithLane select 1, _desiredAltASL];

    // =========================================================================
    // 7. DIRECTION STEERING with turn-rate limit
    // =========================================================================
    private _currentDir = vectorDirVisual _drone;
    private _effectiveTargetPos = if (_losBlocked) then { _lastValidTargetPos } else { _desiredAimPosASL };
    // Inside commit distance aim directly at the raw target, ignore altitude profile
    if (_dist <= _commitDistance) then { _effectiveTargetPos = _targetPos; };
    private _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);

    private _cos = (_currentDir vectorDotProduct _desiredDir) min 1 max -1;
    private _angle = acos _cos;

    // Turn rate: AP drones are nimbler (infantry specialist), AT drones wider arcs
    private _maxTurnRate = if (_AP) then { 55 } else { 42 }; // degrees/second
    private _maxTurnAngle = _maxTurnRate * _deltaTime;
    private _newDir = if (_angle <= 0.01) then {
        _desiredDir
    } else {
        if (_angle <= _maxTurnAngle) then {
            _desiredDir
        } else {
            private _t = _maxTurnAngle / _angle;
            vectorNormalized ((_currentDir vectorMultiply (1-_t)) vectorAdd (_desiredDir vectorMultiply _t))
        }
    };

    // =========================================================================
    // 8. BANKING (ROLL INTO TURNS) + setVectorDirAndUp
    // =========================================================================
    private _yawDemand = (_currentDir select 0)*(_desiredDir select 1) - (_currentDir select 1)*(_desiredDir select 0);
    private _maxBankAngle = if (_AP) then { 50 } else { 40 };
    private _targetRollDeg = ((-_yawDemand min 1) max -1) * _maxBankAngle;
    private _maxRollStep = 120 * _deltaTime;
    private _rollDelta = (_targetRollDeg - _currentRollDeg) min _maxRollStep max (-_maxRollStep);
    _currentRollDeg = _currentRollDeg + _rollDelta;

    // Safe reference up vector (gimbal lock prevention for steep dives)
    private _refUp = [0, 0, 1];
    if (abs (_newDir select 2) > 0.85) then {
        _refUp = vectorUpVisual _drone;
        if ((_refUp vectorCrossProduct _newDir) isEqualTo [0,0,0]) then { _refUp = [0,1,0]; };
    };
    private _rightVector = vectorNormalized (_newDir vectorCrossProduct _refUp);
    if (_rightVector isEqualTo [0,0,0]) then { _rightVector = [1,0,0]; };
    private _normalUp = vectorNormalized (_rightVector vectorCrossProduct _newDir);
    private _radRoll = _currentRollDeg * (pi / 180);
    private _upBanked = (_normalUp vectorMultiply (cos _radRoll)) vectorAdd (_rightVector vectorMultiply (sin _radRoll));
    _drone setVectorDirAndUp [_newDir, _upBanked];

    // =========================================================================
    // 9. VELOCITY — blended inertia then scaled to effective speed
    // The velocity vector always matches _newDir so setVectorDirAndUp and
    // setVelocity are never in conflict; no physics braking force is created.
    // =========================================================================
    private _currentVelDir = vectorNormalized _currentVelocity;
    if (_currentVelDir isEqualTo [0,0,0]) then { _currentVelDir = _newDir; };

    private _accelRate = if (_AP) then { 28 } else { 35 }; // m/s²
    private _maxSpeedChange = _accelRate * _deltaTime;
    private _targetSpeed = if (_currentSpeed < _effectiveSpeed) then {
        (_currentSpeed + _maxSpeedChange) min _effectiveSpeed
    } else {
        (_currentSpeed - _maxSpeedChange) max _effectiveSpeed
    };

    // Inertia blend: AT drones hold momentum in wide arcs; AP drones snap tighter
    private _inertiaBlend = if (_AP) then { 0.22 } else { 0.15 };
    private _newVelDir = vectorNormalized ((_currentVelDir vectorMultiply (1-_inertiaBlend)) vectorAdd (_newDir vectorMultiply _inertiaBlend));
    _drone setVelocity (_newVelDir vectorMultiply _targetSpeed);

    sleep _deltaTime;
};

if (isNull _drone) exitWith {};

// Restore vanilla AI pathing features on exit if drone survives
_drone enableAI "PATH";
if (!isNull (driver _drone)) then {
    (driver _drone) enableAI "PATH";
};

// Manual player takeover exit
if (_playerTookControl) exitWith {
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "CLDW: Player took control of drone; auto-guidance disengaged.";
    };
    _drone enableAI "PATH";
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
    _drone setVariable ["CLDW_Disengaged", false, true];
};

// Empty vehicle disengagement exit: pull up, return to squad and clear target
if (_emptyVehicleDisengaged) exitWith {
    _target setVariable ["CLDW_AssignedDrone", objNull, true];
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
    _drone setVariable ["CLDW_Disengaged", true, true];
    _drone enableAI "PATH";
    if (!isNull (driver _drone)) then {
        (driver _drone) enableAI "PATH";
    };

    // Smooth pull-up maneuver away from vehicle/ground
    private _curVel = velocity _drone;
    _drone setVelocity [(_curVel select 0) * 0.7, (_curVel select 1) * 0.7, 15];

    diag_log format ["CLDW [Disengage]: Target vehicle '%1' is empty. Disengaging at %2m. Returning to squad.", 
        typeOf (vehicle _target), round _dist];
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat format ["CLDW: Target vehicle %1 empty. Disengaging!", typeOf (vehicle _target)];
    };

    [_drone, _lastValidTargetPos, _man] spawn CLDW_fnc_disengage;
};

// =====================================
// 4. DIVE ABORTION / PULL-UP & RE-ENGAGEMENT
// =====================================
if (_diveAborted) exitWith {
    // Re-enable AI and execute smooth pull-up maneuver back to pursuit altitude
    _drone enableAI "PATH";
    
    [_drone, _target, _man, _lastValidTargetPos, _speed, _minDistanceToTarget, _opGrp] spawn {
        params ["_drone", "_target", "_man", "_lastPos", "_speed", "_minDist", "_opGrp"];
        if (isNull _drone || {!alive _drone}) exitWith {};

        _drone enableAI "PATH";
        _drone setSpeedMode "FULL";
        _drone forceSpeed _speed;
        _drone flyInHeight 45;

        // Pull up velocity smoothly
        private _curVel = velocity _drone;
        _drone setVelocity [(_curVel select 0) * 0.7, (_curVel select 1) * 0.7, 14];

        // Calculate an offset vantage position (flank/high altitude) to acquire a clear angle
        private _targetASL = if (!isNull _target && {alive _target}) then { getPosASL _target } else { _lastPos };
        private _droneASL = getPosASL _drone;
        private _dirFromTarget = _targetASL getDir _droneASL;
        private _offsetAngle = (_dirFromTarget + 45) mod 360;
        private _repositionPos = _targetASL vectorAdd [(sin _offsetAngle) * 80, (cos _offsetAngle) * 80, 45];

        (driver _drone) doMove (ASLToAGL _repositionPos);
        _drone doMove (ASLToAGL _repositionPos);

        private _reacquired = false;
        private _searchTimeout = time + 6.0;

        while {alive _drone && {!isNull _target} && {alive _target} && {time < _searchTimeout} && {!_reacquired}} do {
            sleep 0.8; // Rate-limited raycast check during altitude recovery
            if (isNull _drone || {!alive _drone}) exitWith {};

            // Check if clear line of sight is restored from the new angle
            private _uEye = eyePos _drone;
            private _tEye = eyePos _target;
            if (_tEye isEqualTo [0,0,0]) then { _tEye = (getPosASL _target) vectorAdd [0,0,1]; };

            private _blocked = terrainIntersectASL [_uEye, _tEye];
            if (!_blocked) then {
                private _hits = lineIntersectsSurfaces [_uEye, _tEye, _drone, vehicle _target, true, 1, "VIEW", "GEOM"];
                if (count _hits == 0) then {
                    _reacquired = true;
                };
            };

            if (_reacquired) exitWith {
                if (missionNamespace getVariable ["ddtDebug", false]) then {
                    systemChat "CLDW: Unobstructed attack corridor established. Resuming dive!";
                };
                [_drone, _target, _speed, _minDist] spawn CLDW_fnc_guideToTarget;
            };
        };

        // If target remains completely inaccessible after search, disengage to squad
        if (!_reacquired && {alive _drone}) then {
            _drone enableAI "PATH";
            _drone setVariable ["CLDW_Disengaged", true, true];
            _drone setVariable ["CLDW_CurrentTarget", objNull, true];
            [_drone, _lastPos, _man] spawn CLDW_fnc_disengage;
        };
    };
};

// Operator recovery
_man = _drone getVariable ["CLDW_CurrentOperator", objNull];
if (isNull _man || {!alive _man}) then {
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

// Determine terminal exit outcome
private _targetDied    = (!alive _target);
private _losLost       = (_targetLostTime > _maxTimeWithoutLOS);
private _outOfRange    = (_dist > _maxTargetDistance);
private _targetActualDist = (getPosASLVisual _drone) distance (getPosASLVisual (vehicle _target));
private _closeEnough   = (_dist <= (_minDistanceToTarget + 2.5)) || (_targetActualDist <= (_minDistanceToTarget + 2.5)) || (!alive _drone && {_dist < 15});
private _lowAlt        = ((getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone)) < _minRecoveryAlt);

diag_log format ["CLDW [GuidanceExit]: '%1' targeting '%2' — closeEnough:%3 targetDied:%4 losLost:%5 outOfRange:%6 lowAlt:%7 dist:%8m.",
    typeOf _drone, typeOf _target, _closeEnough, _targetDied, _losLost, _outOfRange, _lowAlt, round _dist];

if (_closeEnough) then {
    // Normal terminal impact - drone mod handles its own explosion and deletion
    diag_log format ["CLDW [Impact]: '%1' terminal contact with '%2' at %3m (AP: %4).", typeOf _drone, typeOf _target, round _dist, _AP];
    _drone setFuel 0;

    // Tag victim for Antistasi / RIS scoring
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

    // If drone is still alive after contacting the target, trigger fatal damage so its native mod handler fires
    if (alive _drone) then {
        _drone setDamage 1;
    };

} else {
    if (_targetDied && {_lowAlt}) then {
        // Target died while drone was in unrecoverable low altitude dive
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

        if (alive _drone) then {
            _drone setDamage 1;
        };
    } else {
        if (_outOfRange || _targetDied) then {
            // Target dead or out of range: disengage cleanly
            if (alive _drone && {!isNull _man}) then {
                _drone enableAI "PATH";
                if (!isNull (driver _drone)) then {
                    (driver _drone) enableAI "PATH";
                };
                _drone setVariable ["CLDW_Disengaged", true, true];
                [_drone, _lastValidTargetPos, _man] spawn CLDW_fnc_disengage;
            } else {
                _drone setFuel 0;
            };
        } else {
            // Lost sight: pull up to search altitude and re-acquire
            if (alive _drone && {!isNull _man}) then {
                _drone enableAI "PATH";
                if (!isNull (driver _drone)) then {
                    (driver _drone) enableAI "PATH";
                };
                _drone setVariable ["CLDW_Disengaged", false, true];
                _drone setVariable ["CLDW_CurrentTarget", objNull, true];
                _drone flyInHeight 40;
                (driver _drone) doMove (ASLToAGL _lastValidTargetPos);
                
                [_drone, _man, _lastValidTargetPos] spawn {
                    params ["_drone", "_man", "_lastPos"];
                    sleep 2.5;
                    if (!isNull _drone && {alive _drone} && {!isNull _man} && {alive _man}) then {
                        private _targets = [_drone, missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000]] call CLDW_fnc_getTargetsAT;
                        if (count _targets > 0) then {
                            private _target = _targets select 0;
                            private _speed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6;
                            _drone setVariable ["CLDW_CurrentTarget", _target, true];
                            [_drone, _target, _speed, 0.1] spawn CLDW_fnc_guideToTarget;
                        } else {
                            [_drone, _lastPos, _man] spawn CLDW_fnc_disengage;
                        };
                    };
                };
            };
        };
    };
};
