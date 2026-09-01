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
private _speed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6; // Convert km/h to m/s

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

// Temporarily isolate drone crew into an independent group to prevent squad command interference
private _droneCrew = crew _drone;
private _tempGrp = grpNull;
private _hasSplitGroup = false;

if (count _droneCrew > 0) then {
    private _originalGrp = group (_droneCrew select 0);
    if (!isNull _opGrp && {_originalGrp == _opGrp}) then {
        _tempGrp = createGroup (side _drone);
        _droneCrew joinSilent _tempGrp;
        _hasSplitGroup = true;
    };
};

// 2. Enable Vanilla AI piloting & flight model
_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone forceSpeed _speed;
(group (driver _drone)) setSpeedMode "FULL";
(group (driver _drone)) setBehaviour "CARELESS";
(group (driver _drone)) setCombatMode "BLUE";

// Disable collision between nearby UAVs to prevent mid-air team collisions
private _nearDrones = nearestObjects [_drone, ["UAV", "Air"], 300];
{
    if (_x != _drone) then {
        _drone disableCollisionWith _x;
        _x disableCollisionWith _drone;
    };
} forEach _nearDrones;

// Unique swarm lane offset to prevent multiple drones attacking the same target from flying in single-file
private _droneIdNum = (parseNumber (str _drone select [count (str _drone) - 3])) max 0;
private _laneAngle = ((_droneIdNum mod 8) * 45);
private _laneDist = (((_droneIdNum mod 3) + 1) * 3.5); // 3.5m to 10.5m lateral separation
private _laneOffset = [sin _laneAngle * _laneDist, cos _laneAngle * _laneDist];

// =====================================
// 2. TRACKING & LOS VALIDATION STATE
// =====================================
private _targetLostTime = 0;
private _maxTargetDistance = (missionNamespace getVariable ["CLDW_Setting_MaxRange", 750]) + 400;
private _maxTimeWithoutLOS = 3.5; // Seconds before aborting engagement on lost sight
private _commitDistance    = 15;  // Point of no return where drone commits fully to terminal impact

private _deltaTime = 0.05; // 20 Hz smooth guidance loop
private _targetPos = getPosASLVisual _target;
private _lastValidTargetPos = getPosASLVisual _target;
private _dist = 9999;
private _minRecoveryAlt = 10; // Minimum altitude (m AGL) to safely execute a dive abort
private _lastWpUpdateTime = 0;

private _playerTookControl = false;
private _diveAborted = false;

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
    
    private _currentPos = getPosASLVisual _drone;
    _targetPos = getPosASLVisual _target;
    _dist = _currentPos distance _targetPos;

    // Contact threshold scaled by drone speed
    private _currentVelocity = velocity _drone;
    private _currentSpeed = vectorMagnitude _currentVelocity;
    private _frameStep = (_currentSpeed * _deltaTime) max 1.5;
    private _detonationDistance = (_minDistanceToTarget + _frameStep) max 2.5;

    // Terminal proximity reached -> trigger explosion
    if (_dist <= _detonationDistance) exitWith {};

    // 1. Engagement Range Guard
    if (_dist > _maxTargetDistance) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "CLDW: Target exceeded maximum engagement range.";
        };
    };

    // 2. Strict Raycast LOS & Anti-Wallhack Occlusion Check
    private _uavEye = eyePos _drone;
    if (_uavEye isEqualTo [0,0,0]) then { _uavEye = _currentPos vectorAdd [0,0,0.4]; };
    private _targetEye = eyePos _target;
    if (_targetEye isEqualTo [0,0,0]) then { _targetEye = _targetPos vectorAdd [0,0,0.8]; };

    private _losBlocked = false;
    private _obstacleDistance = 9999;

    if (_dist > _commitDistance) then {
        // Check structural intersections (buildings, houses, walls, static objects)
        private _intersections = lineIntersectsSurfaces [_uavEye, _targetEye, _drone, vehicle _target, true, 1, "VIEW", "GEOM"];
        if (count _intersections > 0) then {
            private _hitInfo = _intersections select 0;
            private _hitPos = _hitInfo select 0;
            private _hitObj = _hitInfo select 2;
            _obstacleDistance = _uavEye distance _hitPos;

            // Block if hitting a building, wall, or landscape structure
            if (!isNull _hitObj && { 
                _hitObj isKindOf "Building" || 
                _hitObj isKindOf "House" || 
                _hitObj isKindOf "Wall" || 
                _hitObj isKindOf "Strategic" || 
                _hitObj isKindOf "NonStrategic" 
            }) then {
                _losBlocked = true;
            };
        };

        // Check terrain occlusion (mountains, hills, ridgelines)
        if (!_losBlocked) then {
            _losBlocked = terrainIntersectASL [_uavEye, _targetEye];
        };
    };

    // 3. Dynamic Dive Abortion on Flight Corridor Obstruction
    if (_losBlocked && {_dist > _commitDistance} && {_obstacleDistance < (_dist * 0.85)}) then {
        private _droneAGL = (getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone));
        if (_droneAGL > _minRecoveryAlt) then {
            _diveAborted = true;
            if (missionNamespace getVariable ["ddtDebug", false]) then {
                systemChat "CLDW: Obstacle detected in dive corridor! Aborting terminal dive to recalculate.";
            };
        };
    };

    if (_diveAborted) exitWith {};

    if (_losBlocked) then {
        _targetLostTime = _targetLostTime + _deltaTime;
    } else {
        _targetLostTime = 0;
        _lastValidTargetPos = _targetPos;
    };

    // Abort if line of sight is continuously lost
    if (_targetLostTime > _maxTimeWithoutLOS) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat format ["CLDW: Target lost: LOS blocked for %1s.", round _targetLostTime];
        };
    };

    // =========================================================================
    // 4. PROGRESSIVE ALTITUDE-BY-DISTANCE PROFILE & DYNAMIC DESCENT CALCULATION
    // =========================================================================
    private _dist2D = _currentPos distance2D _targetPos;
    private _dist3D = _dist;
    private _targetVel = velocity (vehicle _target);

    // Dynamic Lead Compensation:
    private _timeToTarget = _dist3D / (_speed max 1);
    private _leadTime = if (_dist2D < 50) then {
        // Pre-impact dynamic lead tracking target velocity
        (_timeToTarget min 0.6) max 0.02
    } else {
        // Long-range trajectory lead
        (_timeToTarget min 1.2) max 0.0
    };
    private _leadOffset = _targetVel vectorMultiply _leadTime;

    // Swarm lateral spread: maintains separation during approach and converges at < 50m
    private _spreadWeight = if (_dist2D > 50) then { 1.0 } else { (_dist2D max 0) / 50.0 };
    private _aimPos2D = [
        (_targetPos select 0) + (_leadOffset select 0) + ((_laneOffset select 0) * _spreadWeight),
        (_targetPos select 1) + (_leadOffset select 1) + ((_laneOffset select 1) * _spreadWeight)
    ];

    // Distance-to-Altitude Profile & Staging (Smoothstep Cubic Hermite Interpolation)
    // Establishing a 30° descent glide corridor without sudden pitch jerks:
    // - Distance > 350m: High-altitude cruise at 70m AGL (60-80m)
    // - 300m -> 200m: Transition phase (60m -> 40m AGL)
    // - 200m -> 100m: Dive initiation (40m -> 20m AGL)
    // - 100m -> 50m: Terminal guidance (20m -> 10m AGL)
    // - 50m -> 10m: Pre-impact alignment (10m -> 2.5m AGL)
    // - < 10m to 0m: Final strike point (direct center impact)
    private _deltaZ = switch (true) do {
        case (_dist2D >= 350): { 70.0 };
        case (_dist2D >= 300): {
            private _t = (_dist2D - 300) / 50.0;
            private _s = _t * _t * (3.0 - (2.0 * _t)); // Smoothstep cubic Hermite lerp
            60.0 + (10.0 * _s)
        };
        case (_dist2D >= 200): {
            private _t = (_dist2D - 200) / 100.0;
            private _s = _t * _t * (3.0 - (2.0 * _t));
            40.0 + (20.0 * _s)
        };
        case (_dist2D >= 100): {
            private _t = (_dist2D - 100) / 100.0;
            private _s = _t * _t * (3.0 - (2.0 * _t));
            20.0 + (20.0 * _s)
        };
        case (_dist2D >= 50): {
            private _t = (_dist2D - 50) / 50.0;
            private _s = _t * _t * (3.0 - (2.0 * _t));
            10.0 + (10.0 * _s)
        };
        case (_dist2D >= 10): {
            private _t = (_dist2D - 10) / 40.0;
            private _s = _t * _t * (3.0 - (2.0 * _t));
            2.5 + (7.5 * _s)
        };
        default {
            private _t = (_dist2D max 0) / 10.0;
            private _s = _t * _t * (3.0 - (2.0 * _t));
            0.4 + (2.1 * _s)
        };
    };

    // Guidance & Trajectory Constraints:
    // Ensure no premature low-altitude leveling (drone never drops below 10m AGL when dist2D > 50m)
    private _terrainH = getTerrainHeightASL _aimPos2D;
    private _minAGL = if (_dist2D > 50) then { 10.0 } else { 0.3 };
    private _desiredAltASL = ((_targetPos select 2) + _deltaZ) max (_terrainH + _minAGL);
    private _desiredAimPosASL = [_aimPos2D select 0, _aimPos2D select 1, _desiredAltASL];

    // Update Vanilla AI Waypoint and AGL Altitude smoothly
    _drone flyInHeight (_deltaZ max 2.0);
    if (time > _lastWpUpdateTime + 0.3) then {
        _lastWpUpdateTime = time;
        (driver _drone) doMove (ASLToAGL _desiredAimPosASL);
    };

    // =========================================================================
    // 5. 3D GLIDE SLOPE VECTOR PROPULSION & TERMINAL STRIKE
    // =========================================================================
    // Direction vector pointing directly along the calculated 3D descent glide corridor
    private _dirToAim = vectorNormalized (_desiredAimPosASL vectorDiff _currentPos);
    private _desiredVel = _dirToAim vectorMultiply _speed;

    if (_dist > _commitDistance) then {
        // Physics-based acceleration limits (max 12.0 m/s²): prevents instantaneous 0-to-100% snap
        // Drones take ~2.5s to build full top speed and retain realistic momentum during turns
        private _velDiff = _desiredVel vectorDiff _currentVelocity;
        private _diffMag = vectorMagnitude _velDiff;
        private _maxDeltaV = 12.0 * _deltaTime; // Max 12 m/s² acceleration rate
        
        private _newVel = if (_diffMag <= _maxDeltaV) then {
            _desiredVel
        } else {
            _currentVelocity vectorAdd ((vectorNormalized _velDiff) vectorMultiply _maxDeltaV)
        };
        _drone setVelocity _newVel;
    } else {
        // Terminal strike (< 15m): smooth kinetic closure into target with natural inertia
        private _strikeDir = vectorNormalized (_targetPos vectorDiff _currentPos);
        private _desiredStrikeVel = _strikeDir vectorMultiply _speed;
        private _velDiff = _desiredStrikeVel vectorDiff _currentVelocity;
        private _diffMag = vectorMagnitude _velDiff;
        private _maxDeltaV = 16.0 * _deltaTime;
        
        private _newVel = if (_diffMag <= _maxDeltaV) then {
            _desiredStrikeVel
        } else {
            _currentVelocity vectorAdd ((vectorNormalized _velDiff) vectorMultiply _maxDeltaV)
        };
        _drone setVelocity _newVel;
    };

    sleep _deltaTime;
};

if (isNull _drone) exitWith {};

// Manual player takeover exit
if (_playerTookControl) exitWith {
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "CLDW: Player took control of drone; auto-guidance disengaged.";
    };
    _drone enableAI "PATH";
    _drone enableAI "MOVE";
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
    _drone setVariable ["CLDW_Disengaged", false, true];
};

// =====================================
// 4. DIVE ABORTION / PULL-UP & RE-ENGAGEMENT
// =====================================
if (_diveAborted) exitWith {
    // Re-enable AI and execute smooth pull-up maneuver back to pursuit altitude
    _drone enableAI "PATH";
    _drone enableAI "MOVE";
    
    [_drone, _target, _man, _lastValidTargetPos, _speed, _minDistanceToTarget, _opGrp, _tempGrp, _hasSplitGroup] spawn {
        params ["_drone", "_target", "_man", "_lastPos", "_speed", "_minDist", "_opGrp", "_tempGrp", "_hasSplitGroup"];
        if (isNull _drone || {!alive _drone}) exitWith {};

        _drone enableAI "PATH";
        _drone enableAI "MOVE";
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
            sleep 0.4;
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
            if (_hasSplitGroup && {!isNull _opGrp}) then {
                (crew _drone) joinSilent _opGrp;
                deleteGroup _tempGrp;
            };
            _drone enableAI "PATH";
            _drone enableAI "MOVE";
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
private _closeEnough   = (_dist <= (_minDistanceToTarget + 4.0)) || (!alive _drone && {_dist < 12});
private _lowAlt        = ((getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone)) < _minRecoveryAlt);

if (_closeEnough) then {
    // Normal terminal impact
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
    } else {
        if (_outOfRange || _targetDied) then {
            // Target dead or out of range: disengage cleanly
            if (alive _drone && {!isNull _man}) then {
                if (_hasSplitGroup && {!isNull _opGrp}) then {
                    (crew _drone) joinSilent _opGrp;
                    deleteGroup _tempGrp;
                };
                _drone enableAI "PATH";
                _drone enableAI "MOVE";
                _drone setVariable ["CLDW_Disengaged", true, true];
                [_drone, _lastValidTargetPos, _man] spawn CLDW_fnc_disengage;
            } else {
                _drone setFuel 0;
            };
        } else {
            // Lost sight: pull up to search altitude and re-acquire
            if (alive _drone && {!isNull _man}) then {
                if (_hasSplitGroup && {!isNull _opGrp}) then {
                    (crew _drone) joinSilent _opGrp;
                    deleteGroup _tempGrp;
                };
                _drone enableAI "PATH";
                _drone enableAI "MOVE";
                _drone setVariable ["CLDW_Disengaged", false, true];
                _drone setVariable ["CLDW_CurrentTarget", objNull, true];
                _drone flyInHeight 40;
                (driver _drone) doMove (ASLToAGL _lastValidTargetPos);
                
                [_drone, _man, _lastValidTargetPos] spawn {
                    params ["_drone", "_man", "_lastPos"];
                    sleep 2.5;
                    if (!isNull _drone && {alive _drone} && {!isNull _man} && {alive _man}) then {
                        private _targets = [_drone, 750] call CLDW_fnc_getTargetsAT;
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
