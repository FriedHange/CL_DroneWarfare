// Register EntityCreated handler to prevent FPV drone collisions and realign crew sides immediately upon spawn
addMissionEventHandler ["EntityCreated", {
    params ["_entity"];
    if (isNull _entity) exitWith {};
    if (!local _entity) exitWith {};
    
    private _type = typeOf _entity;
    if (_entity isKindOf "UAV" || {_entity isKindOf "Air"}) then {
        // Exclude Shahed and any drone spawned near a swarm launcher crate (which handles its own launch physics)
        if (((_type find "Crocus" > -1) || (_type find "KVN" > -1) || (_type find "UAFPV" > -1)) && {!("Shahed" in _type)}) then {
            private _nearLaunchers = nearestObjects [_entity, ["CLDWC_DroneCrate_Swarm"], 15];
            if (count _nearLaunchers > 0) exitWith {};
            
            // 1. Safety positioning and temporary invincibility to prevent collision explosions (AI-only)
            _entity allowDamage false;
            
            _entity spawn {
                params ["_drone"];
                sleep 0.05; // Wait 1 frame for physics to initialize
                if (isNull _drone) exitWith {};
                
                // Exclude player-owned and editor/Zeus-placed drones from safety overrides
                private _isPlayerOwned = false;
                private _ownerStr = _drone getVariable ["ddtOwner", ""];
                if (_ownerStr == "") exitWith {
                    _drone allowDamage true; // Re-enable damage immediately for editor/Zeus drones
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
                if (_isPlayerOwned) exitWith {
                    _drone allowDamage true; // Re-enable damage immediately for player drone
                    if (missionNamespace getVariable ["ddtDebug", false]) then {
                        systemChat "CLDW: Excluded player-owned drone from safety relocation.";
                    };
                };
                
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
                
                // Keep it upright and stable for the first second of flight while engine initializes
                for "_j" from 1 to 10 do {
                    if (isNull _drone || {!alive _drone}) exitWith {};
                    _drone setVectorDirAndUp [vectorDir _drone, [0, 0, 1]];
                    sleep 0.1;
                };
                
                // Allow physics to settle before re-enabling damage
                sleep 3.0;
                if (!isNull _drone && {alive _drone}) then {
                    _drone allowDamage true;
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
                if (_ownerStr == "") exitWith {}; // Exclude editor/Zeus placed drones
                
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
                    private _ownerStr = _drone getVariable ["ddtOwner", ""];
                    private _side = sideUnknown;
                    if (_ownerStr != "") then {
                        private _owner = missionNamespace getVariable [_ownerStr, objNull];
                        if (isNull _owner) then {
                            {
                                if (str _x == _ownerStr) exitWith { _owner = _x; };
                            } forEach allUnits;
                        };
                        if (!isNull _owner) then {
                            _side = side group _owner;
                        };
                    };
                    
                    if (_side == sideUnknown) then {
                        private _type = typeOf _drone;
                        if (_type select [0, 2] == "B_") then { _side = west; };
                        if (_type select [0, 2] == "O_") then { _side = east; };
                        if (_type select [0, 2] == "I_") then { _side = independent; };
                    };
                    
                    if (_side == sideUnknown) then { _side = civilian; };
                    
                    // Move crew to a new group of the correct side
                    private _newGrp = createGroup _side;
                    _crew joinSilent _newGrp;
                    _newGrp deleteGroupWhenEmpty true;
                    
                    // Release captive status now that side is aligned
                    {
                        _x setCaptive false;
                    } forEach _crew;
                };
            };
        };
    };
}];

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

            // Periodically verify player is not controlling a UAV crew unit
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
 
    while {true} do { 
        if (CLDW_Setting_EnableMod) then {
            { 
                private _group = _x; 
            private _groupSide = side _group;
 
            if (_groupSide != civilian) then { 
                
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
                        private _bp = backpack _x;
                        if (_bp != "") then {
                            private _isDroneBag = ("Crocus" in _bp) || ("KVN" in _bp) || ("UAFPV" in _bp) || ("UAS_06" in _bp);
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
                    };
                } forEach units _group;

                private _currentOperators = _group getVariable ["_chosen_drone_operators_list", []]; 
                _currentOperators = _currentOperators select { alive _x && {!isNull _x} };
                _group setVariable ["_chosen_drone_operators_list", _currentOperators];
 
                if (_currentOperators isEqualTo []) then { _group setVariable ["_drone_initialized", false]; };
                
                // CBA CHECK: Scale drone distribution count dynamically based on menu slider
                private _currentDroneCount = count _currentOperators;
                private _maxAllowedDrones = round (missionNamespace getVariable ["CLDW_Setting_MaxDrones", 3]);
                private _minSquadSize = round (missionNamespace getVariable ["CLDW_Setting_MinSquadSize", 4]);
 
                if (_currentDroneCount < _maxAllowedDrones) then { 
                    if ((count units _group) >= _minSquadSize) then { 
                        
                        private _sideDrones = switch (_groupSide) do { 
                            case west: { ["B_Crocus_AP_Bag", "B_Crocus_AT_Bag", "B_KVN_AP_Bag", "B_KVN_AT_Bag", "B_UAFPV_IED_AP_Bag", "B_UAFPV_OG7V_AP_Bag", "B_UAFPV_RKG_AP_Bag", "B_UAFPV_PG7VL_AT_Bag"] }; 
                            case east:  { ["O_Crocus_AP_Bag", "O_Crocus_AT_Bag", "O_KVN_AP_Bag", "O_KVN_AT_Bag", "O_UAFPV_IED_AP_Bag", "O_UAFPV_OG7V_AP_Bag", "O_UAFPV_RKG_AP_Bag", "O_UAFPV_PG7VL_AT_Bag"] }; 
                            default      { ["I_Crocus_AP_Bag", "I_Crocus_AT_Bag", "I_KVN_AP_Bag", "I_KVN_AT_Bag", "I_UAFPV_IED_AP_Bag", "I_UAFPV_OG7V_AP_Bag", "I_UAFPV_RKG_AP_Bag", "I_UAFPV_PG7VL_AT_Bag"] }; 
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
                            private _availableTypes = _sideDrones select { !(_x in _groupBackpacks) };
                            if (_availableTypes isEqualTo []) then { _availableTypes = _sideDrones; };
                            private _droneBackpack = selectRandom _availableTypes; 
                
                            if (backpack _operator != "") then {
                                removeBackpack _operator;
                            };
                            _operator addBackpack _droneBackpack; 
                
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
                                                    if ((_type find "Crocus" > -1) || (_type find "KVN" > -1) || (_type find "UAFPV" > -1) || (_veh isKindOf "UAV")) then {
                                                        private _crew = crew _veh;
                                                        if (count _crew > 0 && {group (_crew select 0) != _grp}) then {
                                                            { 
                                                                _x setVariable ["CLDW_IsDroneCrew", true, true]; 
                                                                _x setVariable ["USED", true, true];
                                                                if (_x in switchableUnits) then { removeSwitchableUnit _x; };
                                                            } forEach _crew;
                                                            // Avoid adding virtual crew to player-led or player-containing groups to prevent UI clutter and softlocks
                                                            if (!({isPlayer _x} count (units _grp) > 0)) then {
                                                                _crew joinSilent _grp;
                                                            } else {
                                                                // If the group contains players, join the crew to a new separate group of the same side to prevent UI clutter
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
                            
                            _currentOperators pushBack _operator;
                            _group setVariable ["_chosen_drone_operators_list", _currentOperators]; 
                            _group setVariable ["_drone_initialized", true]; 
                            
                            // Force combat mode on backpack assignment
                            if (CLDW_Setting_CombatMode) then {
                                _group setCombatMode "RED";
                                _group setBehaviour "COMBAT";
                            };
                            _operator setUnitAbility 1.0; 
                        }; 
                    }; 
                }; 
            }; 
        } forEach allGroups; 
        
        // Re-engagement monitor for disengaged/idle drones
        {
            private _drone = _x;
            if (alive _drone && {!(_drone getVariable ["CLDW_Disengaged", false])}) then {
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