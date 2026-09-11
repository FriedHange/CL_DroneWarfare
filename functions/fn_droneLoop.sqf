// Register EntityCreated handler to prevent FPV drone collisions and realign crew sides immediately upon spawn
addMissionEventHandler ["EntityCreated", {
    params ["_entity"];
    if (isNull _entity) exitWith {};
    if (!local _entity) exitWith {};

    private _type = typeOf _entity;
    if (_entity isKindOf "UAV" || {_entity isKindOf "Air"}) then {
        // Suppress ACE marking laser checks on turretless FPV drones immediately upon creation
        _entity setVariable ["ace_markinglaser_hasLaser", false];

        // Exclude Shahed and any drone spawned near a swarm launcher crate (which handles its own launch physics)
        private _lowerType = toLower _type;
        private _isExtendedUAV = (_lowerType find "crocus" > -1) ||
                                 {_lowerType find "kvn" > -1} ||
                                 {_lowerType find "uafpv" > -1} ||
                                 {_lowerType find "rc40" > -1} ||
                                 {_lowerType find "rc-40" > -1} ||
                                 {_lowerType find "uav_02_ied" > -1} ||
                                 {_lowerType find "tura_uav" > -1} ||
                                 {_lowerType find "uav_06" > -1} ||
                                 {_lowerType find "uas_06" > -1} ||
                                 {_lowerType find "fpv" > -1};
        if (_isExtendedUAV && {!(_lowerType find "shahed" > -1)}) then {
            // Suppress infrared, radar, and visual target signatures to deter AI heavy-weapon and launcher targeting
            _entity setTargetSize [0.05, 0, 0];
            _entity setVehicleRadar 2;
            _entity disableTIEquipment true;
            _entity disableNVGEquipment true;
            _entity setVehicleReportRemoteTargets false;
            _entity setVehicleReceiveRemoteTargets false;
            _entity setVehicleReportOwnPosition false;
            _entity setVariable ["CLDW_IsDrone", true, true];

            private _nearLaunchers = nearestObjects [_entity, ["CLDWC_DroneCrate_Swarm"], 15];
            if (count _nearLaunchers > 0) exitWith {};

            // Disable physical collision with all other active UAVs safely
            private _otherUAVs = (+CLDW_activeDrones) select { !isNull _x && {alive _x} && {_x != _entity} };
            {
                _entity disableCollisionWith _x;
                _x disableCollisionWith _entity;
            } forEach _otherUAVs;

            // 1. Safety positioning and temporary invincibility to prevent collision explosions (AI-only)
            _entity spawn {
                params ["_drone"];
                sleep 0.1; // Wait for physics and ownership variables to initialize
                if (isNull _drone) exitWith {};
                if (!local _drone) exitWith {}; // Locality may have transferred during sleep; skip if drone is no longer local

                // Exclude player-owned, player-assembled, Zeus-placed, and editor-placed drones from safety overrides
                if (!isNull findDisplay 312 || {count (allPlayers select { _x distance _drone < 10 }) > 0}) exitWith {};

                private _owner = _drone getVariable ["CLDW_CurrentOperator", objNull];
                if (!isNull _owner && {isPlayer _owner}) exitWith {};

                if (!(_drone getVariable ["CLDW_AI_Spawned", false]) && {isNull _owner}) exitWith {};

                _drone allowDamage false;

                private _posASL = getPosASL _drone;
                private _upPos = _posASL vectorAdd [0, 0, 50];
                private _intersections = lineIntersectsSurfaces [_posASL, _upPos, _drone, objNull, true, 1, "VIEW", "FIRE"];

                if (count _intersections > 0) then {
                    // Spawned inside building/under roof. Teleport to roof.
                    private _intersection = _intersections select 0;
                    private _roofPosASL = _intersection select 0;
                    private _safePosASL = _roofPosASL vectorAdd [0, 0, 3];
                    _drone setPosASL _safePosASL;
                    _drone setVectorDirAndUp [vectorDir _drone, [0, 0, 1]];
                    _drone setVelocity [0, 0, 0.5];
                    if (missionNamespace getVariable ["ddtDebug", false]) then {
                        systemChat format ["CLDW: Relocated %1 from inside building to roof.", typeOf _drone];
                    };
                };

                // Keep it upright and stable for the first second of flight while engine initializes
                for "_j" from 1 to 10 do {
                    if (isNull _drone || {!alive _drone}) exitWith {};
                    _drone setVectorDirAndUp [vectorDir _drone, [0, 0, 1]];
                    sleep 0.1;
                };

                // Allow physics to settle before re-enabling damage
                sleep 2.0;
                if (!isNull _drone && {alive _drone}) then {
                    _drone allowDamage true;
                };
            };

            // 2. Instantly realign crew side to prevent friendly mortar targeting (AI-only)
            _entity spawn {
                params ["_drone"];
                sleep 0.1; // Wait 1 frame to detect ownership variables
                if (isNull _drone) exitWith {};
                if (!local _drone) exitWith {}; // Locality may have transferred during sleep; skip if drone is no longer local
                if (_drone getVariable ["CLDW_AI_Spawned", false]) exitWith {};

                // Exclude player-owned, player-assembled, and Zeus-placed drones from crew realignment
                if (!isNull findDisplay 312 || {count (allPlayers select { _x distance _drone < 10 }) > 0}) exitWith {};

                private _isPlayerOwned = false;
                private _owner = _drone getVariable ["CLDW_CurrentOperator", objNull];
                if (isNull _owner) then {
                    private _ownerVar = _drone getVariable ["ddtOwner", objNull];
                    if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
                        _owner = _ownerVar;
                    } else {
                        if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
                            { if (str _x == _ownerVar) exitWith { _owner = _x; }; } forEach allUnits;
                        };
                    };
                };

                if (!isNull _owner && {isPlayer _owner}) then { _isPlayerOwned = true; };

                if (!_isPlayerOwned) then {
                    { if (getConnectedUAV _x == _drone) exitWith { _isPlayerOwned = true; }; } forEach allPlayers;
                };
                if (!_isPlayerOwned) then {
                    private _crew = crew _drone;
                    if (count _crew > 0) then {
                        private _grp = group (_crew select 0);
                        if ({isPlayer _x} count (units _grp) > 0) then { _isPlayerOwned = true; };
                    };
                };
                if (_isPlayerOwned) exitWith {};
                if (_drone getVariable ["CLDW_AI_Spawned", false]) exitWith {};
                if (isNull _owner) exitWith {};

                private _timeout = time + 3.0;
                waitUntil {
                    // Instantly set any spawned crew captive as they spawn to block target locking
                    {
                        if !(_x getVariable ["CLDWC_CrewCaptiveSet", false]) then {
                            _x setCaptive true;
                            _x setVariable ["CLDWC_CrewCaptiveSet", true];
                        };
                    } forEach (crew _drone);
                    !((crew _drone) isEqualTo []) || time > _timeout
                };

                if (isNull _drone) exitWith {};
                private _crew = crew _drone;
                if !(_crew isEqualTo []) then {
                    // Determine correct side based on owner or vehicle prefix
                    private _side = sideUnknown;
                    if (!isNull _owner) then {
                        _side = side group _owner;
                    };

                    if (_side == sideUnknown) then {
                        private _type = typeOf _drone;
                        if (_type select [0, 2] == "B_") then { _side = west; };
                        if (_type select [0, 2] == "O_") then { _side = east; };
                        if (_type select [0, 2] == "I_") then { _side = independent; };
                    };

                    if (_side == sideUnknown) then { _side = civilian; };

                    // Determine group and side for the drone crew
                    private _op = _drone getVariable ["CLDW_CurrentOperator", objNull];
                    private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
                    if (isNull _opGrp && {!isNull _op}) then { _opGrp = group _op; };

                    {
                        _x setVariable ["CLDW_IsDroneCrew", true, true];
                        _x setVariable ["CLDW_DroneCrewUsed", true, true];
                        if (!isNull _op) then { _x setVariable ["CLDW_CurrentOperator", _op, true]; };
                        if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                    } forEach _crew;

                    // createGroup and joinSilent must only run on the server/dedi — they are not safe on clients
                    if (isServer || isDedicated) then {
                        private _newGrp = createGroup [_side, true];
                        _crew joinSilent _newGrp;
                        _newGrp deleteGroupWhenEmpty true;
                        _newGrp setBehaviour "CARELESS";
                        _newGrp setCombatMode "BLUE";
                    };

                    // Release captive status now that side is aligned (safe on all machines)
                    {
                        _x setCaptive false;
                    } forEach _crew;

                    _drone setVariable ["CLDW_DroneSide", _side, true];
                };
            };
        };
    };
}];

[] spawn {
    // Capture original DDT functions before overriding them
    [] spawn {
        waitUntil { sleep 0.2; (missionNamespace getVariable ["ddtReady", false]) || !isNil "DDT_fnc_GuideToTarget" };
        if (!isNil "DDT_fnc_GuideToTarget" && {isNil "CLDW_original_GuideToTarget"}) then {
            CLDW_original_GuideToTarget = DDT_fnc_GuideToTarget;
        };
        if (!isNil "DDT_fnc_getTargetsAT" && {isNil "CLDW_original_getTargetsAT"}) then {
            CLDW_original_getTargetsAT = DDT_fnc_getTargetsAT;
        };
        if (!isNil "DDT_fnc_GetSoftTargets" && {isNil "CLDW_original_GetSoftTargets"}) then {
            CLDW_original_GetSoftTargets = DDT_fnc_GetSoftTargets;
        };
        if (!isNil "DDT_fnc_Move" && {isNil "CLDW_original_Move"}) then {
            CLDW_original_Move = DDT_fnc_Move;
        };
        if (!isNil "DDT_fnc_DroneGroupAlive" && {isNil "CLDW_original_DroneGroupAlive"}) then {
            CLDW_original_DroneGroupAlive = DDT_fnc_DroneGroupAlive;
        };
        if (!isNil "DDT_fnc_GuideToTargetBomber" && {isNil "CLDW_original_GuideToTargetBomber"}) then {
            CLDW_original_GuideToTargetBomber = DDT_fnc_GuideToTargetBomber;
        };

        DDT_fnc_getTargetsAT = CLDW_fnc_getTargetsAT;
        DDT_fnc_GetSoftTargets = CLDW_fnc_getSoftTargets;
        DDT_fnc_GuideToTarget = CLDW_fnc_guideToTarget;
        DDT_fnc_Move = CLDW_fnc_move;
        DDT_fnc_DroneGroupAlive = CLDW_fnc_droneGroupAlive;

        // Realistic calm bomber/dropper guidance override
        DDT_fnc_GuideToTargetBomber = {
            params ["_drone", "_target"];
            if (isNull _drone || {isNull _target} || {!alive _drone} || {!alive _target}) exitWith {};

            private _dropperSpeed = ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 10;
            private _minDistanceToTarget = 9;
            private _z = (getPosASL _drone) select 2;

            _drone setCombatMode "BLUE";
            _drone setBehaviour "CARELESS";
            _drone setSpeedMode "NORMAL";
            _drone forceSpeed _dropperSpeed;

            private _targetVelocity = [];
            while {!isNull _drone && {!isNull _target} && {alive _drone} && {alive _target}} do {
                if ((count (crew _drone)) < 1) exitWith {};
                private _currentPos = getPosASLVisual _drone;
                private _targetPos = getPosASLVisual _target;
                _targetPos set [2, _z];

                if (((getPosASLVisual _drone) distance _targetPos) <= _minDistanceToTarget) exitWith {};

                private _forwardVector = vectorNormalized (_targetPos vectorDiff _currentPos);
                private _rightVector = (_forwardVector vectorCrossProduct [0,0,1]) vectorMultiply -1;
                private _upVector = _forwardVector vectorCrossProduct _rightVector;

                // Move smoothly at realistic calm bomber speed (~30-35 km/h, 8-9.7 m/s)
                _targetVelocity = _forwardVector vectorMultiply _dropperSpeed;
                _drone setVelocity _targetVelocity;

                sleep 0.3;
                if (isNull _drone || {!alive _drone}) exitWith {};
                _drone setVectorDirAndUp [_forwardVector, _upVector];
            };

            if (!alive _drone || isNull _drone) exitWith {};

            private _lowerDrone = toLower (typeOf _drone);
            private _isIEDDrone = _lowerDrone in [
                "c_idap_uav_06_antimine_f",
                "b_g_uav_02_ied_lxws",
                "b_tura_uav_02_ied_lxws",
                "o_g_uav_02_ied_lxws",
                "o_tura_uav_02_ied_lxws",
                "i_g_uav_02_ied_lxws",
                "i_tura_uav_02_ied_lxws"
            ] || {(_lowerDrone find "uav_02_ied" > -1) || {(_lowerDrone find "tura_uav" > -1)}};

            if (_isIEDDrone) exitWith {
                if !(someAmmo _drone) exitWith { _drone setVariable ["ddtHasAmmo", false, true]; };
                _drone setVariable ["ddtTargetPos", (getPosASL _target), true];
                private _EH = _drone addEventHandler ["Fired", {
                    params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_magazine", "_projectile", "_gunner"];
                    [_projectile, _unit] spawn DDT_fnc_GuideToTarget3;
                    true
                }];
                _drone setCombatMode "RED";
                _drone fire (currentWeapon _drone);
                _target = objNull;
                sleep 1;
                if (!alive _drone) exitWith {};
                _drone removeEventHandler ["Fired", _EH];
                _drone setCombatMode "BLUE";
                _drone setBehaviour "AWARE";
                _drone setSpeedMode "NORMAL";
                _drone forceSpeed _dropperSpeed;
                _drone flyInHeight 80;
                if !(someAmmo _drone) exitWith { _drone setVariable ["ddtHasAmmo", false, true]; };
                sleep 10;
                if (!alive _drone) exitWith {};
                _drone setVariable ["ddtBusy", false, true];
            };

            { deleteVehicle _x; } forEach (attachedObjects _drone);
            private _shellPos = getPosATL _drone;
            private _sz = (_shellPos select 2) - 0.2;
            _shellPos set [2, _sz];
            private _shellType = "G_40mm_HE";
            private _shell = createVehicle [_shellType, _shellPos, [], 0, "FLY"];
            _shell setVectorUp [0, 0.99, 0.01];
            [_shell, _target, 10] spawn DDT_fnc_GuideToTarget2;

            _drone setSpeedMode "NORMAL";
            _drone forceSpeed _dropperSpeed;
            _drone flyInHeight 80;
            _drone setVariable ["ddtHasAmmo", false, true];
            _drone setVariable ["ddtBusy", false, true];
        };

        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "CL Drone Warfare overrides applied successfully.";
        };
    };

    // =========================================================================
    // RIS (Random Infantry Skirmish) Compatibility & Death Camera Sanitization
    // Resolves drone kills back to the operator and prevents camera swing to [0,0,0]
    // =========================================================================
    [] spawn {
        // Wait for mission functions to initialize (polling for up to 30 seconds)
        private _risDetected = false;
        for "_i" from 1 to 30 do {
            if (!isNil "RSTF_fnc_playerKilled" || {!isNil "RSTF_fnc_unitKilled"} || {!isNil "RSTFM_fnc_playerKilled"} || {!isNil "RSTF_fnc_showDeath"}) exitWith {
                _risDetected = true;
            };
            sleep 1;
        };

        if (!_risDetected) exitWith {};

        diag_log "CLDW: RIS mission detected. Registering drone kill sanitization handlers.";

        // Mission-level EntityKilled handler: Intercepts player and unit deaths immediately on both host and client
        addMissionEventHandler ["EntityKilled", {
            params ["_unit", "_killer", "_instigator"];
            if (!hasInterface) exitWith {};

            // Check if killed unit is player or the recorded death victim
            if (_unit == player || {_unit isEqualTo (missionNamespace getVariable ["RSTF_RESPAWN_KILLED", objNull])} || {_unit isEqualTo (missionNamespace getVariable ["RSTF_DEATH_BODY", objNull])}) then {
                private _resolved = [_unit, _killer, _instigator] call CLDW_fnc_resolveDroneKiller;
                if (!isNull _resolved && {alive _resolved} && {(_resolved distance [0,0,0]) > 150}) then {
                    RSTF_RESPAWN_KILLER = _resolved;
                    RSTF_DEATH_KILLER = _resolved;
                } else {
                    RSTF_RESPAWN_KILLER = objNull;
                    RSTF_DEATH_KILLER = objNull;
                };
            };
        }];
    };

    // Client-side safety: Prevent team-switching or remote-controlling drone crew units
    if (hasInterface) then {
        [] spawn {
            waitUntil { !isNull player && {alive player} };

            addMissionEventHandler ["TeamSwitch", {
                params ["_previousUnit", "_newUnit"];
                private _type = typeOf _newUnit;
                private _isUAVCrew = (_type in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]) ||
                                     {getText (configFile >> "CfgVehicles" >> _type >> "simulation") == "UAVPilot"} ||
                                     {_newUnit getVariable ["CLDW_IsDroneCrew", false]};
                if (_isUAVCrew) then {
                    if (!isNull _previousUnit && {alive _previousUnit}) then {
                        selectPlayer _previousUnit;
                        systemChat "CLDW: Prevented switching to UAV crew unit.";
                    };
                };
            }];

            // High-frequency frame-level death camera protector and UI updater
            addMissionEventHandler ["EachFrame", {
                if (!hasInterface) exitWith {};
                if !(missionNamespace getVariable ["RSTF_DEATH_SHOWN", false]) exitWith {
                    missionNamespace setVariable ["CLDW_DeathUI_Updated", false];
                };

                private _cam = missionNamespace getVariable ["RSTF_CAM", objNull];
                if (isNull _cam) exitWith {};

                private _body = missionNamespace getVariable ["RSTF_DEATH_BODY", objNull];
                if (isNull _body) then { _body = missionNamespace getVariable ["RSTF_RESPAWN_KILLED", player]; };
                if (isNull _body) exitWith {};

                private _killer = missionNamespace getVariable ["RSTF_DEATH_KILLER", objNull];
                private _resolved = [_body, _killer] call CLDW_fnc_resolveDroneKiller;

                private _camPos = getPos _cam;
                private _camTarget = camTarget _cam;
                private _targetPos = if (!isNull _camTarget) then { getPos _camTarget } else { [0, 0, 0] };

                private _targetIsZero = (isNull _camTarget) || {(_targetPos distance [0,0,0]) < 150} || {_targetPos isEqualTo [0,0,0]};
                private _targetIsDrone = (!isNull _camTarget && {_camTarget isKindOf "UAV" || unitIsUAV _camTarget || (_camTarget getVariable ["CLDW_IsDroneCrew", false])});
                private _targetInvalid = (_targetIsZero || _targetIsDrone) && {isNull _resolved || {_camTarget != _resolved}};

                private _posInvalid = ((_camPos distance [0,0,0]) < 250) || ((_camPos select 0 < 100) && (_camPos select 1 < 100));
                private _strayCam = (isNull _resolved) && {(_camPos distance (getPos _body)) > 35};

                if (_targetInvalid || _posInvalid || _strayCam) then {
                    if (!isNull _resolved && {alive _resolved} && {(_resolved distance [0,0,0]) > 150}) then {
                        _cam camSetTarget _resolved;
                        _cam camSetRelPos [0.5, 0, 3];
                        _cam camCommit 0;
                        _cam camSetRelPos [0.5, 0, 3];
                        _cam camCommit 5;
                    } else {
                        _cam camSetTarget _body;
                        _cam camSetPos (getPos _body vectorAdd [0, -3, 4]);
                        _cam camCommit 0;
                        _cam camSetRelPos [0, -4, 5];
                        _cam camCommit 3;
                    };
                };

                // Dynamic UI attribution on Death Dialog
                private _layout = missionNamespace getVariable ["RSTF_DEATH_DIALOG_layout", []];
                if (count _layout > 0 && {!(missionNamespace getVariable ["CLDW_DeathUI_Updated", false])}) then {
                    missionNamespace setVariable ["CLDW_DeathUI_Updated", true];
                    private _killerCtrl = [_layout, "killer"] call ZUI_fnc_getControlById;
                    private _weaponCtrl = [_layout, "weapon"] call ZUI_fnc_getControlById;
                    if (!isNull _resolved && {alive _resolved}) then {
                        private _dist = round (_resolved distance _body);
                        if (!isNull _killerCtrl) then {
                            _killerCtrl ctrlShow true;
                            _killerCtrl ctrlSetText ("Killed by " + name _resolved);
                        };
                        if (!isNull _weaponCtrl) then {
                            _weaponCtrl ctrlShow true;
                            _weaponCtrl ctrlSetText ("With FPV Drone from distance of " + str(_dist) + " m");
                        };
                    } else {
                        if (!isNull _killerCtrl) then {
                            _killerCtrl ctrlShow true;
                            _killerCtrl ctrlSetText "Killed by FPV Strike Drone";
                        };
                        if (!isNull _weaponCtrl) then {
                            _weaponCtrl ctrlShow true;
                            _weaponCtrl ctrlSetText "Direct kinetic/explosive impact";
                        };
                    };
                };
            }];

            private _lastValidPlayer = player;
            while {true} do {
                private _p = player;
                private _isUAVCrew = false;
                if (!isNull _p) then {
                    private _type = typeOf _p;
                    if ((_type in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]) ||
                        {getText (configFile >> "CfgVehicles" >> _type >> "simulation") == "UAVPilot"} ||
                        {_p getVariable ["CLDW_IsDroneCrew", false]}) then {
                        _isUAVCrew = true;
                    };
                };

                // RIS Safe Killed EH Installation on player unit
                if (!isNil "RSTF_fnc_playerKilled" || {!isNil "RSTFM_fnc_playerKilled"}) then {
                    if (!isNull _p && {alive _p} && {!(_p getVariable ["CLDW_SafeKilledEH", false])}) then {
                        _p setVariable ["CLDW_SafeKilledEH", true];
                        _p removeAllEventHandlers "Killed";
                        _p addEventHandler ["Killed", {
                            params ["_unit", ["_killer", objNull], ["_instigator", objNull], ["_useEffects", true]];
                            private _resolved = [_unit, _killer, _instigator] call CLDW_fnc_resolveDroneKiller;
                            if (!isNull _resolved && {alive _resolved} && {(_resolved distance [0,0,0]) > 150}) then {
                                _killer = _resolved;
                            } else {
                                _killer = objNull;
                            };
                            RSTF_RESPAWN_KILLER = _killer;
                            RSTF_DEATH_KILLER = _killer;
                            if (!isNil "RSTF_fnc_playerKilled") then {
                                [_unit, _killer, _instigator, _useEffects] call RSTF_fnc_playerKilled;
                            } else {
                                if (!isNil "RSTFM_fnc_playerKilled") then {
                                    [_unit, _killer, _instigator, _useEffects] call RSTFM_fnc_playerKilled;
                                };
                            };
                        }];
                    };
                };

                private _isControllingUAV = !isNull (getConnectedUAV _p);

                if (_isUAVCrew && !_isControllingUAV) then {
                    if (!isNull _lastValidPlayer && {alive _lastValidPlayer} && {_lastValidPlayer != _p}) then {
                        selectPlayer _lastValidPlayer;
                        systemChat "CLDW: Restored player from UAV crew unit.";
                    } else {
                        private _groupUnits = (units group _p) select {
                            alive _x &&
                            {_x != _p} &&
                            {!(typeOf _x in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"])} &&
                            {getText (configFile >> "CfgVehicles" >> typeOf _x >> "simulation") != "UAVPilot"}
                        };
                        if (count _groupUnits > 0) then {
                            selectPlayer (_groupUnits select 0);
                            systemChat "CLDW: Switched player to squad member.";
                        } else {
                            systemChat "CLDW: No squad members left. Triggering respawn.";
                            if (isMultiplayer) then {
                                if (!isNil "RSTF_DEATH_SIDE") then {
                                    if (!isNil "RSTF_fnc_spawnPlayer") then {
                                        RSTF_DEATH_SIDE spawn RSTF_fnc_spawnPlayer;
                                    } else {
                                        if (!isNil "RSTFM_fnc_spawnPlayer") then {
                                            RSTF_DEATH_SIDE spawn RSTFM_fnc_spawnPlayer;
                                        };
                                    };
                                };
                            } else {
                                if (!isNil "RSTF_fnc_playerKilled") then {
                                    [player, objNull] call RSTF_fnc_playerKilled;
                                } else {
                                    if (!isNil "RSTFM_fnc_playerKilled") then {
                                        [player, objNull] call RSTFM_fnc_playerKilled;
                                    };
                                };
                            };
                        };
                    };
                } else {
                    if (!_isUAVCrew && !isNull _p && {alive _p}) then {
                        _lastValidPlayer = _p;
                    };
                };

                sleep 0.5;
            };
        };
    };

    // Inventory assignment, AI spawning, and guidance must have one authority in multiplayer.
    if (!isServer) exitWith { true };

    if (isNil "CLDW_activeDrones") then { CLDW_activeDrones = []; };
    if (isNil "CLDW_deployQueue") then { CLDW_deployQueue = []; };

    // Server-side throttled deployment worker:
    // Processes deployment requests sequentially with a minimum 0.35s delay between UAV instantiations.
    // Prevents network message table overflow and engine race conditions when multiple squads deploy simultaneously.
    if (isNil "CLDW_deployWorkerRunning") then {
        CLDW_deployWorkerRunning = true;
        [] spawn {
            while {true} do {
                waitUntil { sleep 0.05; count CLDW_deployQueue > 0 };
                private _req = CLDW_deployQueue deleteAt 0;
                _req params ["_operator", "_droneBackpack", "_groupSide"];
                if (!isNull _operator) then {
                    _operator setVariable ["CLDW_Drone_Queued", false];
                };

                if (!isNull _operator && {alive _operator} && {backpack _operator == _droneBackpack}) then {
                    private _droneClass = getText (configFile >> "CfgVehicles" >> _droneBackpack >> "assembleInfo" >> "assembleTo");
                    if (_droneClass == "") then {
                        _droneClass = _droneBackpack;
                        private _bagIndex = _droneBackpack find "_Bag";
                        if (_bagIndex != -1) then {
                            _droneClass = _droneBackpack select [0, _bagIndex];
                        } else {
                            private _bpIndex = _droneBackpack find "_backpack_F";
                            if (_bpIndex != -1) then {
                                _droneClass = (_droneBackpack select [0, _bpIndex]) + "_F";
                            };
                        };
                    };

                    if (isClass (configFile >> "CfgVehicles" >> _droneClass)) then {
                        private _spawnPos = getPosATL _operator;
                        private _spawnPosFinal = if (missionNamespace getVariable ["CLDW_Setting_SpawnInAir", false]) then {
                            [_spawnPos select 0, _spawnPos select 1, 100]
                        } else {
                            _spawnPos vectorAdd [(sin (getDir _operator)) * 1.5, (cos (getDir _operator)) * 1.5, 1.5]
                        };
                        private _drone = createVehicle [_droneClass, _spawnPosFinal, [], 0, "FLY"];

                        if (!isNull _drone) then {
                            // Suppress ACE marking laser checks on turretless FPV drones during spawn
                            _drone setVariable ["ace_markinglaser_hasLaser", false];

                            diag_log format ["CLDW [Deploy]: '%1' deployed '%2' at %3 (machine %4).", name _operator, _droneClass, mapGridPosition _drone, clientOwner];
                            _drone setVariable ["CLDW_AI_Spawned", true, true];
                            _drone setVariable ["CLDW_CurrentOperator", _operator, true];
                            _drone setVariable ["CLDW_OperatorGroup", group _operator, true];
                            _drone setVariable ["CLDW_DroneSide", _groupSide, true];
                            _drone setVariable ["ddtOwner", _operator, true];

                            // Track in thread-safe active drones list
                            CLDW_activeDrones pushBack _drone;

                            createVehicleCrew _drone;
                            removeBackpack _operator;
                            if (isPlayer _operator) then {
                                _operator connectTerminalToUAV _drone;
                            };

                            private _crew = crew _drone;
                            {
                                _x setVariable ["CLDW_IsDroneCrew", true, true];
                                _x setVariable ["CLDW_DroneCrewUsed", true, true];
                                _x setVariable ["CLDW_CurrentOperator", _operator, true];
                                _x setVariable ["A3A_isIrrelevant", true, true];
                                if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                            } forEach _crew;

                            private _opGrp = group _operator;
                            private _separateGrp = createGroup [_groupSide, true];
                            _crew joinSilent _separateGrp;
                            _separateGrp deleteGroupWhenEmpty true;
                            _separateGrp setBehaviour "CARELESS";
                            _separateGrp setCombatMode "BLUE";

                            // If a Headless Client is connected, offload the drone's group simulation to the HC.
                            private _hcList = entities "HeadlessClient_F";
                            if (count _hcList > 0) then {
                                private _targetOwner = owner (_hcList select 0);
                                if (_targetOwner > 2) then {
                                    diag_log format ["CLDW [Locality]: Offloading '%1' group to Headless Client (machine %2).", typeOf _drone, _targetOwner];
                                    _separateGrp setGroupOwner _targetOwner;
                                };
                            };

                            if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                                private _terminalClass = switch (_groupSide) do {
                                    case west:  { "B_UavTerminal" };
                                    case east:  { "O_UavTerminal" };
                                    default     { "I_UavTerminal" };
                                };
                                if !(_terminalClass in (assignedItems _operator)) then {
                                    _operator linkItem _terminalClass;
                                };
                            };

                            (group _operator) setCombatMode "RED";
                            (group _operator) setBehaviour "COMBAT";

                            // Disable collisions with all other active UAVs immediately
                            private _otherActive = (+CLDW_activeDrones) select { !isNull _x && {alive _x} };
                            {
                                if (_x != _drone) then {
                                    _drone disableCollisionWith _x;
                                    _x disableCollisionWith _drone;
                                };
                            } forEach _otherActive;

                            private _role = [_drone] call CLDW_fnc_getDroneRole;

                            switch (_role) do {
                                case "SUICIDE": {
                                    private _targets = [_drone, missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000]] call CLDW_fnc_getTargetsAT;
                                    if (count _targets > 0) then {
                                        private _target = _targets select 0;
                                        private _speed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6;
                                        _drone setVariable ["CLDW_Disengaged", false, true];
                                        _drone setVariable ["CLDW_CurrentTarget", _target, true];
                                        [_drone, _target, _speed, 0.1] spawn CLDW_fnc_guideToTarget;
                                    } else {
                                        [_drone, getPosATL _operator] call CLDW_fnc_move;
                                    };
                                };
                                case "DROPPER": {
                                    // Dropper/Bomber drones loiter high and drop munitions - NEVER suicide dive!
                                    _drone setVariable ["CLDW_Disengaged", false, true];
                                    private _dropperSpeed = ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 12;
                                    _drone setSpeedMode "NORMAL";
                                    _drone forceSpeed _dropperSpeed;
                                    _drone flyInHeight 80;

                                    if (fileExists "DrongosDroneTweaks\Scripts\Drones\AI_Bomber.sqf") then {
                                        [_drone, _operator] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Bomber.sqf";
                                    } else {
                                        [_drone, getPosATL _operator] call CLDW_fnc_move;
                                    };
                                };
                                default { // "NONCOMBAT" (AL-6 Pelican, AR-2 Darter, Recon, Medical, Cargo)
                                    // Non-combat drones NEVER attack or dive! Maintain safe altitude and loiter/follow
                                    _drone setVariable ["CLDW_Disengaged", false, true];
                                    if (fileExists "DrongosDroneTweaks\Scripts\Drones\AI_Recon.sqf") then {
                                        [_drone, _operator] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Recon.sqf";
                                    } else {
                                        _drone flyInHeight 40;
                                        [_drone, getPosATL _operator] call CLDW_fnc_move;
                                    };
                                };
                            };

                            if (missionNamespace getVariable ["ddtDebug", false]) then {
                                systemChat format ["CLDW: AI %1 deployed drone %2 in combat.", name _operator, typeOf _drone];
                            };
                        };
                    };
                    if (!isNull _operator) then {
                        _operator setVariable ["CLDW_Drone_Deploying", false];
                    };
                    // Throttle AI deployments through a server-side queue with a minimum 0.25-second delay between UAV instantiations
                    sleep 0.25;
                };
            };
        };
    };

    sleep 2;
    private _isFirstRun = true;

    while {true} do {
        if (missionNamespace getVariable ["CLDW_Setting_EnableMod", true]) then {
            {
                private _group = _x;
                private _groupSide = side _group;

                if (_groupSide != civilian) then {

                    // CBA CHECK: Immersion guard check
                    if (_groupSide == independent && {! (missionNamespace getVariable ["CLDW_Setting_AllowIndependent", false])}) then {
                        continue;
                    };
                    if (_groupSide == west && {! (missionNamespace getVariable ["CLDW_Setting_AllowBlufor", true])}) then {
                        continue;
                    };
                    if (_groupSide == east && {! (missionNamespace getVariable ["CLDW_Setting_AllowOpfor", true])}) then {
                        continue;
                    };

                    // Determine if group contains human players for distribution exclusion
                    private _isPlayerGroup = {isPlayer _x} count (units _group) > 0;
                    private _excludeFromDistribution = (missionNamespace getVariable ["CLDW_Setting_ExcludePlayerGroup", true]) && _isPlayerGroup;

                    // AI turret/tower safety check: Strip drone bags from units in turrets or on watchtowers + RC-40 distribution
                    {
                        if !(isPlayer _x) then {
                            private _bp = backpack _x;
                            if (_bp != "") then {
                                private _lowerBP = toLower _bp;
                                private _isDroneBag = ("crocus" in _lowerBP) || ("kvn" in _lowerBP) || ("uafpv" in _lowerBP) || ("uav_02_ied" in _lowerBP) || ("tura_uav" in _lowerBP) || ("rc40" in _lowerBP) || ("rc-40" in _lowerBP);
                                if (_isDroneBag) then {
                                    private _inTurret = (vehicle _x != _x);
                                    private _onTower = ((getPosATL _x) select 2) > 1.8;
                                    if (_inTurret || _onTower) then {
                                        removeBackpack _x;
                                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                                            systemChat format ["CLDW: Stripped drone bag from %1 on turret/tower.", name _x];
                                        };
                                    };
                                };
                            };

                            // RC-40 magazine distribution — one-shot per unit (flag prevents re-running)
                            if (!_excludeFromDistribution && {!(_x getVariable ["CLDW_RC40_Checked", false])}) then {
                                _x setVariable ["CLDW_RC40_Checked", true, true];
                                private _unit = _x;
                                private _weapon = primaryWeapon _unit;
                                private _hasGL = false;
                                if (_weapon != "") then {
                                    private _muzzles = getArray (configFile >> "CfgWeapons" >> _weapon >> "muzzles");
                                    if (count _muzzles > 1) then {
                                        {
                                            if (_x != "this" && {_x != _weapon}) then {
                                                private _lowerMuzzle = toLower _x;
                                                if (("ugl" in _lowerMuzzle) || ("eglm" in _lowerMuzzle) || ("gl" in _lowerMuzzle) || ("gp" in _lowerMuzzle) || ("3gl" in _lowerMuzzle) || ("m203" in _lowerMuzzle) || ("m320" in _lowerMuzzle)) then {
                                                    _hasGL = true;
                                                };
                                            };
                                            if (_hasGL) exitWith {};
                                        } forEach _muzzles;
                                    };

                                    if (_hasGL) then {
                                        private _ammoCount = round (missionNamespace getVariable ["CLDW_Setting_RC40_Count", 2]);
                                        private _hasAssignedDrone = false;
                                        {
                                            _x params ["_settingVar", "_magClass"];
                                            private _chance = missionNamespace getVariable [_settingVar, 0];
                                            if (_chance > 0 && {random 100 < _chance}) then {
                                                if !(_unit canAdd _magClass) then {
                                                    if (backpack _unit == "") then {
                                                        private _bagClass = switch (_groupSide) do {
                                                            case west:  { "B_AssaultPack_mcamo" };
                                                            case east:  { "B_AssaultPack_ocamo" };
                                                            default     { "B_AssaultPack_dgtl" };
                                                        };
                                                        if (!isClass (configFile >> "CfgVehicles" >> _bagClass)) then {
                                                            _bagClass = "B_AssaultPack_khk";
                                                        };
                                                        _unit addBackpack _bagClass;
                                                    } else {
                                                        private _mags = magazines _unit;
                                                        private _limit = 5;
                                                        while {!(_unit canAdd _magClass) && {_limit > 0} && {count _mags > 0}} do {
                                                            private _toRemove = _mags deleteAt 0;
                                                            _unit removeMagazine _toRemove;
                                                            _limit = _limit - 1;
                                                        };
                                                    };
                                                };

                                                private _addedCount = 0;
                                                for "_i" from 1 to _ammoCount do {
                                                    _unit addMagazine _magClass;
                                                    _addedCount = _addedCount + 1;
                                                };

                                                if (_addedCount > 0) then { _hasAssignedDrone = true; };

                                                if (missionNamespace getVariable ["ddtDebug", false]) then {
                                                    systemChat format ["CLDW: Added %1x RC-40 mag %2 to %3.", _addedCount, _magClass, name _unit];
                                                };
                                            };
                                        } forEach [
                                            ["CLDW_Setting_RC40_HE",         "1Rnd_RC40_HE_shell_RF"],
                                            ["CLDW_Setting_RC40_Recon",       "1Rnd_RC40_shell_RF"],
                                            ["CLDW_Setting_RC40_SmokeBlue",   "1Rnd_RC40_SmokeBlue_shell_RF"],
                                            ["CLDW_Setting_RC40_SmokeGreen",  "1Rnd_RC40_SmokeGreen_shell_RF"],
                                            ["CLDW_Setting_RC40_SmokeOrange", "1Rnd_RC40_SmokeOrange_shell_RF"],
                                            ["CLDW_Setting_RC40_SmokeRed",    "1Rnd_RC40_SmokeRed_shell_RF"],
                                            ["CLDW_Setting_RC40_SmokeWhite",  "1Rnd_RC40_SmokeWhite_shell_RF"]
                                        ];

                                        if (_hasAssignedDrone && {backpack _unit != ""}) then {
                                            if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                                                private _terminalClass = switch (_groupSide) do {
                                                    case west:  { "B_UavTerminal" };
                                                    case east:  { "O_UavTerminal" };
                                                    default     { "I_UavTerminal" };
                                                };
                                                if !(_terminalClass in (assignedItems _unit)) then {
                                                    _unit linkItem _terminalClass;
                                                };
                                            };

                                            private _list = _group getVariable ["_chosen_drone_operators_list", []];
                                            _list pushBackUnique _unit;
                                            _group setVariable ["_chosen_drone_operators_list", _list];
                                        };
                                    };
                                };
                            };
                        };
                    } forEach units _group;

                    private _currentOperators = _group getVariable ["_chosen_drone_operators_list", []];
                    _currentOperators = _currentOperators select { alive _x && {!isNull _x} };

                    // Auto-detect any units carrying drone backpacks in the group and register them
                    {
                        private _unit = _x;
                        private _bp = backpack _unit;
                        if (_bp != "") then {
                            private _uavType = toLower _bp;
                            private _isDroneBag = ("crocus" in _uavType) || ("kvn" in _uavType) || ("uafpv" in _uavType) || ("uav_02_ied" in _uavType) || ("tura_uav" in _uavType) || ("rc40" in _uavType) || ("rc-40" in _uavType);
                            if (_isDroneBag) then {
                                _currentOperators pushBackUnique _unit;
                            };
                        };
                    } forEach units _group;

                    _group setVariable ["_chosen_drone_operators_list", _currentOperators];

                    if (_currentOperators isEqualTo []) then { _group setVariable ["_drone_initialized", false]; };

                    // Scale drone distribution count dynamically based on menu slider
                    private _currentDroneCount = count _currentOperators;
                    private _maxAllowedDrones = round (missionNamespace getVariable ["CLDW_Setting_MaxDrones", 3]);
                    private _minSquadSize = round (missionNamespace getVariable ["CLDW_Setting_MinSquadSize", 4]);

                    if (!_excludeFromDistribution && {_currentDroneCount < _maxAllowedDrones}) then {
                        if ((count units _group) >= _minSquadSize) then {
                            private _spawnChance = missionNamespace getVariable ["CLDW_Setting_DroneSpawnChance", 50];
                            if (_spawnChance > 0 && { (random 100) < _spawnChance }) then {

                            // Build bag pool from mod-gated toggles only
                            private _apBags = [];
                            private _atBags = [];

                            // Crocus FPV (DarkBall) — AP and AT
                            if (missionNamespace getVariable ["CLDW_Mod_Crocus", true]) then {
                                private _ap = (switch (_groupSide) do {
                                    case west:  { ["B_Crocus_AP_Bag", "B_Crocus_AP_TI_Bag"] };
                                    case east:  { ["O_Crocus_AP_Bag", "O_Crocus_AP_TI_Bag"] };
                                    default     { ["I_Crocus_AP_Bag", "I_Crocus_AP_TI_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _apBags append _ap;

                                private _at = (switch (_groupSide) do {
                                    case west:  { ["B_Crocus_AT_Bag", "B_Crocus_AT_TI_Bag"] };
                                    case east:  { ["O_Crocus_AT_Bag", "O_Crocus_AT_TI_Bag"] };
                                    default     { ["I_Crocus_AT_Bag", "I_Crocus_AT_TI_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _atBags append _at;
                            };

                            // KVN Fibre-Optic FPV (DarkBall) — AP and AT
                            if (missionNamespace getVariable ["CLDW_Mod_KVN", true]) then {
                                private _ap = (switch (_groupSide) do {
                                    case west:  { ["B_KVN_AP_Bag", "B_KVN_AP_TI_Bag"] };
                                    case east:  { ["O_KVN_AP_Bag", "O_KVN_AP_TI_Bag"] };
                                    default     { ["I_KVN_AP_Bag", "I_KVN_AP_TI_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _apBags append _ap;

                                private _at = (switch (_groupSide) do {
                                    case west:  { ["B_KVN_AT_Bag", "B_KVN_AT_TI_Bag"] };
                                    case east:  { ["O_KVN_AT_Bag", "O_KVN_AT_TI_Bag"] };
                                    default     { ["I_KVN_AT_Bag", "I_KVN_AT_TI_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _atBags append _at;
                            };

                            // Ukraine FPV Drone (Tom) — RKG/OG7V/IED AP + PG7VL AT
                            if (missionNamespace getVariable ["CLDW_Mod_UAFPV_Tom", true]) then {
                                private _ap = (switch (_groupSide) do {
                                    case west:  { ["B_UAFPV_IED_AP_Bag", "B_UAFPV_OG7V_AP_Bag", "B_UAFPV_RKG_AP_Bag"] };
                                    case east:  { ["O_UAFPV_IED_AP_Bag", "O_UAFPV_OG7V_AP_Bag", "O_UAFPV_RKG_AP_Bag"] };
                                    default     { ["I_UAFPV_IED_AP_Bag", "I_UAFPV_OG7V_AP_Bag", "I_UAFPV_RKG_AP_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _apBags append _ap;

                                private _at = (switch (_groupSide) do {
                                    case west:  { ["B_UAFPV_PG7VL_AT_Bag"] };
                                    case east:  { ["O_UAFPV_PG7VL_AT_Bag"] };
                                    default     { ["I_UAFPV_PG7VL_AT_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _atBags append _at;
                            };

                            // Ukraine FPV Edited (BIG GUY) — RKG_Bag/AP_Bag AP + AT_Bag/AT_TI_Bag AT
                            if (missionNamespace getVariable ["CLDW_Mod_UAFPV_BIG", true]) then {
                                private _ap = (switch (_groupSide) do {
                                    case west:  { ["B_UAFPV_RKG_Bag", "B_UAFPV_AP_Bag"] };
                                    case east:  { ["O_UAFPV_RKG_Bag", "O_UAFPV_AP_Bag"] };
                                    default     { ["I_UAFPV_RKG_Bag", "I_UAFPV_AP_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _apBags append _ap;

                                private _at = (switch (_groupSide) do {
                                    case west:  { ["B_UAFPV_AT_Bag", "B_UAFPV_AT_TI_Bag"] };
                                    case east:  { ["O_UAFPV_AT_Bag", "O_UAFPV_AT_TI_Bag"] };
                                    default     { ["I_UAFPV_AT_Bag", "I_UAFPV_AT_TI_Bag"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _atBags append _at;
                            };

                            // Western Sahara IED UAV (bomber — counts as AT)
                            if (missionNamespace getVariable ["CLDW_Mod_WS_IED", true]) then {
                                private _at = ["B_Tura_UAV_02_IED_backpack_lxws", "B_G_UAV_02_IED_backpack_lxWS"] select { isClass (configFile >> "CfgVehicles" >> _x) };
                                _atBags append _at;
                            };

                            // Fallback to Western Sahara IED UAV if explicitly allowed and no mod bags or RF are loaded
                            private _sideDrones = _apBags + _atBags;
                            private _rfLoaded = isClass (configFile >> "CfgMagazines" >> "1Rnd_RC40_HE_shell_RF");
                            private _allowFallback = missionNamespace getVariable ["CLDW_Setting_AllowVanillaFallback", false];
                            if (_sideDrones isEqualTo [] && {_allowFallback} && {!_rfLoaded}) then {
                                _sideDrones = (switch (_groupSide) do {
                                    case west:  { ["B_Tura_UAV_02_IED_backpack_lxws", "B_G_UAV_02_IED_backpack_lxWS"] };
                                    case east:  { ["O_Tura_UAV_02_IED_backpack_lxws", "O_G_UAV_02_IED_backpack_lxWS"] };
                                    default     { ["I_Tura_UAV_02_IED_backpack_lxws", "I_G_UAV_02_IED_backpack_lxWS"] };
                                }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                            };

                            private _eligibleUnits = [];
                            private _groupBackpacks = [];
                            { _groupBackpacks pushBackUnique (backpack _x); } forEach units _group;

                            {
                                if !(isPlayer _x) then {
                                    private _onTower = ((getPosATL _x) select 2) > 1.8;
                                    if (vehicle _x == _x && {!_onTower} && {!(_x in _currentOperators)}) then {
                                        if (backpack _x isEqualTo "" || {missionNamespace getVariable ["CLDW_Setting_ReplaceBackpacks", false]}) then { _eligibleUnits pushBack _x; };
                                    };
                                };
                            } forEach units _group;

                            if !(_eligibleUnits isEqualTo []) then {
                                private _operator = selectRandom _eligibleUnits;

                                // Select drone backpack based on AP Drone Ratio setting
                                private _apRatio = missionNamespace getVariable ["CLDW_Setting_APRatio", 50];
                                private _wantAP = (random 100) < _apRatio;
                                private _primaryPool = if (_wantAP) then { _apBags } else { _atBags };
                                private _secondaryPool = if (_wantAP) then { _atBags } else { _apBags };

                                private _preferredTypes = _primaryPool select { !(_x in _groupBackpacks) };
                                if (_preferredTypes isEqualTo []) then { _preferredTypes = _primaryPool; };
                                if (_preferredTypes isEqualTo []) then {
                                    _preferredTypes = _secondaryPool select { !(_x in _groupBackpacks) };
                                    if (_preferredTypes isEqualTo []) then { _preferredTypes = _secondaryPool; };
                                };
                                if (_preferredTypes isEqualTo []) then { _preferredTypes = _sideDrones; };
                                if (_preferredTypes isEqualTo []) exitWith {};

                                private _droneBackpack = selectRandom _preferredTypes;
                                if (!isClass (configFile >> "CfgVehicles" >> _droneBackpack)) exitWith {
                                    diag_log format ["CLDW: Selected backpack %1 is not a valid CfgVehicles class.", _droneBackpack];
                                };

                                if (backpack _operator != "") then {
                                    removeBackpack _operator;
                                };
                                _operator addBackpack _droneBackpack;

                                if (backpack _operator != "") then {
                                    if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                                        private _terminalClass = switch (_groupSide) do {
                                            case west:  { "B_UavTerminal" };
                                            case east:  { "O_UavTerminal" };
                                            default     { "I_UavTerminal" };
                                        };
                                        if !(_terminalClass in (assignedItems _operator)) then {
                                            _operator linkItem _terminalClass;
                                        };
                                    };

                                    _currentOperators pushBack _operator;
                                    _group setVariable ["_chosen_drone_operators_list", _currentOperators];
                                    _group setVariable ["_drone_initialized", true];

                                    _operator setUnitAbility 1.0;
                                };
                            };
                            };
                        };
                    };

                    // Combat assembly monitor for AI operators carrying drone backpacks
                    private _allActiveDrones = (+CLDW_activeDrones) select { !isNull _x && {alive _x} };
                    {
                        private _op = _x;
                        private _bp = backpack _op;
                        private _uavType = toLower _bp;
                        private _isDroneBag = ("crocus" in _uavType) || ("kvn" in _uavType) || ("uafpv" in _uavType) || ("uav_02_ied" in _uavType) || ("tura_uav" in _uavType) || ("rc40" in _uavType) || ("rc-40" in _uavType);

                        // Give UAV Terminal ONLY to operators carrying drone backpacks or registered as operators
                        if (_isDroneBag || {_op in _currentOperators}) then {
                            if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                                private _terminalClass = switch (_groupSide) do {
                                    case west:  { "B_UavTerminal" };
                                    case east:  { "O_UavTerminal" };
                                    default     { "I_UavTerminal" };
                                };
                                if !(_terminalClass in (assignedItems _op)) then {
                                    _op linkItem _terminalClass;
                                };
                            };
                        };

                        private _hasActiveDrone = false;
                        {
                            if ((_x getVariable ["CLDW_CurrentOperator", objNull]) == _op && {alive _x}) exitWith {
                                _hasActiveDrone = true;
                            };
                        } forEach _allActiveDrones;

                        private _cooldownActive = (time - (_op getVariable ["CLDW_Last_Drone_Deploy_Time", 0])) < 30;

                        if (_bp != "" && {_isDroneBag} && {!isPlayer _op} && {!_hasActiveDrone} && {!_cooldownActive} && {!(_op getVariable ["CLDW_Drone_Deploying", false])}) then {
                            private _nearestEnemy = _op findNearestEnemy _op;
                            if (isNull _nearestEnemy && {!isNull (leader group _op)}) then {
                                _nearestEnemy = (leader group _op) findNearestEnemy (leader group _op);
                            };
                            private _scanDist = (missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000]) max 800;
                            private _nearThreat = (!isNull _nearestEnemy && {_op distance _nearestEnemy <= _scanDist});
                            private _inCombat = (behaviour _op in ["COMBAT", "STEALTH"]) ||
                                                { _nearThreat } ||
                                                { !((_op targets [true, _scanDist]) isEqualTo []) } ||
                                                { !isNull (leader group _op) && { !(((leader group _op) targets [true, _scanDist]) isEqualTo []) } };
                            if (_inCombat) then {
                                // Stagger gate: enforce a minimum delay between successive drone launches
                                // within the same group so explosions don't chain-kill each other.
                                // One getVariable read per operator per tick — zero network cost (no broadcast).
                                private _lastGroupLaunch = _group getVariable ["CLDW_Group_Last_Launch", -9999];
                                private _staggerDelay = missionNamespace getVariable ["CLDW_Setting_LaunchStagger", 5];
                                if ((time - _lastGroupLaunch) >= _staggerDelay) then {
                                    _group setVariable ["CLDW_Group_Last_Launch", time]; // Server-local, no broadcast needed
                                    _op setVariable ["CLDW_Drone_Deploying", true];
                                    _op setVariable ["CLDW_Last_Drone_Deploy_Time", time, true];
                                    if (!(_op getVariable ["CLDW_Drone_Queued", false])) then {
                                        _op setVariable ["CLDW_Drone_Queued", true];
                                        CLDW_deployQueue pushBack [_op, _bp, _groupSide];
                                    };
                                }; // end stagger gate
                            }; // end _inCombat
                        };
                    } forEach units _group;
                };
            } forEach allGroups;

            // Re-engagement monitor for disengaged/idle drones using thread-safe cloned array
            private _active = +CLDW_activeDrones;
            for "_i" from (count _active - 1) to 0 step -1 do {
                private _uav = _active select _i;
                if (isNull _uav || {!alive _uav}) then {
                    private _idx = CLDW_activeDrones find _uav;
                    if (_idx != -1) then {
                        CLDW_activeDrones deleteAt _idx;
                    };
                } else {
                    private _drone = _uav;
                    if (!(_drone getVariable ["CLDW_Disengaged", false])) then {
                        private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
                        if (isNull _man || {!alive _man}) then {
                            private _ownerVar = _drone getVariable ["ddtOwner", objNull];
                            if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
                                _man = _ownerVar;
                            } else {
                                if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
                                    { if (str _x == _ownerVar) exitWith { _man = _x; }; } forEach allUnits;
                                };
                            };
                            if (isNull _man || {!alive _man}) then {
                                private _droneSide = side _drone;
                                private _nearUnits = (getPosATL _drone) nearEntities ["CAManBase", 60];
                                private _friendlyUnits = _nearUnits select { alive _x && {side (group _x) == _droneSide || [side (group _x), _droneSide] call BIS_fnc_areFriendly} && {!isPlayer _x} };
                                if (count _friendlyUnits > 0) then {
                                    _man = _friendlyUnits select 0;
                                };
                            };
                            if (!isNull _man) then {
                                _drone setVariable ["CLDW_CurrentOperator", _man, true];
                                _drone setVariable ["ddtOwner", _man, true];
                            };
                        };
                                  if (!isNull _drone && {alive _drone} && {count (crew _drone) > 0}) then {
                            private _role = [_drone] call CLDW_fnc_getDroneRole;

                            if (_role == "SUICIDE") then {
                                private _currentTarget = _drone getVariable ["CLDW_CurrentTarget", objNull];
                                if (isNull _currentTarget || {!alive _currentTarget}) then {
                                    // Check for targets within the configured engagement range.
                                    private _targets = [_drone, missionNamespace getVariable ["CLDW_Setting_MaxRange", 2000]] call CLDW_fnc_getTargetsAT;
                                    if (count _targets > 0) then {
                                        private _target = _targets select 0;
                                        private _speed = (missionNamespace getVariable ["CLDW_Setting_DroneSpeed", 150]) / 3.6;
                                        _drone setVariable ["CLDW_Disengaged", false, true];
                                        _drone setVariable ["CLDW_CurrentTarget", _target, true];
                                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                                            systemChat format ["CLDW: Drone %1 engaging target %2 from %3m!", typeOf _drone, typeOf _target, round (_drone distance _target)];
                                        };
                                        [_drone, _target, _speed, 0.1] spawn CLDW_fnc_guideToTarget;
                                    } else {
                                        // Actively follow operator/squad in formation loiter if operator is alive
                                        if (!isNull _man && {alive _man} && {_drone distance _man > 30}) then {
                                            [_drone, getPosATL _man] call CLDW_fnc_move;
                                        };
                                    };
                                };
                            } else {
                                // Non-suicide drones (droppers, non-combat) NEVER suicide dive!
                                if (_role == "DROPPER") then {
                                    // Enforce calm, realistic dropper flight speed and safe bombing altitude
                                    private _dropperSpeed = ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 12;
                                    _drone setSpeedMode "NORMAL";
                                    _drone forceSpeed _dropperSpeed;
                                    _drone flyInHeight 80;

                                    // If the drone is actively executing a bombing run (has ammo / target / busy), do not interrupt it!
                                    private _hasAmmo = _drone getVariable ["ddtHasAmmo", true];
                                    private _isBusy = _drone getVariable ["ddtBusy", false];
                                    private _currentTarget = _drone getVariable ["CLDW_CurrentTarget", objNull];
                                    private _isBombingActive = _hasAmmo && {_isBusy || {!isNull _currentTarget && {alive _currentTarget}}};

                                    if (!_isBombingActive) then {
                                        // Drone is idle, out of ammo, or formation loitering with operator
                                        if (!isNull _man && {alive _man} && {_drone distance _man > 40}) then {
                                            [_drone, getPosATL _man] call CLDW_fnc_move;
                                        };
                                    };
                                } else {
                                    // NONCOMBAT (AL-6 Pelican, AR-2 Darter, Recon, Medical, Cargo)
                                    _drone setSpeedMode "NORMAL";
                                    _drone forceSpeed (38 / 3.6);
                                    _drone flyInHeight 40;
                                    if (!isNull _man && {alive _man} && {_drone distance _man > 40}) then {
                                        [_drone, getPosATL _man] call CLDW_fnc_move;
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // Periodically disable collisions between all friendly UAVs so swarms never collide mid-air
            private _allActiveUAVs = (+CLDW_activeDrones) select { !isNull _x && {alive _x} };
            private _uavCount = count _allActiveUAVs;
            if (_uavCount > 1) then {
                for "_i" from 0 to (_uavCount - 2) do {
                    private _uavA = _allActiveUAVs select _i;
                    if (!isNull _uavA && {alive _uavA}) then {
                        for "_j" from (_i + 1) to (_uavCount - 1) do {
                            private _uavB = _allActiveUAVs select _j;
                            if (!isNull _uavB && {alive _uavB}) then {
                                _uavA disableCollisionWith _uavB;
                                _uavB disableCollisionWith _uavA;
                            };
                        };
                    };
                };
            };

            // Periodically suppress AI launcher/RPG targeting against all active FPV drones
            {
                private _droneObj = _x;
                if (!isNull _droneObj && {alive _droneObj}) then {
                    private _nearLaunchers = (_droneObj nearEntities ["CAManBase", 350]) select {
                        !isPlayer _x && {alive _x} && {secondaryWeapon _x != ""}
                    };
                    {
                        if (currentWeapon _x == secondaryWeapon _x) then {
                            private _assigned = assignedTarget _x;
                            if (_assigned == _droneObj || {(_x targetKnowledge _droneObj) select 0}) then {
                                if (primaryWeapon _x != "") then {
                                    _x selectWeapon (primaryWeapon _x);
                                } else {
                                    if (handgunWeapon _x != "") then {
                                        _x selectWeapon (handgunWeapon _x);
                                    };
                                };
                                _x forgetTarget _droneObj;
                            };
                        };
                    } forEach _nearLaunchers;
                };
            } forEach _allActiveUAVs;

            // Periodically remove all UAV crew units from switchable units list
            {
                private _type = typeOf _x;
                private _isUAVCrew = (_type in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]) ||
                                     {getText (configFile >> "CfgVehicles" >> _type >> "simulation") == "UAVPilot"} ||
                                     {_x getVariable ["CLDW_IsDroneCrew", false]};
                if (_isUAVCrew) then {
                    if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                    if (!(_x getVariable ["CLDW_DroneCrewUsed", false])) then {
                        _x setVariable ["CLDW_DroneCrewUsed", true, true];
                    };
                };
            } forEach allUnits;
        };

        // Wreck cleanup: remove destroyed AI drones that native mod handlers leave behind.
        // Runs OUTSIDE the enable gate so lingering wrecks are always cleaned up.
        // A grace period lets each drone mod's own explosion/destruction scripts finish first;
        // contact and detonation behavior itself is never modified.
        {
            private _drone = _x;
            if (!isNull _drone && {!alive _drone && {!(_drone getVariable ["CLDW_WreckCleanupScheduled", false])}}) then {
                private _isCLDWDrone = (_drone getVariable ["CLDW_AI_Spawned", false])
                    || {!isNull (_drone getVariable ["CLDW_CurrentOperator", objNull])}
                    || {{ _x getVariable ["CLDW_IsDroneCrew", false] } count (crew _drone) > 0};
                if (_isCLDWDrone) then {
                    diag_log format ["CLDW [Cleanup]: Scheduling wreck deletion for '%1' in 10s.", typeOf _drone];
                    _drone setVariable ["CLDW_WreckCleanupScheduled", true];
                    [_drone] spawn {
                        params ["_drone"];
                        sleep 10; // Grace period for native explosion/deletion scripts
                        if (isNull _drone) exitWith {};
                        { _drone deleteVehicleCrew _x } forEach (crew _drone);
                        deleteVehicle _drone;
                    };
                };
            };
        } forEach (+CLDW_activeDrones);

        private _loopSpeed = missionNamespace getVariable ["CLDW_Setting_LoopSpeed", 10];
        if (_isFirstRun) then { _isFirstRun = false; sleep 1; } else { sleep _loopSpeed; };
    };
};
