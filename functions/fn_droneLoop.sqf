// Register EntityCreated handler to prevent FPV drone collisions and realign crew sides immediately upon spawn
addMissionEventHandler ["EntityCreated", {
    params ["_entity"];
    if (isNull _entity) exitWith {};
    if (!local _entity) exitWith {};
    
    private _type = typeOf _entity;
    if (_entity isKindOf "UAV" || {_entity isKindOf "Air"}) then {
        // Exclude Shahed and any drone spawned near a swarm launcher crate (which handles its own launch physics)
        private _lowerType = toLower _type;
        private _isProtectedType = (_lowerType find "crocus" > -1) || 
                                   {_lowerType find "kvn" > -1} || 
                                   {_lowerType find "uafpv" > -1} || 
                                   {_lowerType find "uav_02_ied" > -1} || 
                                   {_lowerType find "tura_uav" > -1} || 
                                   {_lowerType find "uas_06" > -1} ||
                                   {_lowerType find "rc40" > -1} ||
                                   {_lowerType find "rc-40" > -1};
        if (_isProtectedType && {!("shahed" in _lowerType)}) then {
            private _nearLaunchers = nearestObjects [_entity, ["CLDWC_DroneCrate_Swarm"], 15];
            if (count _nearLaunchers > 0) exitWith {};
            
            // 1. Safety positioning and temporary invincibility to prevent collision explosions (bypassed for launcher-fired RC-40)
            private _isRC40 = (_lowerType find "rc40" > -1) || {_lowerType find "rc-40" > -1};
            if (!_isRC40) then {
                _entity allowDamage false;
                
                _entity spawn {
                    params ["_drone"];
                    if (isNull _drone) exitWith {};

                    // Disable collision with any units and vehicles within 15 meters during the takeoff safety window
                    private _nearUnits = nearestObjects [_drone, ["CAManBase", "AllVehicles"], 15];
                    {
                        _drone disableCollisionWith _x;
                    } forEach _nearUnits;
                    
                    sleep 0.05; // Wait 1 frame for physics to initialize
                    if (isNull _drone) exitWith {};
                    
                    // Exclude player-owned and editor/Zeus-placed drones from safety relocation overrides
                    private _isPlayerOwned = false;
                    private _ownerStr = _drone getVariable ["ddtOwner", ""];
                    private _isEditorPlaced = (_ownerStr == "");
                    
                    if (_isEditorPlaced) exitWith {
                        _drone allowDamage true; // Re-enable damage immediately for editor/Zeus drones
                        { _drone enableCollisionWith _x; } forEach _nearUnits;
                    };
                    
                    private _owner = missionNamespace getVariable [_ownerStr, objNull];
                    if (isNull _owner) then {
                        { if (str _x == _ownerStr) exitWith { _owner = _x; }; } forEach allUnits;
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
                    
                    if (!_isPlayerOwned) then {
                        // AI-only: Perform relocation and stabilization (prevents clipping inside houses/ground)
                        private _spawnInAir = missionNamespace getVariable ["CLDW_Setting_SpawnInAir", false];
                        
                        if (_spawnInAir) then {
                            private _posATL = getPosATL _drone;
                            _drone setPosATL [_posATL select 0, _posATL select 1, 100];
                            _drone setVectorDirAndUp [vectorDir _drone, [0, 0, 1]];
                            _drone setVelocity [0, 0, 0.5];
                            _drone flyInHeight 100;
                            if (missionNamespace getVariable ["ddtDebug", false]) then {
                                systemChat format ["CLDW: Spawn-in-air activated. Teleported %1 to 100m AGL.", typeOf _drone];
                            };
                        } else {
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
                            } else {
                                // Ensure drone is clear of ground and other objects
                                private _posATL = getPosATL _drone;
                                if (_posATL select 2 < 3.5) then {
                                    _drone setPosATL [_posATL select 0, _posATL select 1, 3.5];
                                    _drone setVectorDirAndUp [vectorDir _drone, [0, 0, 1]];
                                    _drone setVelocity [0, 0, 0.5];
                                };
                            };
                        };
                        
                        // Keep it upright and stable for the first second of flight while engine initializes
                        for "_j" from 1 to 10 do {
                            if (isNull _drone || {!alive _drone}) exitWith {};
                            _drone setVectorDirAndUp [vectorDir _drone, [0, 0, 1]];
                            sleep 0.1;
                        };
                    } else {
                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                            systemChat "CLDW: Protected player-owned drone from takeoff collision; safety relocation bypassed.";
                        };
                    };
                    
                    // Allow takeoff phase / physics to settle before re-enabling damage and collisions
                    sleep 3.0;
                    if (!isNull _drone) then {
                        if (alive _drone) then {
                            _drone allowDamage true;
                        };
                        {
                            if (!isNull _x) then {
                                _drone enableCollisionWith _x;
                            };
                        } forEach _nearUnits;
                    };
                };
            };
            
            // 2. Instantly realign crew side to prevent friendly mortar targeting (AI-only)
            _entity spawn {
                params ["_drone"];
                sleep 0.05; // Wait 1 frame to detect ownership variables
                if (isNull _drone) exitWith {};
                
                // Exclude player-owned and editor/Zeus-placed drones from crew realignment
                private _isPlayerOwned = false;
                private _ownerStr = _drone getVariable ["ddtOwner", ""];
                private _owner = objNull;
                
                if (_ownerStr != "") then {
                    _owner = missionNamespace getVariable [_ownerStr, objNull];
                    if (isNull _owner) then {
                        { if (str _x == _ownerStr) exitWith { _owner = _x; }; } forEach allUnits;
                    };
                } else {
                    // Check parents if fired as a projectile (e.g. RC-40)
                    private _parents = getShotParents _drone;
                    if (count _parents > 0) then {
                        _owner = _parents select 1; // instigator
                        if (isNull _owner) then { _owner = _parents select 0; }; // fallback to vehicle
                        if (!isNull _owner) then {
                            _ownerStr = str _owner;
                            _drone setVariable ["ddtOwner", _ownerStr, true];
                            _drone setVariable ["CLDW_CurrentOperator", _owner, true];
                            _drone setVariable ["CLDW_OperatorGroup", group _owner, true];
                        };
                    };
                };
                
                if (_ownerStr == "") exitWith {}; // Exclude editor/Zeus placed drones
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
                    
                    // Move crew to a new group of the correct side or operator's squad if merging is active
                    private _ownerGrp = grpNull;
                    if (!isNull _owner) then { _ownerGrp = group _owner; };
                    private _shouldMerge = (!isNull _ownerGrp) && {missionNamespace getVariable ["CLDW_Setting_MergeDroneGroup", true]} && {!({isPlayer _x} count (units _ownerGrp) > 0)};
                    
                    if (_shouldMerge) then {
                        _crew joinSilent _ownerGrp;
                    } else {
                        private _newGrp = createGroup _side;
                        _crew joinSilent _newGrp;
                        _newGrp deleteGroupWhenEmpty true;
                    };
                    
                    // Release captive status now that side is aligned
                    {
                        _x setCaptive false;
                    } forEach _crew;
                    
                    // If it's an RC-40 HE drone, start the FPV script immediately
                    if (toLower (typeOf _drone) find "rc40_he" > -1) then {
                        [_drone, _owner] spawn {
                            params ["_drone", "_owner"];
                            sleep 0.5;
                            if (isNull _drone || {!alive _drone}) exitWith {};
                            [_drone, _owner] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
                        };
                    };
                };
            };
        };
    };
}];

// Register EntityKilled handler to attribute drone kills to operators/sides in RIS TDM
if (isServer) then {
    addMissionEventHandler ["EntityKilled", {
        params ["_killed", "_killer", "_instigator"];
        if (isNull _killed || {!(_killed isKindOf "CAManBase")}) exitWith {};
        
        private _lastAttacker = _killed getVariable ["CLDW_LastDroneAttacker", objNull];
        private _lastTime = _killed getVariable ["CLDW_LastDroneAttackerTime", 0];
        
        if (!isNull _lastAttacker && {time - _lastTime < 3.0}) then {
            if (!isNil "RSTF_fnc_unitKilled") then {
                [_killed, _lastAttacker, _lastAttacker] call RSTF_fnc_unitKilled;
            };
        };
    }];
};

// Register WeaponAssembled check on client-side safety loop to track player-driven assemblies

[] spawn { 
    // Wait for DDT mod to initialize, then apply overrides
    [] spawn {
        waitUntil { sleep 0.5; missionNamespace getVariable ["ddtReady", false] };
        DDT_fnc_getTargetsAT = CLDW_fnc_getTargetsAT;
        DDT_fnc_GetSoftTargets = CLDW_fnc_getSoftTargets;
        DDT_fnc_GuideToTarget = CLDW_fnc_guideToTarget;
        DDT_fnc_Move = CLDW_fnc_move;
        DDT_fnc_DroneGroupAlive = CLDW_fnc_droneGroupAlive;
        
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "CL Drone Warfare overrides applied successfully.";
        };
    };

    // Client-side safety: Prevent team-switching or remote-controlling drone crew units
    if (hasInterface) then {
        [] spawn {
            // Wait for player to be initialized
            waitUntil { !isNull player && {alive player} };
            
            // Instantly catch any TeamSwitch attempt to a UAV crew member
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

            private _fnc_addAssembledHandler = {
                params ["_unit"];
                if (isNull _unit || {_unit getVariable ["CLDW_AssembledHandler_Added", false]}) exitWith {};
                _unit setVariable ["CLDW_AssembledHandler_Added", true];
                _unit addEventHandler ["WeaponAssembled", {
                    params ["_unit", "_weapon"];
                    if (isNull _unit || {isNull _weapon}) exitWith {};
                    if (_weapon isKindOf "UAV" || {_weapon isKindOf "Air"}) then {
                        _weapon setVariable ["CLDW_CurrentOperator", _unit, true];
                        _weapon setVariable ["CLDW_OperatorGroup", group _unit, true];
                        _weapon setVariable ["ddtOwner", str _unit, true];
                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                            systemChat format ["CLDW: Registered manual assembly of %1 by %2.", typeOf _weapon, name _unit];
                        };
                    };
                }];
            };

            // Periodically verify player is not controlling a UAV crew unit and register assembly handler
            private _lastValidPlayer = player;
            while {true} do {
                private _p = player;
                if (!isNull _p) then {
                    [_p] call _fnc_addAssembledHandler;
                };
                private _isUAVCrew = false;
                if (!isNull _p) then {
                    private _type = typeOf _p;
                    if ((_type in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]) || 
                        {getText (configFile >> "CfgVehicles" >> _type >> "simulation") == "UAVPilot"} ||
                        {_p getVariable ["CLDW_IsDroneCrew", false]}) then {
                        _isUAVCrew = true;
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
                                    RSTF_DEATH_SIDE spawn RSTFM_fnc_spawnPlayer;
                                };
                            } else {
                                if (!isNil "RSTFM_fnc_playerKilled") then {
                                    [player, objNull] call RSTFM_fnc_playerKilled;
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

    sleep 2; 
    private _isFirstRun = true;

    private _fnc_isDroneBag = {
        params ["_bp"];
        if (_bp == "") exitWith { false };
        private _assembleTo = getText (configFile >> "CfgVehicles" >> _bp >> "assembleInfo" >> "assembleTo");
        if (_assembleTo != "") exitWith { true };
        private _lowerBp = toLower _bp;
        (("crocus" in _lowerBp) || ("kvn" in _lowerBp) || ("uafpv" in _lowerBp) || ("uas_06" in _lowerBp) || ("uav_02_ied" in _lowerBp) || ("tura_uav" in _lowerBp))
    };
 
    while {true} do { 
        if (CLDW_Setting_EnableMod) then {
            private _allActiveDrones = vehicles select { (_x isKindOf "UAV" || _x isKindOf "Air") && {alive _x} };
            { 
                private _group = _x; 
                private _groupSide = side _group;
 
                if (_groupSide != civilian) then { 
                    
                    // Exclude drone crew groups
                    if ({getText (configFile >> "CfgVehicles" >> typeOf _x >> "simulation") == "UAVPilot"} count (units _group) > 0) then {
                        continue;
                    };
                
                // CBA CHECK: Immersion guard check
                if (_groupSide == independent && {!CLDW_Setting_AllowIndependent}) then {
                    continue; 
                };
                if (_groupSide == west && {!CLDW_Setting_AllowBlufor}) then {
                    continue; 
                };
                if (_groupSide == east && {!CLDW_Setting_AllowOpfor}) then {
                    continue; 
                };

                // CBA CHECK: Exclude player's squad check
                if (CLDW_Setting_ExcludePlayerGroup && {{isPlayer _x} count (units _group) > 0}) then {
                    continue;
                };

                // AI turret/tower safety check: Strip drone bags from units in turrets or on watchtowers
                {
                    if !(isPlayer _x) then {
                        // Check for underbarrel grenade launcher and add RC-40 magazines
                        if (!(_x getVariable ["CLDW_RC40_Checked", false])) then {
                            _x setVariable ["CLDW_RC40_Checked", true, true];
                            private _unit = _x;
                            private _weapon = primaryWeapon _unit;
                            if (_weapon != "") then {
                                private _muzzles = getArray (configFile >> "CfgWeapons" >> _weapon >> "muzzles");
                                private _hasGL = false;
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
                                    {
                                        _x params ["_settingVar", "_magClass"];
                                        private _chance = missionNamespace getVariable [_settingVar, 0];
                                        if (_chance > 0 && {random 100 < _chance}) then {
                                            for "_i" from 1 to _ammoCount do {
                                                _unit addMagazine _magClass;
                                            };
                                            if (missionNamespace getVariable ["ddtDebug", false]) then {
                                                systemChat format ["CLDW: Added %1x RC-40 mag %2 to %3.", _ammoCount, _magClass, name _unit];
                                            };
                                        };
                                    } forEach [
                                        ["CLDW_Setting_RC40_HE", "1Rnd_RC40_HE_shell_RF"],
                                        ["CLDW_Setting_RC40_Recon", "1Rnd_RC40_shell_RF"],
                                        ["CLDW_Setting_RC40_SmokeBlue", "1Rnd_RC40_SmokeBlue_shell_RF"],
                                        ["CLDW_Setting_RC40_SmokeGreen", "1Rnd_RC40_SmokeGreen_shell_RF"],
                                        ["CLDW_Setting_RC40_SmokeOrange", "1Rnd_RC40_SmokeOrange_shell_RF"],
                                        ["CLDW_Setting_RC40_SmokeRed", "1Rnd_RC40_SmokeRed_shell_RF"],
                                        ["CLDW_Setting_RC40_SmokeWhite", "1Rnd_RC40_SmokeWhite_shell_RF"]
                                    ];
                                };
                            };
                        };

                        private _bp = backpack _x;
                        if (_bp != "") then {
                            private _isDroneBag = [_bp] call _fnc_isDroneBag;
                            if (_isDroneBag) then {
                                private _inTurret = (vehicle _x != _x);
                                private _onTower = ((getPosATL _x) select 2) > 1.8;
                                if (_inTurret || _onTower) then {
                                    removeBackpack _x;
                                    if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                                        private _terminalClass = switch (_groupSide) do {
                                            case west:  { "B_UavTerminal" };
                                            case east:  { "O_UavTerminal" };
                                            default     { "I_UavTerminal" };
                                        };
                                        _x unlinkItem _terminalClass;
                                    };
                                    if (missionNamespace getVariable ["ddtDebug", false]) then {
                                        systemChat format ["CLDW: Stripped drone bag from %1 on turret/tower.", name _x];
                                    };
                                };
                            };
                        };
                    };
                } forEach units _group;

                // Update and clean up the persistent operators list
                private _currentOperators = _group getVariable ["_chosen_drone_operators_list", []];
                _currentOperators = _currentOperators select { alive _x && {!isNull _x} };

                // Auto-detect any units already carrying drone backpacks and add them to the list
                {
                    if ([backpack _x] call _fnc_isDroneBag) then {
                        _currentOperators pushBackUnique _x;
                    };
                } forEach units _group;
                _group setVariable ["_chosen_drone_operators_list", _currentOperators];

                // If any operator is carrying a drone bag and enters combat, trigger deployment
                {
                    private _op = _x;
                    private _bp = backpack _op;
                    if (_bp != "" && {!(_op getVariable ["CLDW_Drone_Deploying", false])}) then {
                        private _inCombat = (behaviour _op == "COMBAT") || 
                                            { !isNull (_op findNearestEnemy _op) } ||
                                            { !((_op targets [true, 1000]) isEqualTo []) };
                        if (_inCombat) then {
                            _op setVariable ["CLDW_Drone_Deploying", true];
                            [_op, _bp] spawn {
                                params ["_operator", "_droneBackpack"];
                                sleep (1 + random 3);
                                if (isNull _operator || {!alive _operator} || {backpack _operator != _droneBackpack}) exitWith {
                                    _operator setVariable ["CLDW_Drone_Deploying", false];
                                };
                                
                                private _droneClass = _droneBackpack;
                                private _bagIndex = _droneBackpack find "_Bag";
                                if (_bagIndex != -1) then {
                                    _droneClass = _droneBackpack select [0, _bagIndex];
                                } else {
                                    private _bpIndex = _droneBackpack find "_backpack_F";
                                    if (_bpIndex != -1) then {
                                        _droneClass = (_droneBackpack select [0, _bpIndex]) + "_F";
                                    };
                                };
                                if (_droneClass == _droneBackpack) then {
                                    private _assembleTo = getText (configFile >> "CfgVehicles" >> _droneBackpack >> "assembleInfo" >> "assembleTo");
                                    if (_assembleTo != "") then { _droneClass = _assembleTo; };
                                };
                                
                                private _spawnPos = getPosATL _operator;
                                private _spawnPosFinal = if (missionNamespace getVariable ["CLDW_Setting_SpawnInAir", false]) then {
                                    [_spawnPos select 0, _spawnPos select 1, 100]
                                } else {
                                    _spawnPos vectorAdd [(sin (getDir _operator)) * 1.5, (cos (getDir _operator)) * 1.5, 1.5]
                                };
                                private _drone = createVehicle [_droneClass, _spawnPosFinal, [], 0, "FLY"];
                                
                                if (!isNull _drone) then {
                                    _drone setVariable ["CLDW_CurrentOperator", _operator, true];
                                    _drone setVariable ["CLDW_OperatorGroup", group _operator, true];
                                    _drone setVariable ["ddtOwner", str _operator, true];
                                    
                                    removeBackpack _operator;
                                    createVehicleCrew _drone;
                                    
                                    private _crew = crew _drone;
                                    if (count _crew > 0) then {
                                        {
                                            _x setVariable ["CLDW_IsDroneCrew", true, true];
                                            _x setVariable ["USED", true, true];
                                        } forEach _crew;
                                        
                                        private _side = side group _operator;
                                        private _newGrp = createGroup _side;
                                        _crew joinSilent _newGrp;
                                        _newGrp deleteGroupWhenEmpty true;
                                    };
                                    
                                    _drone allowDamage false;
                                    _drone setFuel 1;
                                    _drone engineOn true;
                                    
                                    [_drone, _operator] spawn {
                                        params ["_drone", "_operator"];
                                        sleep 0.2;
                                        if (isNull _drone || {!alive _drone}) exitWith {};
                                        [_drone, _operator] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
                                    };
                                    
                                    if (missionNamespace getVariable ["ddtDebug", false]) then {
                                        systemChat format ["CLDW: AI %1 deployed drone %2 in combat.", name _operator, typeOf _drone];
                                    };
                                };
                                _operator setVariable ["CLDW_Drone_Deploying", false];
                            };
                        };
                    };
                } forEach _currentOperators;

                if (_currentOperators isEqualTo []) then { _group setVariable ["_drone_initialized", false]; };

                private _currentDroneCount = count _currentOperators;
                private _maxAllowedDrones = round (missionNamespace getVariable ["CLDW_Setting_MaxDrones", 2]);
                private _minSquadSize = round (missionNamespace getVariable ["CLDW_Setting_MinSquadSize", 4]);

                if (_currentDroneCount < _maxAllowedDrones) then { 
                    if ((count units _group) >= _minSquadSize) then { 
                        
                        // Build AP/AT bag pools conditionally based on active mod settings
                        private _apBags = [];
                        private _atBags = [];

                        // Crocus FPV (DarkBall) — AP and AT
                        if (missionNamespace getVariable ["CLDW_Mod_Crocus", false]) then {
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
                        if (missionNamespace getVariable ["CLDW_Mod_KVN", false]) then {
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
                        if (missionNamespace getVariable ["CLDW_Mod_UAFPV_Tom", false]) then {
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
                        if (missionNamespace getVariable ["CLDW_Mod_UAFPV_BIG", false]) then {
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



                        // Western Sahara IED UAV (bomber — targets vehicles; placed in AT quota)
                        if (missionNamespace getVariable ["CLDW_Mod_WS_IED", false]) then {
                            private _at = (switch (_groupSide) do {
                                case west:  { ["B_Tura_UAV_02_IED_backpack_lxws", "B_G_UAV_02_IED_backpack_lxWS"] };
                                case east:  { ["B_Tura_UAV_02_IED_backpack_lxws", "B_G_UAV_02_IED_backpack_lxWS"] };
                                default     { ["B_Tura_UAV_02_IED_backpack_lxws", "B_G_UAV_02_IED_backpack_lxWS"] };
                            }) select { isClass (configFile >> "CfgVehicles" >> _x) };
                            _atBags append _at;
                        };

                        // Fallback to vanilla AL-6 Darter UAV backpacks if no custom mods are loaded or active
                        if (_apBags isEqualTo [] && {_atBags isEqualTo []}) then {
                            private _fallbackBag = switch (_groupSide) do {
                                case west:  { "B_UAS_06_backpack_F" };
                                case east:  { "O_UAS_06_backpack_F" };
                                default     { "I_UAS_06_backpack_F" };
                            };
                            _apBags = [_fallbackBag];
                            _atBags = [_fallbackBag];
                        };

                        // Count how many AP and AT operators this group currently has (checks both backpacks and active drones)
                        private _currentAP = 0;
                        private _currentAT = 0;
                        {
                            private _bp = backpack _x;
                            if (_bp != "") then {
                                if (_bp in _apBags) then { _currentAP = _currentAP + 1; };
                                if (_bp in _atBags) then { _currentAT = _currentAT + 1; };
                            } else {
                                private _unit = _x;
                                {
                                    private _op = _x getVariable ["CLDW_CurrentOperator", objNull];
                                    if (_op == _unit) then {
                                        private _type = typeOf _x;
                                        private _lowerType = toLower _type;
                                        private _isAT = ("at" in _lowerType) || ("ied" in _lowerType) || ("pg7" in _lowerType) || ("600" in _lowerType);
                                        if (_isAT) then { _currentAT = _currentAT + 1; } else { _currentAP = _currentAP + 1; };
                                    };
                                } forEach _allActiveDrones;
                            };
                        } forEach _currentOperators;

                        // Decide whether we want to give AP or AT based on alternating requirements
                        private _pool = [];
                        private _wantAP = _currentAP <= _currentAT;

                        if (_wantAP) then {
                            if !(_apBags isEqualTo []) then {
                                _pool = _apBags;
                            } else {
                                _pool = _atBags;
                            };
                        } else {
                            if !(_atBags isEqualTo []) then {
                                _pool = _atBags;
                            } else {
                                _pool = _apBags;
                            };
                        };

                        // Fallback to avoid empty pool
                        if (_pool isEqualTo []) then {
                            _pool = _apBags + _atBags;
                        };

                        private _groupBackpacks = [];
                        { _groupBackpacks pushBackUnique (backpack _x); } forEach units _group;

                        // Prefer bag types not already in the group (variety check)
                        private _uniquePool = _pool select { !(_x in _groupBackpacks) };
                        if (_uniquePool isEqualTo []) then { _uniquePool = _pool; };

                        private _eligibleUnits = []; 
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
                            private _droneBackpack = selectRandom _uniquePool; 
                
                              if (backpack _operator != "") then {
                                  removeBackpack _operator;
                              };
                              _operator addBackpack _droneBackpack;

                            // Give AI UAV Terminal if enabled so players can loot it
                            if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
                                private _terminalClass = switch (_groupSide) do {
                                    case west:  { "B_UavTerminal" };
                                    case east:  { "O_UavTerminal" };
                                    default     { "I_UavTerminal" };
                                };
                                _operator linkItem _terminalClass;
                            }; 

                            // AI Immediate Drone Deployment Feature
                            private _deployImmediatelySetting = missionNamespace getVariable ["CLDW_Setting_AIDeployImmediately", 1];
                            private _shouldDeploy = false;
                            if (_deployImmediatelySetting == 2) then {
                                _shouldDeploy = true;
                            };
                            if (_deployImmediatelySetting == 1) then {
                                private _isRISActive = !isNil "RSTF_init" || {!isNil "RSTF_STATE"};
                                if (_isRISActive) then {
                                    _shouldDeploy = true;
                                };
                            };

                            if (_shouldDeploy) then {
                                [_operator, _droneBackpack] spawn {
                                    params ["_operator", "_droneBackpack"];
                                    sleep (1 + random 2); // Small delay to feel natural and prevent instant spawn blocking
                                    if (isNull _operator || {!alive _operator} || {backpack _operator != _droneBackpack}) exitWith {};

                                    private _droneClass = _droneBackpack;
                                    private _bagIndex = _droneBackpack find "_Bag";
                                    if (_bagIndex != -1) then {
                                        _droneClass = _droneBackpack select [0, _bagIndex];
                                    } else {
                                        private _bpIndex = _droneBackpack find "_backpack_F";
                                        if (_bpIndex != -1) then {
                                            _droneClass = (_droneBackpack select [0, _bpIndex]) + "_F";
                                        };
                                    };
                                    // Fallback: resolve via assembleInfo for non-standard backpack names (Switchblade tubes, WS IED UAV, etc.)
                                    if (_droneClass == _droneBackpack) then {
                                        private _assembleTo = getText (configFile >> "CfgVehicles" >> _droneBackpack >> "assembleInfo" >> "assembleTo");
                                        if (_assembleTo != "") then { _droneClass = _assembleTo; };
                                    };

                                    // Relocate spawn position slightly forward and up to prevent collision stuck
                                    private _spawnPos = getPosATL _operator;
                                    private _spawnPosFinal = if (missionNamespace getVariable ["CLDW_Setting_SpawnInAir", false]) then {
                                        [_spawnPos select 0, _spawnPos select 1, 100]
                                    } else {
                                        _spawnPos vectorAdd [(sin (getDir _operator)) * 1.5, (cos (getDir _operator)) * 1.5, 1.5]
                                    };
                                    private _drone = createVehicle [_droneClass, _spawnPosFinal, [], 0, "FLY"];

                                    if (!isNull _drone) then {
                                        // Set owner references before EntityCreated event handler finishes frame initialization
                                        _drone setVariable ["CLDW_CurrentOperator", _operator, true];
                                        _drone setVariable ["CLDW_OperatorGroup", group _operator, true];
                                        _drone setVariable ["ddtOwner", str _operator, true];

                                        removeBackpack _operator;
                                        createVehicleCrew _drone;

                                        private _crew = crew _drone;
                                        if (count _crew > 0) then {
                                            {
                                                _x setVariable ["CLDW_IsDroneCrew", true, true];
                                                _x setVariable ["USED", true, true];
                                            } forEach _crew;

                                            // Join drone crew to a silent side group to avoid cluttering operator's squad commands
                                            private _side = side group _operator;
                                            private _newGrp = createGroup _side;
                                            _crew joinSilent _newGrp;
                                            _newGrp deleteGroupWhenEmpty true;
                                        };

                                        _drone allowDamage false; // Let EntityCreated handler run safety Relocation
                                        _drone setFuel 1;
                                        _drone engineOn true;

                                        // Register monitoring on the operator unit
                                        if (missionNamespace getVariable ["CLDW_Setting_MergeDroneGroup", true]) then {
                                            if !(_operator getVariable ["CLDW_DroneMonitor_Active", false]) then {
                                                _operator setVariable ["CLDW_DroneMonitor_Active", true];
                                                [_operator, group _operator] spawn {
                                                    params ["_operator", "_grp"];
                                                    while {alive _operator} do {
                                                        if (backpack _operator == "") then {
                                                            sleep 2;
                                                            private _drones = nearestObjects [_operator, ["Air", "LandVehicle"], 50];
                                                            {
                                                                private _veh = _x;
                                                                private _type = typeOf _veh;
                                                                if ((_type find "Crocus" > -1) || (_type find "KVN" > -1) || (_type find "UAFPV" > -1) || (_type find "UAV_02_IED" > -1) || (_type find "Tura_UAV" > -1) || (_veh isKindOf "UAV")) then {
                                                                    private _crew = crew _veh;
                                                                    if (count _crew > 0 && {group (_crew select 0) != _grp}) then {
                                                                        { 
                                                                            _x setVariable ["CLDW_IsDroneCrew", true, true]; 
                                                                            _x setVariable ["USED", true, true];
                                                                            if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                                                                        } forEach _crew;
                                                                        if (!({isPlayer _x} count (units _grp) > 0)) then {
                                                                            _crew joinSilent _grp;
                                                                        } else {
                                                                            private _separateGrp = createGroup (side _grp);
                                                                            _crew joinSilent _separateGrp;
                                                                            _separateGrp deleteGroupWhenEmpty true;
                                                                        };
                                                                    };
                                                                };
                                                            } forEach _drones;
                                                            waitUntil { sleep 5; !alive _operator || backpack _operator != "" };
                                                        };
                                                        sleep 2;
                                                    };
                                                    if (alive _operator) then { _operator setVariable ["CLDW_DroneMonitor_Active", false]; };
                                                };
                                            };
                                        };

                                        // Start the FPV target acquisition script
                                        [_drone, _operator] spawn {
                                            params ["_drone", "_operator"];
                                            sleep 0.2;
                                            if (isNull _drone || {!alive _drone}) exitWith {};
                                            [_drone, _operator] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
                                        };
                                        
                                        if (missionNamespace getVariable ["ddtDebug", false]) then {
                                            systemChat format ["CLDW: AI %1 immediately deployed drone %2.", name _operator, typeOf _drone];
                                        };
                                    };
                                };
                            };
                
                            if (missionNamespace getVariable ["CLDW_Setting_MergeDroneGroup", true]) then {
                                if !(_operator getVariable ["CLDW_DroneMonitor_Active", false]) then {
                                    _operator setVariable ["CLDW_DroneMonitor_Active", true];
                                    [_operator, group _operator] spawn {
                                        params ["_operator", "_grp"];
                                        while {alive _operator} do {
                                            if (backpack _operator == "") then {
                                                sleep 2;
                                                private _drones = nearestObjects [_operator, ["Air", "LandVehicle"], 50];
                                                {
                                                    private _veh = _x;
                                                    private _type = typeOf _veh;
                                                    if ((_type find "Crocus" > -1) || (_type find "KVN" > -1) || (_type find "UAFPV" > -1) || (_type find "UAV_02_IED" > -1) || (_type find "Tura_UAV" > -1) || (_veh isKindOf "UAV")) then {
                                                        private _crew = crew _veh;
                                                        if (count _crew > 0 && {group (_crew select 0) != _grp}) then {
                                                            { 
                                                                _x setVariable ["CLDW_IsDroneCrew", true, true]; 
                                                                _x setVariable ["USED", true, true];
                                                                if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                                                            } forEach _crew;
                                                            // Avoid adding virtual crew to player-led or player-containing groups
                                                            if (!({isPlayer _x} count (units _grp) > 0)) then {
                                                                _crew joinSilent _grp;
                                                            } else {
                                                                private _separateGrp = createGroup (side _grp);
                                                                _crew joinSilent _separateGrp;
                                                                _separateGrp deleteGroupWhenEmpty true;
                                                            };
                                                        };
                                                    };
                                                } forEach _drones;
                                                waitUntil { sleep 5; !alive _operator || backpack _operator != "" };
                                            };
                                            sleep 2;
                                        };
                                        if (alive _operator) then { _operator setVariable ["CLDW_DroneMonitor_Active", false]; };
                                    };
                                };
                            };
                            
                            _currentOperators pushBackUnique _operator;
                            _group setVariable ["_chosen_drone_operators_list", _currentOperators]; 
                            _group setVariable ["_drone_initialized", true]; 
                            
                            // Force combat mode on backpack assignment
                            if (missionNamespace getVariable ["CLDW_Setting_CombatMode", false]) then {
                                _group setCombatMode "RED";
                                _group setBehaviour "COMBAT";
                            };
                            _operator setUnitAbility 1.0; 
                        }; 
                    }; 
                }; 
            }; 
        } forEach allGroups; 
        
        // Re-engagement monitor for disengaged/idle drones (suicide/FPV variants only)
        {
            private _drone = _x;
            private _uavType = toLower (typeOf _drone);
            private _isSuicide = (_uavType find "crocus" > -1) || 
                                 {_uavType find "kvn" > -1} || 
                                 {_uavType find "uafpv" > -1} || 
                                 {_uavType find "rc40_he" > -1} || 
                                 {_uavType find "uav_02_ied" > -1} || 
                                 {_uavType find "tura_uav" > -1};
            if (_isSuicide && {alive _drone && {!(_drone getVariable ["CLDW_Disengaged", false])}}) then {
                private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
                if (!isNull _man && {alive _man}) then {
                    private _heartbeat = _drone getVariable ["CLDW_FPV_Running", 0];
                    if (time > _heartbeat) then {
                        // FPV loop is idle. Check if targets are available
                        private _targets = [_man, 2000] call CLDW_fnc_getTargetsAT;
                        if (count _targets > 0) then {
                            if (missionNamespace getVariable ["ddtDebug", false]) then {
                                systemChat format ["Idle drone %1 re-engaging target!", _drone];
                            };
                            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
                        };
                    };
                };
            };
        } forEach (vehicles select { _x isKindOf "UAV" || _x isKindOf "Air" });

        // Periodically remove all UAV crew units from switchable units list (protection override)
        {
            private _type = typeOf _x;
            private _isUAVCrew = (_type in ["B_UAV_AI", "O_UAV_AI", "I_UAV_AI"]) || 
                                 {getText (configFile >> "CfgVehicles" >> _type >> "simulation") == "UAVPilot"} ||
                                 {_x getVariable ["CLDW_IsDroneCrew", false]};
            if (_isUAVCrew) then {
                if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                if (!(_x getVariable ["USED", false])) then {
                    _x setVariable ["USED", true, true];
                };
            };
        } forEach allUnits;
        };
 
        // CBA CHECK: Read sleep interval directly from menu slider dynamically
        if (_isFirstRun) then { _isFirstRun = false; sleep 1; } else { sleep CLDW_Setting_LoopSpeed; }; 
    }; 
};