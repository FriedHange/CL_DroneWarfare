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

// 2. Target Tracking Proximity Cap
[
    "CLDW_Setting_MaxRange",
    "SLIDER",
    ["Max Drone Targeting Range", "The maximum distance (in meters) the drone loop will scan for targets."],
    "CL Drone Warfare",
    [200, 2500, 600, 0], // [Min, Max, Default, Decimals]
    1
] call CBA_fnc_addSetting;

// 3. Max Drones Per Squad Slider
[
    "CLDW_Setting_MaxDrones",
    "SLIDER",
    ["Max Drone Operators Per Squad", "The maximum number of AI soldiers allowed to carry drone backpacks in a single group simultaneously."],
    "CL Drone Warfare",
    [1, 5, 3, 0], 
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