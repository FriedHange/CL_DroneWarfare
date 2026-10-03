/*
    File: fn_guideToTarget.sqf
    Author: Carl Lorenzo
    Description:
        Refactored drone pursuit and terminal engagement guidance.
        Features:
        1. Controlled infantry pursuit and fast vehicle interception.
        2. High vantage approach altitude (35m AGL) during chase phase; transitions into terminal dive within 80m.
        3. Smooth 3D velocity and orientation blending without midair stutter or freezing.
        4. Strict raycast LOS & anti-wallhack validation against terrain and building structures.
        5. Obstacle-aware approaches and persistent verified indoor entry routes.
        6. Mod-native destruction hooks for Crocus, KVN, UAFPV, and universal drones.
*/

params [["_drone", objNull], ["_target", objNull], ["_speedInput", 0], ["_minDistanceToTarget", 0.1]];

if (isNull _drone || {isNull _target} || {!alive _drone} || {!alive _target}) exitWith {};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
private _assigned = _drone getVariable ["CLDW_AssignedOperator",objNull];
if (_drone getVariable ["CLDW_Orphaned",false] ||
    {_drone getVariable ["CLDW_OperatorBound",false] && {isNull _assigned || {!alive _assigned}}}) exitWith {};

// Only FPV suicide drones perform physical terminal dive guidance.
// Non-combat drones (AL-6 Pelican, AR-2 Darter, etc.) and Dropper / Bomber drones must NEVER suicide dive.
private _role = [_drone] call CLDW_fnc_getDroneRole;

if (_role != "SUICIDE") exitWith {
    diag_log format ["CLDW [Guide]: Intercepted non-suicide drone '%1' (role: %2). Aborting suicide dive guidance.", typeOf _drone, _role];

    // Dropper drones delegate to level-flight bomb release if DDT is loaded, otherwise safely loiter at bombing altitude
    if (_role == "DROPPER") then {
        private _dropperSpeed = ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 12;
        _drone setSpeedMode "NORMAL";
        _drone forceSpeed _dropperSpeed;
        _drone flyInHeight 80;

        if (!isNil "DDT_fnc_GuideToTargetBomber") then {
            [_drone, _target] spawn DDT_fnc_GuideToTargetBomber;
        } else {
            _drone enableAI "PATH";
            [_drone, getPosATL _target] call CLDW_fnc_move;
        };
    } else {
        // NONCOMBAT drones (AL-6 Pelican, Darter, Medical, Recon): NEVER attack or dive! Follow operator at safe altitude
        _drone enableAI "PATH";
        _drone flyInHeight 40;
        _drone setSpeedMode "NORMAL";
        _drone forceSpeed (38 / 3.6);
        private _op = _drone getVariable ["CLDW_CurrentOperator", objNull];
        if (isNull _op) then { _op = _drone getVariable ["ddtOwner", objNull]; };
        if (!isNull _op && {alive _op}) then {
            [_drone, getPosATL _op] call CLDW_fnc_move;
        };
    };
};

private _droneType = typeOf _drone;
private _lowerType = toLower _droneType;
private _isKamikaze = true;

// Target classification available in outer scope everywhere
private _isVehicleOrAir = (!(_target isKindOf "CAManBase")) || {(vehicle _target) isKindOf "LandVehicle"} || {(vehicle _target) isKindOf "Air"} || {(vehicle _target) isKindOf "Ship"};

// =====================================
// 1. UNIFIED SPEED & PAYLOAD CONFIGURATION
// =====================================
private _maxDiveSpeed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6; // Convert km/h to m/s
private _speed = _maxDiveSpeed;
private _searchBoostPending = _isVehicleOrAir &&
    {_drone getVariable ["CLDW_SearchAttackBoost", false]};
private _searchBoostUntil = -1;
private _tightTurn = false;
private _turnYaw = getDir _drone;
_drone setVariable ["CLDW_SearchAttackBoost", false];
private _fastTargetThreshold = 8;
private _fastTargetLeadOffset = 1.2; // Lead forward along velocity vector into engine/chassis
private _vehicleDiveDistance = 500;
private _vehicleAimHeightOffset = 0.2; // Aim at upper chassis/roof/engine deck, NOT underground!

private _AP = [_drone] call CLDW_fnc_isAPDrone;

// Detonation contact tolerance based on target bounding volume
if (_isVehicleOrAir) then {
    private _targetVeh = vehicle _target;
    private _bbox = boundingBoxReal _targetVeh;
    private _p1 = _bbox select 0;
    private _p2 = _bbox select 1;
    private _vehHalfLen = (abs ((_p2 select 1) - (_p1 select 1)) * 0.5) max 1.2;
    private _vehHalfWid = (abs ((_p2 select 0) - (_p1 select 0)) * 0.5) max 1.0;
    // For vehicles, contact radius is scaled so drone penetrates into bounding volume before exit
    _minDistanceToTarget = ((_vehHalfLen min _vehHalfWid) * 0.8) max 1.4;
} else {
    _minDistanceToTarget = 1.2; // Infantry
};

// Lead cap: AP targets infantry â€” tight, short lead (1.5s). AT targets vehicles â€” wider pursuit arc (2.5s).
private _predictionTimeCap = if (_AP) then { 1.5 } else { 8.0 };

// boundingCenter is the model origin, which need not be inside a vehicle's hull.
private _vehicleCenterASL = {
    params ["_vehicle"];
    private _box = boundingBoxReal _vehicle;
    private _center = ((_box select 0) vectorAdd (_box select 1)) vectorMultiply 0.5;
    AGLToASL (_vehicle modelToWorldVisual _center)
};

if (missionNamespace getVariable ["ddtDebug", false]) then {
    systemChat format ["CLDW: FPV engaging %1 with maximum speed %2 km/h", typeOf _target, round (_speed * 3.6)];
};

// Operator & group resolution
private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
if (isNull _opGrp && {!isNull _man}) then { _opGrp = group _man; };
if ((isNull _man || {!alive _man}) && {!(_drone getVariable ["CLDW_OperatorBound",false])}) then {
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

private _droneSide = _drone getVariable ["CLDW_DroneSide", sideUnknown];
if (_droneSide == sideUnknown || {_droneSide == civilian}) then {
    if (!isNull _opGrp) then {
        _droneSide = side _opGrp;
    } else {
        if (!isNull _man && {alive _man}) then {
            _droneSide = side group _man;
        } else {
            _droneSide = side _drone;
        };
    };
};
if (_droneSide == sideUnknown || {_droneSide == civilian}) then {
    private _cfgSideNum = getNumber (configFile >> "CfgVehicles" >> (typeOf _drone) >> "side");
    switch (_cfgSideNum) do {
        case 0: { _droneSide = east; };
        case 1: { _droneSide = west; };
        case 2: { _droneSide = independent; };
    };
};
if (_droneSide == sideUnknown) then { _droneSide = civilian; };
_drone setVariable ["CLDW_DroneSide", _droneSide, true];

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
_driverUnit disableAI "PATH";
_drone disableAI "PATH";
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
private _laneDistBase = if (_AP) then { 1.5 } else { 3.0 }; // AP: 1.5â€“4.5m  AT: 3â€“9m
private _laneDist = ((_droneIdNum mod 3) + 1) * _laneDistBase;
private _laneOffset = [sin _laneAngle * _laneDist, cos _laneAngle * _laneDist];

// =====================================
// 2. TRACKING & LOS VALIDATION STATE
// =====================================
private _impactSide = if (!isNull _man) then { side group _man } else { sideUnknown };
if (!isNull _target) then {
    _target setVariable ["CLDW_LastDroneAttacker", _man, true];
    _target setVariable ["CLDW_LastDroneAttackerTime", time, true];
    _target setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
    private _tgtVeh = vehicle _target;
    if (_tgtVeh != _target) then {
        {
            _x setVariable ["CLDW_LastDroneAttacker", _man, true];
            _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
            _x setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
        } forEach (crew _tgtVeh);
    };
};

private _startTime = time;
private _targetLostTime = 0;
private _maxTargetDistance = missionNamespace getVariable ["CLDW_Setting_MaxRange", 750];
// Commit distance: drone must start direct-aiming at the target early enough to correct its heading.
// At 150 km/h (41.7 m/s) and 55 deg/s turn rate, correcting a 30 deg error needs ~0.55s = ~23m.
// AP targets infantry (small hitbox) so needs a longer commit window than AT vs vehicles.
private _commitDistance = if (_AP) then { 70 } else { 80 };

private _deltaTime = 0.05;
private _nextAimTime = -1;
private _aimTarget = objNull;
private _sampledAimPos = [0,0,0];
private _sampledAimVel = [0,0,0];
private _lastTickTime = time;
private _losCheckInterval = 0.75; // Rate-limit obstacle raycasts to 0.75s (optimized for large battles)
private _lastLosCheckTime = -1;
private _emptyCheckInterval = 3.0; // Check vehicle occupancy every 3.0s (optimized for large battles)
private _lastEmptyCheckTime = -1;
private _losBlocked = false;
private _obstacleDistance = 9999;
private _targetPos = getPosASLVisual _target;
private _lastValidTargetPos = _drone getVariable ["CLDW_LastSeenPosASL",getPosASLVisual _target];
private _lastValidTargetVel = _drone getVariable ["CLDW_LastSeenVelocity",[0,0,0]];
private _lastValidTargetTime = _drone getVariable ["CLDW_LastSeenTime",-100];
if (_drone getVariable ["CLDW_LastSeenTarget",objNull] != _target) then {
    _lastValidTargetTime = -100;
    _lastValidTargetPos = getPosASLVisual _drone;
    _lastValidTargetVel = [0,0,0];
};
private _dist = 9999;
private _impactDistance = 9999;
private _minRecoveryAlt = 10;
private _currentRollDeg = 0;
private _smoothedInterceptPos = _lastValidTargetPos;
private _closestPass = 1e6;
private _missRecoveryUntil = 0;
private _missSide = 1;

private _playerTookControl = false;
private _diveAborted = false;
private _emptyVehicleDisengaged = false;
private _undercoverBreak = false;
private _routeBlocked = false;
private _boardedIneligible = false;
private _routeBox = boundingBoxReal _drone;
private _routeExtent = 0.35;
if (count _routeBox == 2) then {
    private _lo = _routeBox select 0;
    private _hi = _routeBox select 1;
    _routeExtent = (((abs (_hi select 0)) max (abs (_lo select 0))) max
        ((abs (_hi select 2)) max (abs (_lo select 2)))) max 0.25 min 0.8;
};
private _attackPlan = _drone getVariable ["CLDW_InitialAttackPlan",[]];
_drone setVariable ["CLDW_InitialAttackPlan",[]];
if !(_attackPlan param [3,false]) then {_attackPlan = [];};
private _attackPhase = 0;
private _nextAttackPlanTime = 0;
private _nextApproachTime = 0;
private _approach = [];
private _approachFinalClear = false;
private _planTargetPos = if (_attackPlan isEqualTo []) then {[0,0,0]} else {_attackPlan select 2};
private _indoorRoute = if (_attackPlan isEqualTo []) then {false} else {_attackPlan select 3};
private _lastVisibleAimPoint = if (_attackPlan isEqualTo []) then {[]} else {_attackPlan select 2};

// =====================================
// 3. MAIN GUIDANCE & ENGAGEMENT LOOP
// =====================================
while {!isNull _drone && {!isNull _target} && {alive _drone} && {!_diveAborted}} do {
    if (_drone getVariable ["CLDW_Orphaned",false] ||
        {_drone getVariable ["CLDW_OperatorBound",false] &&
            {isNull _assigned || {!alive _assigned}}}) exitWith {};
    if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
    if ((count (crew _drone)) < 1) exitWith {};

    // Allow player to take manual control seamlessly
    if ([_drone] call CLDW_fnc_playerPiloting) exitWith {
        _playerTookControl = true;
    };

    // A passenger is no longer a visible infantry hitbox. Transfer guidance
    // to the occupied vehicle only after validating the hull in its own right.
    if (_target isKindOf 'CAManBase' && {vehicle _target != _target}) then {
        private _boarded = vehicle _target;
        if ([_drone,_boarded,_AP] call CLDW_fnc_canAttackVehicle &&
            {[_drone,_boarded] call CLDW_fnc_isEnemy} &&
            {[_drone,_boarded] call CLDW_fnc_hasVisualTarget}) then {
            if (_target getVariable ['CLDW_AssignedDrone',objNull] == _drone) then {
                _target setVariable ['CLDW_AssignedDrone',objNull,true];
            };
            _target = _boarded;
            _target setVariable ['CLDW_AssignedDrone',_drone,true];
            _drone setVariable ['CLDW_CurrentTarget',_target,true];
            _isVehicleOrAir = true;
            _attackPlan = [];
            _indoorRoute = false;
            _approach = [];
            _approachFinalClear = false;
            _losBlocked = false;
            _targetLostTime = 0;
            _lastLosCheckTime = -1;
            _aimTarget = objNull;
            _searchBoostPending = false;
            _searchBoostUntil = -1;
            _lastValidTargetPos = [_target] call _vehicleCenterASL;
            _lastValidTargetVel = velocity _target;
            _lastValidTargetTime = time;
            _drone setVariable ["CLDW_LastSeenTarget",_target];
            _drone setVariable ["CLDW_LastSeenPosASL",_lastValidTargetPos];
            _drone setVariable ["CLDW_LastSeenVelocity",_lastValidTargetVel];
            _drone setVariable ["CLDW_LastSeenTime",time];
            _smoothedInterceptPos = _lastValidTargetPos;
            diag_log format ['CLDW [Boarded]: %1 switched to occupied %2.',typeOf _drone,typeOf _target];
        } else {
            _boardedIneligible = true;
            _targetLostTime = 8;
        };
    };
    if (_boardedIneligible) exitWith {};

    // If target died mid-flight, attempt a quick re-acquisition nearby before disengaging
    if (!alive _target) then {
        private _lastKnownPos = ASLToAGL _lastValidTargetPos;
        private _nearEnemies = (_lastKnownPos nearEntities ["Man", 150]) select {
            alive _x && {[_drone, _x] call CLDW_fnc_isEnemy}
        };
        if (count _nearEnemies == 0) then {
            _nearEnemies = (_lastKnownPos nearEntities [["LandVehicle", "Ship", "Air"], 150]) select {
                alive _x && {[_drone, _x] call CLDW_fnc_isEnemy}
            };
        };

        if (count _nearEnemies > 0) then {
            _nearEnemies = [_nearEnemies, [], { _drone distance _x }, "ASCEND"] call BIS_fnc_sortBy;
            _target = vehicle (_nearEnemies select 0);
            _isVehicleOrAir = (!(_target isKindOf "CAManBase")) || {(vehicle _target) isKindOf "LandVehicle"} || {(vehicle _target) isKindOf "Air"} || {(vehicle _target) isKindOf "Ship"};
            _lastValidTargetPos = getPosASLVisual _drone;
            _lastValidTargetVel = [0,0,0];
            _lastValidTargetTime = -100;
            _targetLostTime = 0;
            _targetPos = _lastValidTargetPos;
            _drone setVariable ["CLDW_CurrentTarget", _target, true];
            diag_log format ["CLDW [QuickRetarget]: '%1' target died mid-flight; retargeted to nearby enemy '%2' at %3m.", typeOf _drone, typeOf _target, round (_drone distance _target)];
        } else {
            _diveAborted = true;
        };
    };
    if (_diveAborted) exitWith {};

    _deltaTime = ((time - _lastTickTime) min 0.15) max 0.02;
    _lastTickTime = time;

    private _currentPos = getPosASLVisual _drone;
    private _targetVeh = vehicle _target;
    _targetPos = if (_isVehicleOrAir) then {
        [_targetVeh] call _vehicleCenterASL
    } else {
        eyePos _target
    };
    if (_targetPos isEqualTo [0,0,0]) then { _targetPos = (getPosASLVisual _target) vectorAdd [0,0,1.0]; };
    // The live position is used only after the visibility ray confirms it.
    private _visualNow = [_drone,_target] call CLDW_fnc_hasVisualTarget;
    _dist = if (_visualNow) then {_currentPos distance _targetPos} else {
        _currentPos distance (_lastValidTargetPos vectorAdd
            (_lastValidTargetVel vectorMultiply (((time - _lastValidTargetTime) max 0) min 2)))
    };
    if (!_visualNow) then {
        _losBlocked = true;
        _targetLostTime = (time - _lastValidTargetTime) max 0;
    };

    // Continuously tag target and nearby units within 80m so attribution is never missed if drone detonates prematurely
    if (_dist < 80 && {time - (_drone getVariable ["CLDW_LastNearTagTime", 0]) > 0.4}) then {
        _drone setVariable ["CLDW_LastNearTagTime", time];
        _target setVariable ["CLDW_LastDroneAttacker", _man, true];
        _target setVariable ["CLDW_LastDroneAttackerTime", time, true];
        _target setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
        private _tgtVeh = vehicle _target;
        if (_tgtVeh != _target) then {
            {
                _x setVariable ["CLDW_LastDroneAttacker", _man, true];
                _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
                _x setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
            } forEach (crew _tgtVeh);
        };
        private _nearMen = (getPosATL _drone) nearEntities ["CAManBase", 40];
        {
            _x setVariable ["CLDW_LastDroneAttacker", _man, true];
            _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
            _x setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
        } forEach _nearMen;
    };

    // Suppress AI launcher/RPG targeting during terminal approach
    if (_dist < 300 && {time - (_drone getVariable ["CLDW_LastLauncherSuppressTime", 0]) > 0.3}) then {
        _drone setVariable ["CLDW_LastLauncherSuppressTime", time];
        private _nearLaunchers = ((getPosATL _drone) nearEntities ["CAManBase", 250]) select {
            !isPlayer _x && {alive _x} && {secondaryWeapon _x != ""}
        };
        {
            if (currentWeapon _x == secondaryWeapon _x) then {
                if (primaryWeapon _x != "") then {
                    _x selectWeapon (primaryWeapon _x);
                } else {
                    if (handgunWeapon _x != "") then {
                        _x selectWeapon (handgunWeapon _x);
                    };
                };
                _x forgetTarget _drone;
            };
        } forEach _nearLaunchers;
    };

    // Only an actual close hull contact ends guidance. A wider exit radius
    // abandoned viable drones after a near pass.
    private _currentVelocity = velocity _drone;
    private _currentSpeed = vectorMagnitude _currentVelocity;

    // Terrain proximity guard: only abort if low altitude while STILL FAR away from target.
    // Inside 40m, diving low into the target is intended terminal behavior!
    private _droneAGL = (getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone));
    private _terrainThreat = (_droneAGL < 0.8 && {_dist > 40});

    private _contactReady = !_losBlocked && {_lastValidTargetTime >= 0} &&
        {_visualNow} && (_isVehicleOrAir || {
        private _contactPoint = if (_losBlocked) then {_attackPlan param [2,_targetPos]} else {_targetPos};
        (!_losBlocked || {_indoorRoute && {_attackPhase == 2}}) && {!_routeBlocked} &&
        {(_attackPlan isEqualTo [] && {_approachFinalClear}) ||
            {!(_attackPlan isEqualTo []) && {_attackPhase == 2}}} &&
        {[_currentPos,_contactPoint,_drone,_target,
            if (_indoorRoute) then {_routeExtent} else {0.35}] call CLDW_fnc_clearFlightPath}
    });
    if ((_contactReady && {_dist <= 0.8}) || _terrainThreat) exitWith {};

    // 1. Engagement Range Guard
    if (!_losBlocked && {_dist > _maxTargetDistance} &&
        {_visualNow}) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "CLDW: Target exceeded maximum engagement range.";
        };
    };

    // Undercover protection (Antistasi / Antistasi Ultimate): break off if the live target
    // became a mission-protected undercover unit (setCaptive true) while the drone was inbound.
    // Shares the empty-check cadence below and never breaks off inside 25m terminal range.
    if ((time >= _lastEmptyCheckTime + _emptyCheckInterval || {_lastEmptyCheckTime < 0}) && {_dist > 25}) then {
        if ([_drone, _target] call CLDW_fnc_isUndercoverProtected) then {
            _undercoverBreak = true;
        };
    };
    if (_undercoverBreak) exitWith {};

    // 2. Empty Vehicle Check & Dismounted Passenger Priority (rate-limited to 3s for large battles)
    if ((time >= _lastEmptyCheckTime + _emptyCheckInterval || {_lastEmptyCheckTime < 0}) && {_dist > 25}) then {
        _lastEmptyCheckTime = time;

        if (missionNamespace getVariable ["CLDW_Setting_PrioritizeDismounted", true]) then {
            if (!(_target isKindOf "CAManBase")) then {
                private _targetVeh = vehicle _target;
                private _baseCrew = crew _targetVeh;
                // crew returns AI; fullCrew includes players riding as passengers/driver (FFV/cargo).
                // Safely inspect unit object (_x select 0) and extract object references to prevent array type mismatch crashes on Linux dedicated servers.
                private _playerCrew = ((fullCrew _targetVeh) select {
                    private _unit = _x select 0;
                    (!isNull _unit) && { isPlayer _unit } && { !(_unit in _baseCrew) }
                }) apply { _x select 0 };
                private _allOccupants = _baseCrew + _playerCrew;
                private _aliveCrew = _allOccupants select { alive _x };
                if (count _aliveCrew == 0) then {
                    // Target vehicle has become empty! Search for dismounted passengers / hostiles near the vehicle
                    private _nearInf = (getPosATL _targetVeh) nearEntities ["CAManBase", 75];
                    private _dismountedCandidates = _nearInf select {
                        alive _x &&
                        {!(_x getVariable ["CLDW_IsDroneCrew", false])} &&
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

                        // Verify LOS to the best candidate (elevated model center to avoid grass/ground occlusions)
                        private _uavEye = eyePos _drone;
                        if (_uavEye isEqualTo [0,0,0]) then { _uavEye = _currentPos vectorAdd [0,0,0.4]; };
                        private _foundCandidate = objNull;
                        {
                            private _eyeCand = eyePos _x;
                            private _candModelCenter = AGLToASL (_x modelToWorldVisual [0, 0, 1]);
                            if (_eyeCand isEqualTo [0,0,0] || {(_eyeCand select 2) < (_candModelCenter select 2)}) then {
                                _eyeCand = _candModelCenter;
                            };
                            if (_eyeCand isEqualTo [0,0,0]) then { _eyeCand = (getPosASL _x) vectorAdd [0,0,1]; };
                            if (!terrainIntersectASL [_uavEye, _eyeCand]) exitWith {
                                _foundCandidate = _x;
                            };
                        } forEach _dismountedCandidates;

                        if (!isNull _foundCandidate) then {
                            // Smoothly switch target to dismounted passenger
                            _target setVariable ["CLDW_AssignedDrone", objNull, true];
                            _target = _foundCandidate;
                            _isVehicleOrAir = false;
                            _target setVariable ["CLDW_AssignedDrone", _drone, true];
                            _drone setVariable ["CLDW_CurrentTarget", _target, true];
                            _minDistanceToTarget = 1.2;
                            _lastValidTargetPos = getPosASLVisual _target;
                            _lastValidTargetVel = velocity (vehicle _target);
                            _lastValidTargetTime = time;
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

        // Ensure raycasts evaluate eyePos _target or _target modelToWorldVisual [0, 0, 1] rather than feet level to avoid grass/ground collision triggers
        private _targetEye = eyePos _target;
        private _modelCenterASL = AGLToASL (_target modelToWorldVisual [0, 0, 1]);
        if (_targetEye isEqualTo [0,0,0] || {(_targetEye select 2) < (_modelCenterASL select 2)}) then {
            _targetEye = _modelCenterASL;
        };
        if (_targetEye isEqualTo [0,0,0]) then { _targetEye = _targetPos vectorAdd [0,0,1.0]; };

        _losBlocked = false;
        _obstacleDistance = 9999;

        if (_dist > 2) then {
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
            // An eye ray may hit a window frame while the torso is visible.
            private _visiblePoint = [_drone,_target] call CLDW_fnc_visibleAimPoint;
            _losBlocked = !_visualNow || {_visiblePoint isEqualTo []};
            if (!_losBlocked) then {_lastVisibleAimPoint = _visiblePoint;};
        } else {
            _losBlocked = !_visualNow;
        };

        if (_losBlocked) then {
            _targetLostTime = (time - _lastValidTargetTime) max 0;
            _approachFinalClear = false;
            _nextApproachTime = 0;
        } else {
            _targetLostTime = 0;
            _lastValidTargetPos = _targetPos;
            _lastValidTargetVel = velocity (vehicle _target);
            _lastValidTargetTime = time;
            _drone setVariable ["CLDW_LastSeenTarget",_target];
            _drone setVariable ["CLDW_LastSeenPosASL",_lastValidTargetPos];
            _drone setVariable ["CLDW_LastSeenVelocity",_lastValidTargetVel];
            _drone setVariable ["CLDW_LastSeenTime",time];
        };
    };
    if (_losBlocked) then {
        _targetLostTime = (time - _lastValidTargetTime) max 0;
        _dist = _currentPos distance (_lastValidTargetPos vectorAdd
            (_lastValidTargetVel vectorMultiply (_targetLostTime min 2)));
    };

    // 3. Dive abort on corridor obstruction (bypassed entirely for strike / kamikaze drones)
    if (!_isKamikaze && {_losBlocked} && {_dist > _commitDistance} && {_obstacleDistance < (_dist * 0.85)}) then {
        if (_droneAGL > _minRecoveryAlt) then {
            _diveAborted = true;
            diag_log format ["CLDW [Abort]: '%1' aborting dive â€” obstacle at %2m, target at %3m, AGL %4m.", typeOf _drone, round _obstacleDistance, round _dist, round _droneAGL];
            if (missionNamespace getVariable ["ddtDebug", false]) then {
                systemChat "CLDW: Obstacle in dive corridor! Aborting.";
            };
        };
    };

    if (_diveAborted) exitWith {};

    // Strike drones must also stop pursuing hidden targets inside commit range.
    private _effectiveMaxLostTime = 10;
    if (_targetLostTime > _effectiveMaxLostTime) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat format ["CLDW: Target lost: LOS blocked for %1s.", round _targetLostTime];
        };
    };

    // Infantry behind cover needs a verified approach before any terminal dive.
    // Keep the chosen route through its stages so the periodic planner cannot
    // repeatedly send the drone back to the beginning of the same approach.
    if (!_isVehicleOrAir && {_dist < 150}) then {
        if (!_indoorRoute && {!_losBlocked} && {time >= _nextAttackPlanTime}) then {
            _nextAttackPlanTime = time + 1;
            private _candidate = [_drone,_target,_lastVisibleAimPoint] call CLDW_fnc_planAttack;
            if (_candidate param [3,false]) then {
                _attackPlan = _candidate;
                _attackPhase = 0;
                _planTargetPos = _targetPos;
                _indoorRoute = true;
                _approach = [];
                _nextAttackPlanTime = time + 0.75;
            };
        };
        if (_indoorRoute && {_attackPhase == 0} && {!_losBlocked} && {time >= _nextAttackPlanTime &&
            {_targetPos distance _planTargetPos > 3}}) then {
            private _newPlan = [_drone,_target,_lastVisibleAimPoint] call CLDW_fnc_planAttack;
            if (_newPlan param [3,false]) then {
                _attackPlan = _newPlan;
                _attackPhase = 0;
                _planTargetPos = _targetPos;
            };
            _nextAttackPlanTime = time + 0.75;
        };
        if (_indoorRoute && {!_losBlocked} && {!_routeBlocked} && {time >= _nextAttackPlanTime}) then {
            _nextAttackPlanTime = time + 0.75;
            if (!_losBlocked && {_attackPhase > 0} &&
                {_targetPos distance _planTargetPos > 3}) then {
                _routeBlocked = true;
            } else {
                private _nextRoutePoint = if (_attackPhase == 0) then {_attackPlan select 0}
                    else {if (_attackPhase == 1) then {_attackPlan select 1} else {_attackPlan select 2}};
                if !([_currentPos,_nextRoutePoint,_drone,_target,_routeExtent] call CLDW_fnc_clearFlightPath) then {
                    _routeBlocked = true;
                };
            };
        };
        if (!_indoorRoute && {!_losBlocked} && {_dist < 90} && {time >= _nextApproachTime}) then {
            _nextApproachTime = time + 0.5;
            private _probeAim = if (_losBlocked) then {_lastValidTargetPos} else {_lastVisibleAimPoint};
            _approach = [_drone,_probeAim,_target,!_losBlocked] call CLDW_fnc_findSafeApproach;
            _approachFinalClear = _approach param [1,false];
            if (_approach isEqualTo []) then {_routeBlocked = true;};
        };
    };
    if (_routeBlocked) exitWith {};

    // A close pass is not an impact. Keep the same target and turn around it
    // until the nose can line up for another verified approach.
    if (!_losBlocked && {!_indoorRoute} && {time >= _missRecoveryUntil}) then {
        _closestPass = _closestPass min _dist;
        if (_closestPass < 8 && {_dist > _closestPass + 3} &&
            {_currentPos distance2D _lastValidTargetPos < 35}) then {
            _missRecoveryUntil = time + 4;
            private _outward = vectorNormalized [(_currentPos select 0) - (_lastValidTargetPos select 0),
                (_currentPos select 1) - (_lastValidTargetPos select 1),0];
            private _cross = (_currentVelocity select 0) * (_outward select 1) -
                (_currentVelocity select 1) * (_outward select 0);
            _missSide = if (_cross >= 0) then {1} else {-1};
            _closestPass = 1e6;
            _drone setVariable ["CLDW_MissedPassCount",
                (_drone getVariable ["CLDW_MissedPassCount",0]) + 1];
        };
    };

    // =========================================================================
    // 4. DYNAMIC SPEED: boost to always be faster than the target vehicle
    // =========================================================================
    private _targetSpeedMS = vectorMagnitude (if (_losBlocked) then {_lastValidTargetVel} else {velocity (vehicle _target)});
    private _effectiveSpeed = _speed;
    if (_targetSpeedMS > 0) then {
        // Fast vehicles need a useful closing speed, including during turns.
        _effectiveSpeed = _speed max ((_targetSpeedMS + 25) min (250 / 3.6));
    };
    _drone forceSpeed -1; // Ensure no AI speed cap overrides our velocity

    // =========================================================================
    // 5. LEAD PURSUIT with smoothed intercept prediction & inertial tracking
    // =========================================================================
    // Inertial tracking / memory buffer: maintain guidance toward last known position & velocity vector
    // for at least 2.5â€“3.0s if line of sight is broken by foliage, trenches, or prone stances
    private _trackingTargetPos = _targetPos;
    private _trackingTargetVel = if (_losBlocked) then {_lastValidTargetVel} else {velocity (vehicle _target)};
    if (_losBlocked) then {
        private _timeSinceLost = (time - _lastValidTargetTime) max 0;
        _trackingTargetPos = _lastValidTargetPos vectorAdd (_lastValidTargetVel vectorMultiply (_timeSinceLost min 2));
        _trackingTargetVel = _lastValidTargetVel;
    };

    // Close to a moving vehicle, even a 0.1 s stale sample misses by metres.
    private _refreshAim = time >= _nextAimTime || {_aimTarget != _target} || {_isVehicleOrAir && {_dist < 100}};
    if (_refreshAim) then {
        _sampledAimPos = _trackingTargetPos;
        _sampledAimVel = _trackingTargetVel;
        _aimTarget = _target;
        _nextAimTime = time + ((missionNamespace getVariable ["CLDW_Setting_AimInterval", 0.1]) max 0.05 min 1);
    };
    _trackingTargetPos = _sampledAimPos;
    _trackingTargetVel = _sampledAimVel;
    private _dist2D = _currentPos distance2D _trackingTargetPos;
    private _targetVel = _trackingTargetVel;
    private _targetSpeedSqr = _targetVel vectorDotProduct _targetVel;
    if (_refreshAim) then {
    private _droneSpeedVal = _effectiveSpeed max 1;
    private _droneSpeedSqr = _droneSpeedVal * _droneSpeedVal;
    private _relPos = _trackingTargetPos vectorDiff _currentPos;
    private _timeToTarget = 0;

    // Exact quadratic intercept time calculation for moving targets
    if (_targetSpeedSqr > 0.25) then {
        private _a = _droneSpeedSqr - _targetSpeedSqr;
        private _b = -2 * (_relPos vectorDotProduct _targetVel);
        private _c = -(_relPos vectorDotProduct _relPos);
        if (_a > 1) then {
            private _disc = (_b * _b) - (4 * _a * _c);
            if (_disc >= 0) then {
                _timeToTarget = ((-_b + sqrt _disc) / (2 * _a)) max 0;
            };
        };
    };
    if (_timeToTarget <= 0) then {
        _timeToTarget = _dist / _droneSpeedVal;
    };

    private _predictionStrength = (missionNamespace getVariable ["CLDW_Setting_PredictionStrength", 100]) max 0 min 100;
    private _leadTime = ((_timeToTarget min (if (_losBlocked) then {0} else {_predictionTimeCap})) max 0) * (_predictionStrength / 100);

    // Forward lead bonus along velocity vector to aim at vehicle engine/center rather than rear bumper
    private _forwardBonus = if (!_losBlocked && {_isVehicleOrAir} && {_targetSpeedSqr > 1.0}) then {
        (vectorNormalized _targetVel) vectorMultiply ((_fastTargetLeadOffset min 1.5) * (_predictionStrength / 100))
    } else {
        [0, 0, 0]
    };
    private _rawPredictedPos = (_trackingTargetPos vectorAdd (_targetVel vectorMultiply _leadTime)) vectorAdd _forwardBonus;

    // Adaptive smoothing: fast at close range (accuracy), snap without lag inside 40m
    private _smoothWeight = if (_dist < 40) then { 0.85 } else { if (_dist < 150) then { 0.55 } else { 0.30 } };
    if (_refreshAim) then {
        _smoothedInterceptPos = (_smoothedInterceptPos vectorMultiply (1 - _smoothWeight)) vectorAdd (_rawPredictedPos vectorMultiply _smoothWeight);
    };

    }; // Expensive intercept calculation runs only on an aim refresh.

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
    // Apply vehicle aim height correction: aim slightly above center for top-attack roof/engine deck strike
    private _aimHeightAdj = if (!_AP && {_isVehicleOrAir}) then { _vehicleAimHeightOffset } else { 0 };
    private _desiredAltASL = ((_trackingTargetPos select 2) + _deltaZ + _aimHeightAdj) max (_terrainH + _minAGL);
    if (_losBlocked) then {
        // Memory pursuit stays above cover; a hidden point is never a dive aim.
        _desiredAltASL = _desiredAltASL max (_terrainH + 25);
    };
    private _desiredAimPosASL = [_interceptWithLane select 0, _interceptWithLane select 1, _desiredAltASL];

    // =========================================================================
    // 7. DIRECTION STEERING with turn-rate limit
    // =========================================================================
    private _currentDir = vectorDirVisual _drone;
    private _effectiveTargetPos = _desiredAimPosASL;
    // Inside commit distance: maintain lead prediction if target is moving!
    // Never revert to raw 0-lead position for moving vehicles!
    if (_dist <= _commitDistance && {!_losBlocked}) then {
        if (_targetSpeedSqr > 0.5) then {
            _effectiveTargetPos = _smoothedInterceptPos;
        } else {
            _effectiveTargetPos = _trackingTargetPos;
        };
    };
    private _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);

    if (!_losBlocked && {!(_attackPlan isEqualTo [])}) then {
        if (_attackPhase == 0 && {_currentPos distance (_attackPlan select 0) < 1.2}) then {
            _attackPhase = 1;
        };
        if (_attackPhase == 1 && {_currentPos distance (_attackPlan select 1) < 0.8}) then {
            _attackPhase = 2;
        };
        if ((_drone getVariable ["CLDW_AttackPhase",-1]) != _attackPhase) then {
            _drone setVariable ["CLDW_AttackPhase",_attackPhase];
            diag_log format ["CLDW [AttackPhase]: %1 phase=%2 range=%3 waypointRange=%4 indoor=%5",
                typeOf _drone,_attackPhase,round _dist,
                round (_currentPos distance (_attackPlan select (_attackPhase min 1))),_attackPlan select 3];
        };
        _indoorRoute = _attackPlan select 3;
        _effectiveTargetPos = if (_attackPhase == 0) then {_attackPlan select 0} else {
            if (_attackPhase == 1) then {_attackPlan select 1} else {_attackPlan select 2}
        };
        _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);
    };
    if (!_losBlocked && {!_isVehicleOrAir} && {!_indoorRoute} && {_dist < 90} && {!(_approach isEqualTo [])}) then {
        _effectiveTargetPos = _approach select 0;
        _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);
    };
    if (time < _missRecoveryUntil && {!_indoorRoute}) then {
        private _radial = vectorNormalized [(_currentPos select 0) - (_trackingTargetPos select 0),
            (_currentPos select 1) - (_trackingTargetPos select 1),0];
        if (_radial isEqualTo [0,0,0]) then {_radial = [sin (getDir _drone),cos (getDir _drone),0];};
        private _tangent = [(_radial select 1) * _missSide,-(_radial select 0) * _missSide,0];
        _effectiveTargetPos = _trackingTargetPos vectorAdd
            ((_radial vectorMultiply 28) vectorAdd (_tangent vectorMultiply 30));
        _effectiveTargetPos set [2,(_currentPos select 2) max
            ((getTerrainHeightASL _effectiveTargetPos) + 12)];
        _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);
        if (_dist > 28 && {abs (((_currentPos getDir _trackingTargetPos) - (getDir _drone) + 540) mod 360 - 180) < 35}) then {
            _missRecoveryUntil = 0;
        };
    };

    // Anticipate rising ground along the actual next leg. A short terrain
    // sample cannot be replaced by the height at the target or intercept.
    private _terrainClimb = 0;
    private _ridgeRange = 0;
    if (!_indoorRoute && {_currentPos distance2D _effectiveTargetPos > 12}) then {
        private _ridge = [_currentPos,_effectiveTargetPos,_currentSpeed,3] call CLDW_fnc_terrainLookahead;
        private _safeASL = _ridge select 0;
        _ridgeRange = _ridge select 1;
        if (_safeASL > (_currentPos select 2) + 0.5) then {
            _terrainClimb = _safeASL - (_currentPos select 2);
            _effectiveTargetPos = +_effectiveTargetPos;
            _effectiveTargetPos set [2,(_effectiveTargetPos select 2) max _safeASL];
            _desiredDir = vectorNormalized (_effectiveTargetPos vectorDiff _currentPos);
        };
    };
    if (_terrainClimb > 0.5) then {_drone setVariable ["CLDW_TerrainAvoidSeen",true];};

    private _cos = (_currentDir vectorDotProduct _desiredDir) min 1 max -1;
    private _angle = acos _cos;
    // Turn level and slowly when the target is behind the drone. Delay the
    // search boost until the nose points into a safe pursuit corridor.
    private _turnHeading = _currentPos getDir _effectiveTargetPos;
    if (!_tightTurn) then {_turnYaw = getDir _drone;};
    private _headingError = ((_turnHeading - _turnYaw + 540) mod 360) - 180;
    if (!_tightTurn && {!_indoorRoute} && {abs _headingError > 75}) then {_tightTurn = true;};
    if (_tightTurn && {abs _headingError < 20}) then {_tightTurn = false;};
    if (!_tightTurn && {_searchBoostPending}) then {
        _searchBoostUntil = time + 2;
        _searchBoostPending = false;
    };

    // Turn rate: AP drones are nimbler (infantry specialist), AT drones wider arcs
    private _maxTurnRate = if (_indoorRoute) then {90} else {
        if (_AP) then { 55 } else { if (_dist < 80) then { 110 } else { 60 } }
    }; // degrees/second
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
    private _targetRollDeg = if (_indoorRoute || {_tightTurn}) then {0} else {((-_yawDemand min 1) max -1) * _maxBankAngle};
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
    if (_tightTurn) then {_drone setDir _turnYaw;};

    // =========================================================================
    // 9. VELOCITY â€” blended inertia then scaled to effective speed
    // The velocity vector always matches _newDir so setVectorDirAndUp and
    // setVelocity are never in conflict; no physics braking force is created.
    // =========================================================================
    private _currentVelDir = vectorNormalized _currentVelocity;
    if (_currentVelDir isEqualTo [0,0,0]) then { _currentVelDir = _newDir; };

    private _accelRate = if (_AP) then { 28 } else { 35 }; // m/sÂ²
    private _maxSpeedChange = _accelRate * _deltaTime;
    private _targetSpeed = if (time < _searchBoostUntil) then {_effectiveSpeed} else {
        if (_currentSpeed < _effectiveSpeed) then {
            (_currentSpeed + _maxSpeedChange) min _effectiveSpeed
        } else {
            (_currentSpeed - _maxSpeedChange) max _effectiveSpeed
        }
    };
    if (_tightTurn) then {
        private _step = (_headingError min (120 * _deltaTime)) max (-120 * _deltaTime);
        _turnYaw = (_turnYaw + _step + 360) mod 360;
        _newDir = [sin _turnYaw,cos _turnYaw,0];
    };
    if (_tightTurn) then {_targetSpeed = _targetSpeed min (if (_indoorRoute) then {6} else {18});};
    if (!_isVehicleOrAir && {_dist < 150} && {time >= _missRecoveryUntil}) then {
        _targetSpeed = _targetSpeed min 15;
    };
    if (_terrainClimb > 0.5) then {
        // Allow time for a 4 m/s climb before the sampled ridge arrives.
        _targetSpeed = _targetSpeed min (((_ridgeRange - 4) max 2) * 4 / _terrainClimb) max 2.5;
    };
    if !(_attackPlan isEqualTo []) then {
        if (_indoorRoute && {_attackPhase == 0} &&
            {_currentPos distance (_attackPlan select 0) < 15}) then {
            _targetSpeed = _targetSpeed min 5;
        };
        if (_attackPhase == 1) then {
            if (_indoorRoute) then {
                _targetSpeed = _targetSpeed min (if (_currentPos distance (_attackPlan select 1) < 6) then {4} else {8});
            } else {
                _targetSpeed = _targetSpeed min 20;
            };
        };
        if (_indoorRoute && {_attackPhase == 2}) then {
            private _entryAngle = acos (((vectorDirVisual _drone) vectorDotProduct
                (vectorNormalized (_effectiveTargetPos vectorDiff _currentPos))) min 1 max -1);
            _targetSpeed = _targetSpeed min (if (_entryAngle > 15) then {2} else {8});
        };
    };

    // Inertia blend: AT drones hold momentum in wide arcs; AP drones snap tighter
    private _inertiaBlend = if (_indoorRoute || {_tightTurn}) then {1.0} else {
        if (_AP) then { 0.22 } else { if (_dist < 80) then { 0.65 } else { 0.25 } }
    };
    private _newVelDir = vectorNormalized ((_currentVelDir vectorMultiply (1-_inertiaBlend)) vectorAdd (_newDir vectorMultiply _inertiaBlend));
    private _newVelocity = _newVelDir vectorMultiply _targetSpeed;
    if (_tightTurn) then {
        private _safeASL = (getTerrainHeightASL _currentPos) + 12;
        _newVelocity set [2,((_safeASL - (_currentPos select 2)) * 0.8) min 3 max -1];
    };
    if (_terrainClimb > 0.5 && {!_tightTurn}) then {
        private _climbDemand = (_terrainClimb / ((_ridgeRange / (_targetSpeed max 2.5)) max 0.5)) min 4;
        private _verticalNow = _currentVelocity select 2;
        _newVelocity set [2,(((_climbDemand min (_verticalNow + 6 * _deltaTime)) max
            (_verticalNow - 6 * _deltaTime)) min 4 max -4)];
    };
    if (_indoorRoute) then {
        // A straight waypoint corridor can still be clipped while turning at
        // its corner. Check the actual next motion before sending velocity.
        private _flightStep = _currentPos vectorAdd (_newVelocity vectorMultiply 0.2);
        if !([_currentPos,_flightStep,_drone,_target,_routeExtent] call CLDW_fnc_clearFlightPath) then {
            _routeBlocked = true;
            _newVelocity = [0,0,0];
        };
    };
    _drone setVelocity _newVelocity;

    sleep 0.05;
};

if (isNull _drone) exitWith {};
if (_drone getVariable ["CLDW_Orphaned",false] ||
    {_drone getVariable ["CLDW_OperatorBound",false] &&
        {isNull _assigned || {!alive _assigned}}}) exitWith {};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};

// Note: AI PATH is selectively restored only in abort/disengage paths below,
// not during terminal contact handoff where AI fighting velocity causes near-misses.

// Manual player takeover exit
if (_playerTookControl) exitWith {
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "CLDW: Player took control of drone; auto-guidance disengaged.";
    };
    _drone enableAI "PATH";
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
    (driver _drone) enableAI "PATH";
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

// Undercover break exit: the target is protected from engagement (e.g. the player went undercover
// mid-attack); clear the assignment, pull up, and return to the squad.
if (_undercoverBreak) exitWith {
    _target setVariable ["CLDW_AssignedDrone", objNull, true];
    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
    _drone setVariable ["CLDW_Disengaged", true, true];
    _drone enableAI "PATH";

    diag_log format ["CLDW [UndercoverBreak]: '%1' target '%2' is undercover-protected. Breaking off and returning to squad.", typeOf _drone, typeOf (vehicle _target)];
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat format ["CLDW: Target %1 is undercover-protected. Breaking off!", typeOf (vehicle _target)];
    };

    [_drone, _lastValidTargetPos, _man] spawn CLDW_fnc_disengage;
};

// An aborted corridor enters the same search at the last confirmed position.
if (_diveAborted) exitWith {
    _drone setVariable ["CLDW_CurrentTarget",objNull,true];
    [_drone,"SEARCH",[_drone,_lastValidTargetPos,_target,_man]] call CLDW_fnc_startController;
};

// Operator recovery
_man = _drone getVariable ["CLDW_CurrentOperator", objNull];
if ((isNull _man || {!alive _man}) && {!(_drone getVariable ["CLDW_OperatorBound",false])}) then {
    if (!isNull _opGrp) then {
        private _aliveUnits = (units _opGrp) select { alive _x };
        if (count _aliveUnits > 0) then {
            _man = leader _opGrp;
            _drone setVariable ["CLDW_CurrentOperator", _man, true];
        };
    };
};

// Determine terminal exit outcome
// SAFETY: Check drone validity before any property access
if (isNull _drone) exitWith {};
private _targetDied    = (!alive _target);
private _losLost       = (_targetLostTime > 10);
private _outOfRange    = (_dist > _maxTargetDistance);
private _droneAlive    = alive _drone;
private _targetVeh     = vehicle _target;
private _vehCenterASL  = if (_isVehicleOrAir) then {
    [_targetVeh] call _vehicleCenterASL
} else {
    eyePos _target
};
if (_vehCenterASL isEqualTo [0,0,0]) then { _vehCenterASL = (getPosASLVisual _target) vectorAdd [0,0,1.0]; };
private _targetActualDist = if (_droneAlive) then { (getPosASLVisual _drone) distance _vehCenterASL } else { _dist };
// Low-altitude near-target = ground-strike terminal contact (drone impacted and Crocus fired its own explosion)
private _lowAlt        = _droneAlive && {!_indoorRoute} &&
    { ((getPosASL _drone select 2) - (getTerrainHeightASL (getPosASL _drone)) < _minRecoveryAlt) };
private _closeEnough   = if (_isVehicleOrAir) then {
    (_targetActualDist <= 1.0) || {!_droneAlive && {_dist < 15}}
} else {
    if (_indoorRoute) then {
        _dist <= 2.0 || {_targetActualDist <= 2.0}
    } else {
        (_dist <= (_minDistanceToTarget + 2.0)) || (_targetActualDist <= (_minDistanceToTarget + 2.0)) || (!_droneAlive && {_dist < 15}) || (_lowAlt && {_dist < 15})
    }
};

if (_routeBlocked) exitWith {
    // No corridor: retain the drone and let exterior search try another angle.
    diag_log format ["CLDW [RouteBlocked]: %1 target=%2 range=%3 phase=%4 plan=%5 los=%6 lost=%7 indoor=%8",
        typeOf _drone,typeOf _target,round _dist,_attackPhase,_attackPlan,
        _losBlocked,_targetLostTime,_indoorRoute];
    _drone setVariable ["CLDW_CurrentTarget",objNull,true];
    _drone setVariable ["CLDW_Disengaged",false,true];
    // Shed any attack velocity before handing a drone near a roof to search.
    _drone setVelocity ((velocity _drone) vectorMultiply 0.1);
    [_drone,"SEARCH",[_drone,_lastValidTargetPos,_target,_man]] call CLDW_fnc_startController;
};

diag_log format ["CLDW [GuidanceExit]: '%1' targeting '%2' â€” closeEnough:%3 targetDied:%4 losLost:%5 outOfRange:%6 lowAlt:%7 dist:%8m.",
    typeOf _drone, typeOf _target, _closeEnough, _targetDied, _losLost, _outOfRange, _lowAlt, round _dist];

if (_closeEnough) then {
    // Normal terminal impact - drone mod handles its own explosion and deletion
    diag_log format ["CLDW [Impact]: '%1' terminal contact with '%2' at %3m (AP: %4).", typeOf _drone, typeOf _target, round _dist, _AP];

    // CRASH FIX: Snapshot operator and near-units BEFORE any detonation call.
    // setDamage 1 / setFuel 0 trigger the KVN/Crocus mod's Killed EH synchronously,
    // which kills and ragdolls _target in the same script tick. Calling nearestObjects
    // or setVariable on a ragdolling object causes ACCESS_VIOLATION (mov rax, [rdx]).
    private _operator = _drone getVariable ["CLDW_CurrentOperator", objNull];
    if (isNull _operator) then { _operator = _drone getVariable ["ddtOwner", objNull]; };
    if (isNull _operator) then { _operator = _man; };
    private _impactSide = if (!isNull _operator) then { side group _operator } else { sideUnknown };

    // Tag victims within 40m of drone impact point so kill handlers and death camera identify the operator
    private _nearUnits = (nearestObjects [_drone, ["CAManBase", "LandVehicle", "Air", "Ship"], 40]) + (nearestObjects [_target, ["CAManBase", "LandVehicle", "Air", "Ship"], 40]);
    if (!isNull _target && {!(_target in _nearUnits)}) then { _nearUnits pushBack _target; };
    if (!isNull _targetVeh) then {
        if !(_targetVeh in _nearUnits) then { _nearUnits pushBack _targetVeh; };
        _nearUnits append (crew _targetVeh);
    };
    {
        if (_x isKindOf "LandVehicle" || {_x isKindOf "Air"} || {_x isKindOf "Ship"}) then {
            _nearUnits append (crew _x);
        };
    } forEach (+_nearUnits);
    _nearUnits = _nearUnits arrayIntersect _nearUnits;

    // Tag victims NOW, before detonation destroys/ragdolls them. Do not check alive _x so killed victims are tagged.
    if (!isNull _operator) then {
        {
            if (!isNull _x) then {
                _x setVariable ["CLDW_LastDroneAttacker", _operator, true];
                _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
                _x setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
            };
        } forEach _nearUnits;
    };

    // Pure Physics Handoff:
    // Impart final forward velocity vector directly toward target at impact speed.
    // If target is moving, lead the velocity vector by target velocity into the hull/engine.
    if (!isNull _target && {alive _target} && {alive _drone}) then {
        private _targetV = velocity _targetVeh;
        private _leadPoint = _smoothedInterceptPos;
        private _dir = _leadPoint vectorDiff (getPosASLVisual _drone);
        private _strikeSpeed = if (_isVehicleOrAir) then {
            ((missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6) max 45
        } else {if (_indoorRoute) then {8} else {15}};
        _drone setVelocity ((vectorNormalized _dir) vectorMultiply _strikeSpeed);
    };

    // Native warheads own damage and fuze failure. Never manufacture damage after a dud.

} else {
    // SAFETY: all fallback paths require a living, local-authority drone.
    // Accessing driver/owner on a dead or non-local drone crashes the dedi server.
    if (isNull _drone) exitWith {};

    if (_targetDied && {_lowAlt}) then {
        // Target died while drone was in unrecoverable low altitude dive.
        // Drone likely impacted the ground; Crocus fires its own native explosion â€” do NOT call setDamage again.
        private _operator = _drone getVariable ["CLDW_CurrentOperator", objNull];
        if (isNull _operator) then { _operator = _drone getVariable ["ddtOwner", objNull]; };
        if (isNull _operator) then { _operator = _man; };
        if (!isNull _operator) then {
            private _impactSide = side group _operator;
            // Use drone position for spatial query â€” target is already dead here
            private _dronePos = getPosATL _drone;
            private _nearUnits = nearestObjects [_dronePos, ["CAManBase", "LandVehicle", "Air", "Ship"], 40];
            if (!isNull _target && {!(_target in _nearUnits)}) then { _nearUnits pushBack _target; };
            if (!isNull (vehicle _target)) then {
                if !(vehicle _target in _nearUnits) then { _nearUnits pushBack (vehicle _target); };
                _nearUnits append (crew (vehicle _target));
            };
            {
                if (_x isKindOf "LandVehicle" || {_x isKindOf "Air"} || {_x isKindOf "Ship"}) then {
                    _nearUnits append (crew _x);
                };
            } forEach (+_nearUnits);
            _nearUnits = _nearUnits arrayIntersect _nearUnits;
            {
                if (!isNull _x) then {
                    _x setVariable ["CLDW_LastDroneAttacker", _operator, true];
                    _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
                    _x setVariable ["CLDW_LastDroneAttackerSide", _impactSide, true];
                };
            } forEach _nearUnits;
        };

        // Maintain downward velocity vector into the ground; base mod detonates on ground collision
        if (alive _drone) then {
            private _curVel = velocity _drone;
            _drone setVelocity [_curVel select 0, _curVel select 1, (_curVel select 2) min -20];
        };
    } else {
        if (_outOfRange || _targetDied) then {
            private _reacquired = false;
            // If target died and drone is still alive and airborne, attempt local re-acquisition nearby before defaulting to disengage
            if (_targetDied && alive _drone) then {
                private _dronePos = getPosATL _drone;
                private _nearCand = (_dronePos nearEntities ["Man", 200]) select {
                    alive _x && {[_drone, _x] call CLDW_fnc_isEnemy}
                };
                if (count _nearCand == 0) then {
                    _nearCand = (_dronePos nearEntities [["LandVehicle", "Ship", "Air"], 200]) select {
                        alive _x && {[_drone, _x] call CLDW_fnc_isEnemy}
                    };
                };
                if (count _nearCand > 0) then {
                    _nearCand = [_nearCand, [], { _drone distance _x }, "ASCEND"] call BIS_fnc_sortBy;
                    private _newTarget = vehicle (_nearCand select 0);
                    private _speed = ((missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6) max 40;
                    _drone setVariable ["CLDW_Disengaged", false, true];
                    _drone setVariable ["CLDW_CurrentTarget", _newTarget, true];
                    diag_log format ["CLDW [RetargetOnExit]: '%1' reacquired nearby enemy '%2' at %3m instead of returning.", typeOf _drone, typeOf _newTarget, round (_drone distance _newTarget)];
                    [_drone, _newTarget, _speed, 0.1] spawn CLDW_fnc_guideToTarget;
                    _reacquired = true;
                };
            };

            if (!_reacquired) then {
                // Target dead or out of range: disengage cleanly
                if (alive _drone && {!isNull _man}) then {
                    _drone enableAI "PATH";
                    private _drv = driver _drone;
                    if (!isNull _drv && {alive _drv}) then { _drv enableAI "PATH"; };
                    _drone setVariable ["CLDW_Disengaged", true, true];
                    [_drone, _lastValidTargetPos, _man] spawn CLDW_fnc_disengage;
                } else {
                    if (alive _drone) then { _drone setFuel 0; };
                };
            };
        } else {
            // Lost sight: search around the last confirmed position, not the
            // target's live hidden coordinates.
            if (alive _drone && {!isNull _man}) then {
                _drone setVariable ["CLDW_Disengaged", false, true];
                _drone setVariable ["CLDW_CurrentTarget", objNull, true];
                [_drone,"SEARCH",[_drone,_lastValidTargetPos,_target,_man]] call CLDW_fnc_startController;
            };
        };
    };
};
