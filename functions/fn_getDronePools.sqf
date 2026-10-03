// Server-local class pool cache, keyed by side and all settings affecting the pool.
params ["_groupSide"];
private _settings = ["CLDW_Mod_Crocus", "CLDW_Mod_KVN", "CLDW_Mod_UAFPV_Tom", "CLDW_Mod_UAFPV_BIG", "CLDW_Mod_WS_IED", "CLDW_Setting_AllowVanillaFallback"];
private _key = str ([_groupSide] + (_settings apply { missionNamespace getVariable [_x, _x != "CLDW_Setting_AllowVanillaFallback"] }));
if (isNil "CLDW_poolCache") then { CLDW_poolCache = createHashMap; };
private _cached = CLDW_poolCache getOrDefault [_key, []];
if !(_cached isEqualTo []) exitWith { _cached };
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


private _result = [_apBags, _atBags, _sideDrones];
CLDW_poolCache set [_key, _result];
_result
