[] spawn { 
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
                if (_groupSide == blufor && {!CLDW_Setting_AllowBlufor}) then {
                    continue; 
                };
                if (_groupSide == opfor && {!CLDW_Setting_AllowOpfor}) then {
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
                            case blufor: { ["B_Crocus_AP_Bag", "B_Crocus_AT_Bag", "B_KVN_AP_Bag", "B_KVN_AT_Bag", "B_UAFPV_IED_AP_Bag", "B_UAFPV_OG7V_AP_Bag", "B_UAFPV_RKG_AP_Bag", "B_UAFPV_PG7VL_AT_Bag"] }; 
                            case opfor:  { ["O_Crocus_AP_Bag", "O_Crocus_AT_Bag", "O_KVN_AP_Bag", "O_KVN_AT_Bag", "O_UAFPV_IED_AP_Bag", "O_UAFPV_OG7V_AP_Bag", "O_UAFPV_RKG_AP_Bag", "O_UAFPV_PG7VL_AT_Bag"] }; 
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
                                                            _crew joinSilent _grp;
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
        };
 
        // CBA CHECK: Read sleep interval directly from menu slider dynamically
        if (_isFirstRun) then { _isFirstRun = false; sleep 1; } else { sleep CLDW_Setting_LoopSpeed; }; 
    }; 
};