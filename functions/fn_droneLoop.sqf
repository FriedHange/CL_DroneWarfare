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
            private _otherUAVs = (+(missionNamespace getVariable ["CLDW_activeDrones", []])) select { !isNull _x && {alive _x} && {_x != _entity} };
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
            [_this param [0, objNull], "BOMBER", _this] call CLDW_fnc_startController;
        };

        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "CL Drone Warfare overrides applied successfully.";
        };
    };

    // =========================================================================
    // RIS (Random Infantry Skirmish) Compatibility & Death Camera Sanitization
    // Resolves drone kills back to the operator and ensures kills count in scores
    // =========================================================================
    [] spawn {
        // Wait for mission functions to initialize (polling for up to 30 seconds)
        private _risDetected = false;
        for "_i" from 1 to 30 do {
            if (!isNil "RSTF_fnc_playerKilled" || {!isNil "RSTF_fnc_unitKilled"} || {!isNil "RSTFM_fnc_playerKilled"} || {!isNil "RSTFM_fnc_unitKilled"} || {!isNil "RSTF_fnc_showDeath"}) exitWith {
                _risDetected = true;
            };
            sleep 1;
        };

        if (!_risDetected) exitWith {};

        diag_log "CLDW: RIS mission detected. Enabling paced squad resupply and death camera sanitization.";
        if (isServer) then { missionNamespace setVariable ["CLDW_RISMode", true]; };

        // RIS kill functions are final; its own handlers remain the sole score authority.
        // Mission-level EntityKilled handler: drone tagging and death camera safety.
        addMissionEventHandler ["EntityKilled", {
            params ["_unit", "_killer", "_instigator"];

            // 1. Drone detonation tagging: When an active or player-controlled drone is destroyed/detonates,
            // immediately tag all entities within blast radius so explosive casualties resolve to the operator
            private _isDrone = (_unit isKindOf "UAV") || {unitIsUAV _unit} || {_unit getVariable ["CLDW_IsDroneCrew", false]} || {_unit getVariable ["ddtDrone", false]};
            if (_isDrone) then {
                private _op = _unit getVariable ["CLDW_CurrentOperator", objNull];
                if (isNull _op) then { _op = _unit getVariable ["CLDW_LastController", objNull]; };
                if (isNull _op) then { _op = _unit getVariable ["ddtOwner", objNull]; };
                if (isNull _op) then {
                    private _ctrl = uavControl _unit select 0;
                    if (!isNull _ctrl && {alive _ctrl}) then { _op = _ctrl; };
                };
                if (!isNull _op && {alive _op}) then {
                    private _opSide = side group _op;
                    private _dronePos = getPosATL _unit;
                    private _near = _dronePos nearEntities [["CAManBase", "LandVehicle", "Air", "Ship"], 35];
                    {
                        if (!isNull _x && {_x != _unit}) then {
                            _x setVariable ["CLDW_LastDroneAttacker", _op, true];
                            _x setVariable ["CLDW_LastDroneAttackerTime", time, true];
                            _x setVariable ["CLDW_LastDroneAttackerSide", _opSide, true];
                        };
                    } forEach _near;
                };
            };

            // 2. Player death camera sanitization on interface clients
            if (hasInterface) then {
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
                if (_isControllingUAV) then {
                    private _connUAV = getConnectedUAV _p;
                    if (!(_connUAV getVariable ["CLDW_AI_Spawned",false]) &&
                        {(_connUAV getVariable ["CLDW_CurrentOperator", objNull]) != _p}) then {
                        _connUAV setVariable ["CLDW_CurrentOperator", _p, true];
                    };
                    _connUAV setVariable ["CLDW_LastController", _p, true];
                };

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
    if (isNil "CLDW_retiringDrones") then { CLDW_retiringDrones = []; };
    if (isNil "CLDW_deployQueue") then { CLDW_deployQueue = []; };

    // One unscheduled launch attempt every 0.25 seconds. Blocked entries rotate fairly.
    [{
        if (count CLDW_deployQueue > 0) then {
            private _op = CLDW_deployQueue deleteAt 0;
            if ([_op] call CLDW_fnc_deploy) then {
                if (!isNull _op) then { _op setVariable ["CLDW_Drone_Queued", false]; };
            } else {
                CLDW_deployQueue pushBack _op;
            };
        };
    }, 0.25] call CBA_fnc_addPerFrameHandler;

    // Independently tick actual owners and clean wrecks before pruning the registry.
    [] spawn {
        while {true} do {
            {
                private _drone = _x;
                if (!isNull _drone) then {
                    if (alive _drone) then {
                        private _assigned = _drone getVariable ["CLDW_AssignedOperator",objNull];
                        if (_drone getVariable ["CLDW_AI_Spawned",false] &&
                            {_drone getVariable ["CLDW_OperatorBound",false]} &&
                            {!(_drone getVariable ["CLDW_Orphaned",false])} &&
                            {isNull _assigned || {!alive _assigned}}) then {
                            _drone setVariable ["CLDW_Orphaned",true,true];
                            CLDW_retiringDrones pushBackUnique _drone;
                            diag_log format ["CLDW [Orphan]: Assigned operator lost for %1.",typeOf _drone];
                        };
                        if (_drone getVariable ["CLDW_Orphaned",false]) then {
                            CLDW_retiringDrones pushBackUnique _drone;
                        } else {
                        if (_drone getVariable ["CLDW_EWReturnPending", false]) then {
                            private _home = _drone getVariable ["EWDJ_home", []];
                            private _cfg = missionNamespace getVariable ["EWDJ_cfg", createHashMap];
                            if (count _home != 3 || {_drone distance2D _home <= 30} ||
                                {!(_cfg getOrDefault ["softReturnHome", true])} ||
                                {!(_cfg getOrDefault ["affectAI", true])}) then {
                                _drone setVariable ["CLDW_EWReturnPending", false, true];
                            };
                        };
                        if (missionNamespace getVariable ["CLDW_Setting_EnableMod", true]) then {
                            [_drone] remoteExecCall ["CLDW_fnc_droneTick", _drone];
                        };
                        };
                    } else {
                        if !(_drone getVariable ["CLDW_WreckCleanupScheduled", false]) then {
                            _drone setVariable ["CLDW_WreckCleanupScheduled", true];
                            [_drone] spawn {
                                params ["_drone"];
                                sleep 10;
                                if (!isNull _drone) then {
                                    { _drone deleteVehicleCrew _x; } forEach crew _drone;
                                    deleteVehicle _drone;
                                };
                            };
                        };
                    };
                };
                sleep 0.01;
            } forEach (+(missionNamespace getVariable ["CLDW_activeDrones", []]));
            {
                if (!isNull _x && {!(_x getVariable ["CLDW_OrphanFinalized",false])}) then {
                    [_x] remoteExecCall ["CLDW_fnc_retireOrphan",_x];
                    private _orphan = _x;
                    {
                        if (alive _x && {!isPlayer _x}) then {
                            [_orphan,_x] remoteExecCall ["CLDW_fnc_retireOrphanCrew",_x];
                        };
                    } forEach crew _orphan;
                };
            } forEach CLDW_retiringDrones;
            CLDW_retiringDrones = CLDW_retiringDrones select {
                !isNull _x && {!(_x getVariable ["CLDW_OrphanFinalized",false])}
            };
            CLDW_activeDrones = CLDW_activeDrones select {
                !isNull _x && {alive _x} && {!(_x getVariable ["CLDW_Orphaned",false])}
            };
            sleep 1;
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

                    // RC-40 remains an independent one-time inventory allocation.
                    {
                        if !(isPlayer _x) then {
                            // RC-40 magazine distribution — one-shot per unit (flag prevents re-running)
                            if (!_excludeFromDistribution && {!(_x getVariable ["CLDW_RC40_Checked", false])}) then {
                                [_x] remoteExecCall ["CLDW_fnc_supplyRC40", _x];
                            };
                        };
                    } forEach units _group;

                    [_group] call CLDW_fnc_assignSquad;
                    [_group] call CLDW_fnc_queueSquad;
                    sleep 0.01; // Spread group scans over scheduler frames.

                };
            } forEach allGroups;

            private _allActiveUAVs = (+(missionNamespace getVariable ["CLDW_activeDrones", []])) select {!isNull _x && {alive _x}};
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

        private _loopSpeed = missionNamespace getVariable ["CLDW_Setting_LoopSpeed", 10];
        if (_isFirstRun) then { _isFirstRun = false; sleep 1; } else { sleep _loopSpeed; };
    };
};
