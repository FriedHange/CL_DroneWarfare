// Inside P:\CL_DroneWarfare\XEH_preInit.sqf

// =====================================
// GENERAL SETTINGS
// =====================================
[
	"CLDW_Setting_EnableMod",
	"CHECKBOX",
	["Enable CL Drone Warfare", "If unchecked, the mod's background loop will pause and no new drones will be distributed."],
	["CL Drone Warfare", "General Settings"],
	true,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_ExcludePlayerGroup",
	"CHECKBOX",
	["Exclude Player's Squad", "If checked, the player's group/squad will not be automatically assigned drone backpacks."],
	["CL Drone Warfare", "General Settings"],
	true,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_GiveAITerminal",
	"CHECKBOX",
	["Give AI UAV Terminal", "If checked, AI soldiers assigned with drone backpacks will also receive the corresponding UAV Terminal, allowing players to loot and use it."],
	["CL Drone Warfare", "General Settings"],
	true,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_SpawnInAir",
	"CHECKBOX",
	["High Altitude Takeoff", "If checked, drones deployed by AI will spawn 100m in the air directly above the operator instead of at ground level, completely bypassing ground collision shenanigans of ArmA 3 causing drones to explode."],
	["CL Drone Warfare", "General Settings"],
	false,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_LoopSpeed",
	"SLIDER",
	["Loop Refresh Speed (Seconds)", "How often the script scans all map groups to distribute drone backpacks. Lower values react faster but use more CPU."],
	["CL Drone Warfare", "General Settings"],
	[2, 30, 10, 0],
	1
] call CBA_fnc_addSetting;

// =====================================
// FACTIONS & LIMITS
// =====================================
[
	"CLDW_Setting_AllowIndependent",
	"CHECKBOX",
	["Allow Independent/Rebels", "If checked, Independent factions (like Antistasi Rebels) will be assigned drone backpacks."],
	["CL Drone Warfare", "Factions & Limits"],
	false,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_AllowBlufor",
	"CHECKBOX",
	["Allow Blufor", "If checked, Blufor factions will be assigned drone backpacks."],
	["CL Drone Warfare", "Factions & Limits"],
	true,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_AllowOpfor",
	"CHECKBOX",
	["Allow Opfor", "If checked, Opfor factions will be assigned drone backpacks."],
	["CL Drone Warfare", "Factions & Limits"],
	true,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_MinSquadSize",
	"SLIDER",
	["Minimum Squad Size", "The minimum number of units required in a group before they can be assigned a drone backpack."],
	["CL Drone Warfare", "Factions & Limits"],
	[1, 12, 4, 0],
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_ReplaceBackpacks",
	"CHECKBOX",
	["Replace Existing Backpacks", "If checked, the script will assign drone bags even to AI that already have backpacks (their old backpack will be deleted). If unchecked, only AI with empty back slots get drones."],
	["CL Drone Warfare", "Factions & Limits"],
	false,
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_AllowVanillaFallback",
	"CHECKBOX",
	["Allow Vanilla Fallback UAVs", "If checked, AI squads will be assigned vanilla UAV backpacks (AR-2 Darter / AL-6) when no supported backpack drone mods are loaded. If unchecked, fallback UAV backpacks will not be distributed."],
	["CL Drone Warfare", "Factions & Limits"],
	false,
	1
] call CBA_fnc_addSetting;

// =====================================
// DRONE QUOTAS
// =====================================
[
	"CLDW_Setting_MaxDrones",
	"SLIDER",
	["Max Drone Operators Per Squad", "The maximum number of AI soldiers allowed to carry drone backpacks in a single group simultaneously."],
	["CL Drone Warfare", "Drone Quotas"],
	[1, 10, 2, 0],
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_APRatio",
	"SLIDER",
	["Drone Ratio", "Percentage of anti-personnel (AP) drones distributed to AI squads. The remaining percentage will be anti-tank (AT) drones."],
	["CL Drone Warfare", "Drone Quotas"],
	[0, 100, 80, 0],
	1
] call CBA_fnc_addSetting;


[
	"CLDW_Setting_DroneSpawnChance",
	"SLIDER",
	["Drone Spawn Chance (%)", "The probability of an eligible squad receiving and deploying a drone (0% = disabled, 100% = guaranteed)."],
	["CL Drone Warfare", "Drone Quotas"],
	[0, 100, 30, 0],
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_ATTargetsInfantry",
	"CHECKBOX",
	["AT Drones Can Target Infantry", "If checked, AT drones will also engage infantry when no armoured vehicles are within range. If unchecked, AT drones only engage tanks, APCs and wheeled vehicles."],
	["CL Drone Warfare", "Drone Quotas"],
	false,
	1
] call CBA_fnc_addSetting;

// =====================================
// FLIGHT PROFILE
// =====================================
[
	"CLDW_Setting_MaxRange",
	"SLIDER",
	["Max Drone Targeting Range (m)", "The maximum distance (in meters) the drone will scan and acquire targets."],
	["CL Drone Warfare", "Flight Profile"],
	[150, 5000, 2000, 0],
	1
] call CBA_fnc_addSetting;

[
	"CLDW_Setting_DroneSpeed",
	"SLIDER",
	["Drone Flight Speed (km/h)", "The top speed of the drone in km/h."],
	["CL Drone Warfare", "Flight Profile"],
	[40, 250, 150, 0],
	1
] call CBA_fnc_addSetting;

// =====================================
// DEPLOYMENT BEHAVIOUR
// =====================================
// [
// 	"CLDW_Setting_AIDeployImmediately",
// 	"LIST",
// 	["AI Immediate Deploy Mode", "Controls when AI operators immediately deploy their drone upon receiving it. Never = deploy on combat entry only. Auto = deploy immediately when RIS/Antistasi is detected. Always = always deploy immediately."],
// 	["CL Drone Warfare", "Deployment Behaviour"],
// 	[[0, 1, 2], ["Never", "Auto (RIS)", "Always"], 1],
// 	1
// ] call CBA_fnc_addSetting;

// =====================================
// SUPPORTED MODS
// =====================================
// Each toggle enables/disables AI backpack distribution for that drone mod.
// Drones from disabled mods will not be given to AI squads.

// Crocus FPV (DarkBall) — AP and AT variants
if (isClass (configFile >> "CfgVehicles" >> "B_Crocus_AP_Bag") || {
	isClass (configFile >> "CfgVehicles" >> "B_Crocus_AP_F")
}) then {
	[
		"CLDW_Mod_Crocus",
		"CHECKBOX",
		["Mod: FPV Drone Crocus", "If checked, Crocus AP and AT backpacks will be distributed to AI squads."],
		"CL Drone Warfare - Supported Mods",
		true,
		1
	] call CBA_fnc_addSetting;
};

// KVN Fibre-Optic FPV (DarkBall) — AP and AT variants
if (isClass (configFile >> "CfgVehicles" >> "B_KVN_AP_Bag") || {
	isClass (configFile >> "CfgVehicles" >> "B_KVN_AP_F")
}) then {
	[
		"CLDW_Mod_KVN",
		"CHECKBOX",
		["Mod: KVN Fibre-Optic FPV", "If checked, KVN AP and AT backpacks will be distributed to AI squads."],
		"CL Drone Warfare - Supported Mods",
		true,
		1
	] call CBA_fnc_addSetting;
};

// Ukraine FPV Drone (Tom) — RKG/OG7V/IED AP + PG7VL AT
if (isClass (configFile >> "CfgVehicles" >> "B_UAFPV_IED_AP_Bag") || {
	isClass (configFile >> "CfgVehicles" >> "B_UAFPV_IED_AP")
}) then {
	[
		"CLDW_Mod_UAFPV_Tom",
		"CHECKBOX",
		["Mod: Ukraine FPV Drone", "If checked, Ukraine FPV AP and AT backpacks (by Tom) will be distributed to AI squads."],
		"CL Drone Warfare - Supported Mods",
		true,
		1
	] call CBA_fnc_addSetting;
};

// Ukraine FPV Edited (BIG GUY) — RKG_Bag/AP_Bag AP + AT_Bag/AT_TI_Bag AT
if (isClass (configFile >> "CfgVehicles" >> "B_UAFPV_AP_Bag")) then {
	[
		"CLDW_Mod_UAFPV_BIG",
		"CHECKBOX",
		["Mod: Ukraine FPV Edited", "If checked, BIG GUY's edited Ukraine FPV AP and AT backpacks will be distributed to AI squads."],
		"CL Drone Warfare - Supported Mods",
		true,
		1
	] call CBA_fnc_addSetting;
};

// Western Sahara IED UAV (bomber — targets vehicles, placed in AT quota)
if (isClass (configFile >> "CfgVehicles" >> "B_Tura_UAV_02_IED_backpack_lxWS") || {
	isClass (configFile >> "CfgVehicles" >> "B_ION_UAV_02_IED_backpack_lxWS")
}) then {
	[
		"CLDW_Mod_WS_IED",
		"CHECKBOX",
		["Mod: Western Sahara IED UAV (Bomber)", "If checked, Western Sahara IED UAV backpacks will be distributed to AI squads (counts against AT quota)."],
		"CL Drone Warfare - Supported Mods",
		true,
		1
	] call CBA_fnc_addSetting;
};

// Reaction Forces RC-40 drone ammunition spawn chances
if (isClass (configFile >> "CfgMagazines" >> "1Rnd_RC40_HE_shell_RF")) then {
	[
		"CLDW_Setting_RC40_Count",
		"SLIDER",
		["RC-40 Drone Ammo Count", "The number of RC-40 drone magazines to add to an eligible AI unit when the spawn chance succeeds."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[1, 10, 2, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_HE",
		"SLIDER",
		["RC-40 HE Drone Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 HE drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 10, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_Recon",
		"SLIDER",
		["RC-40 Recon Drone Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 Recon drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 10, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_SmokeBlue",
		"SLIDER",
		["RC-40 Smoke (Blue) Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 Blue smoke drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 5, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_SmokeGreen",
		"SLIDER",
		["RC-40 Smoke (Green) Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 Green smoke drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 5, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_SmokeOrange",
		"SLIDER",
		["RC-40 Smoke (Orange) Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 Orange smoke drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 5, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_SmokeRed",
		"SLIDER",
		["RC-40 Smoke (Red) Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 Red smoke drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 5, 0],
		1
	] call CBA_fnc_addSetting;

	[
		"CLDW_Setting_RC40_SmokeWhite",
		"SLIDER",
		["RC-40 Smoke (White) Spawn Chance (%)", "Chance for an AI unit with an underbarrel grenade launcher to receive an RC-40 White smoke drone shell."],
		["CL Drone Warfare - Supported Mods", "RC-40 Ammo"],
		[0, 100, 5, 0],
		1
	] call CBA_fnc_addSetting;
};
