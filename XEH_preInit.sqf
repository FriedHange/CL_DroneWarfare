// Inside P:\CL_DroneWarfare\XEH_preInit.sqf

// 0. Master Toggle Switch
[
    "CLDW_Setting_EnableMod", 
    "CHECKBOX",                      
    ["Enable CL Drone Warfare", "If unchecked, the mod's background loop will pause and no new drones will be distributed."], 
    "CL Drone Warfare",              
    true,                            
    1                                
] call CBA_fnc_addSetting;

// 1. Independent Faction Toggle Switch
[
    "CLDW_Setting_AllowIndependent", 
    "CHECKBOX",                      
    ["Allow Independent/Rebels", "If checked, Independent factions (like Antistasi Rebels) will be assigned drone backpacks."], 
    "CL Drone Warfare",              
    false,                            
    1                                
] call CBA_fnc_addSetting;

// 1.1. Blufor Faction Toggle Switch
[
    "CLDW_Setting_AllowBlufor", 
    "CHECKBOX",                      
    ["Allow Blufor", "If checked, Blufor factions will be assigned drone backpacks."], 
    "CL Drone Warfare",              
    true,                            
    1                                
] call CBA_fnc_addSetting;

// 1.2. Opfor Faction Toggle Switch
[
    "CLDW_Setting_AllowOpfor", 
    "CHECKBOX",                      
    ["Allow Opfor", "If checked, Opfor factions will be assigned drone backpacks."], 
    "CL Drone Warfare",              
    true,                            
    1                                
] call CBA_fnc_addSetting;

// 2. Target Tracking Proximity Cap
[
    "CLDW_Setting_MaxRange",
    "SLIDER",
    ["Max Drone Targeting Range", "The maximum distance (in meters) the drone loop will scan for targets."],
    "CL Drone Warfare",
    [200, 3000, 500, 0], // [Min, Max, Default, Decimals]
    1
] call CBA_fnc_addSetting;

// 3. Max Drones Per Squad Slider
[
    "CLDW_Setting_MaxDrones",
    "SLIDER",
    ["Max Drone Operators Per Squad", "The maximum number of AI soldiers allowed to carry drone backpacks in a single group simultaneously."],
    "CL Drone Warfare",
    [1, 10, 2, 0], 
    1
] call CBA_fnc_addSetting;

// 3a. AP Drone Bags Per Squad
[
    "CLDW_Setting_APDroneCount",
    "SLIDER",
    ["AP Drone Bags Per Squad", "How many AP (Anti-Personnel) drone backpacks can be distributed per group. AP drones target infantry. Set to 0 to disable AP drones entirely."],
    "CL Drone Warfare",
    [0, 8, 2, 0],
    1
] call CBA_fnc_addSetting;

// 3b. AT Drone Bags Per Squad
[
    "CLDW_Setting_ATDroneCount",
    "SLIDER",
    ["AT Drone Bags Per Squad", "How many AT (Anti-Tank) drone backpacks can be distributed per group. AT drones target vehicles. Set to 0 to disable AT drones entirely."],
    "CL Drone Warfare",
    [0, 8, 1, 0],
    1
] call CBA_fnc_addSetting;

// 3c. AT Drones Can Target Infantry
[
    "CLDW_Setting_ATTargetsInfantry",
    "CHECKBOX",
    ["AT Drones Can Target Infantry", "If checked, AT drones will also engage infantry when no armoured vehicles are within range. If unchecked, AT drones only engage tanks, APCs and wheeled vehicles."],
    "CL Drone Warfare",
    false,
    1
] call CBA_fnc_addSetting;

// 4. Background Loop Interval Slider
[
    "CLDW_Setting_LoopSpeed",
    "SLIDER",
    ["Loop Refresh Speed (Seconds)", "How often the script scans all map groups to distribute drone backpacks. Lower values react faster but use more CPU."],
    "CL Drone Warfare",
    [2, 30, 10, 0], 
    1
] call CBA_fnc_addSetting;

// 5. Direct Drone Vector Move Toggle Switch
[
    "CLDW_Setting_ForceDirectMove", 
    "CHECKBOX",                      
    ["Force Direct Flight Vector", "If checked, the drone's internal pilot group will be forced to execute a direct move order straight to the 3D target coordinates, completely bypassing native loitering routines."], 
    "CL Drone Warfare",              
    true,                            
    1                                
] call CBA_fnc_addSetting;

// 6. Force Combat Mode on Drone Bag Assignment
[
    "CLDW_Setting_CombatMode",
    "CHECKBOX",
    ["Aggresive Drone Squads", "If true, a group will be set to Combat mode whenever one of its AI soldiers receives a drone backpack. Disabled by default to avoid disrupting existing group AI orders. Turn on for more aggressive FPV Warfare"],
    "CL Drone Warfare",
    false,
    1
] call CBA_fnc_addSetting;

// 7. Minimum Squad Size for Drone Assignment
[
    "CLDW_Setting_MinSquadSize",
    "SLIDER",
    ["Minimum Squad Size", "The minimum number of units required in a group before they can be assigned a drone backpack."],
    "CL Drone Warfare",
    [1, 12, 4, 0], 
    1
] call CBA_fnc_addSetting;

// 8. Replace Existing Backpacks
[
    "CLDW_Setting_ReplaceBackpacks",
    "CHECKBOX",
    ["Replace Existing Backpacks", "If checked, the script will assign drone bags even to AI that already have backpacks (their old backpack will be deleted). If unchecked, only AI with empty back slots get drones."],
    "CL Drone Warfare",
    false,
    1
] call CBA_fnc_addSetting;

// 9. Merge Drone Squad
[
    "CLDW_Setting_MergeDroneGroup",
    "CHECKBOX",
    ["Merge Drone with Assembler's Squad", "If checked, when a drone is assembled, its internal AI crew will be automatically moved into the squad of the soldier who assembled it, allowing them to share target information."],
    "CL Drone Warfare",
    true,
    1
] call CBA_fnc_addSetting;

// 10. Exclude Player Group
[
    "CLDW_Setting_ExcludePlayerGroup",
    "CHECKBOX",
    ["Exclude Player's Squad", "If checked, the player's group/squad will not be automatically assigned drone backpacks."],
    "CL Drone Warfare",
    true,
    1
] call CBA_fnc_addSetting;

// 11. Drone Dive Attack Speed Slider
[
    "CLDW_Setting_DroneSpeed",
    "SLIDER",
    ["Drone Dive Attack Speed (km/h)", "The speed of the drone during the FPV terminal dive/attack phase in km/h."],
    "CL Drone Warfare",
    [50, 270, 125, 0], 
    1
] call CBA_fnc_addSetting;

// 12. Drone Cruising Speed Slider
[
    "CLDW_Setting_CruiseSpeed",
    "SLIDER",
    ["Drone Cruising Speed (km/h)", "The speed of the drone when patrolling, moving, or returning to the squad in km/h."],
    "CL Drone Warfare",
    [30, 180, 85, 0], 
    1
] call CBA_fnc_addSetting;