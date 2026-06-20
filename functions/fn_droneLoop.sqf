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

                if (_isUAVCrew) then {
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
                        };
                    };
                } else {
                    if (!isNull _p && {alive _p}) then {
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
                                if (vehicle _x == _x && {!(_x in _currentOperators)}) then { 
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