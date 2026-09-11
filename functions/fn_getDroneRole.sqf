/*
    File: fn_getDroneRole.sqf
    Author: Carl Lorenzo
    Description:
        Categorizes a UAV into its operational combat role:
        - "SUICIDE": FPV strike/kamikaze drones that impact and detonate on target (Crocus, KVN, UAFPV, RC-40 HE, Switchblade).
        - "DROPPER": Munition/grenade/bomb dropping drones that loiter at altitude and drop ordnance (Western Sahara IED drones, Mavic droppers, Drongo's DRA_UAV_01G, Baba Yaga, etc.).
        - "NONCOMBAT": Unarmed reconnaissance, surveillance, utility, medical, cargo, demining, and transport drones (AL-6 Pelican, AR-2 Darter, Black Hornet, Mavic Recon, etc.).
    Parameters:
        0: OBJECT or STRING - Drone object or vehicle classname
    Returns:
        STRING - "SUICIDE", "DROPPER", or "NONCOMBAT"
*/

params [["_input", objNull]];

if (_input isEqualType objNull && {isNull _input}) exitWith { "NONCOMBAT" };
if (_input isEqualType "" && {_input == ""}) exitWith { "NONCOMBAT" };

private _droneObj = if (_input isEqualType objNull) then { _input } else { objNull };
private _type = if (!isNull _droneObj) then { typeOf _droneObj } else { _input };
private _lowerType = toLower _type;

// 1. Explicit variable override on the drone object
private _override = "";
if (!isNull _droneObj) then {
    private _roleVar = _droneObj getVariable ["CLDW_DroneRole", ""];
    if (_roleVar != "") exitWith { _override = toUpper _roleVar; };
    if (_droneObj getVariable ["CLDW_IsNonCombat", false]) exitWith { _override = "NONCOMBAT"; };
    if (_droneObj getVariable ["CLDW_IsDropper", false]) exitWith { _override = "DROPPER"; };
    if (_droneObj getVariable ["CLDW_IsSuicide", false]) exitWith { _override = "SUICIDE"; };
    if (_droneObj getVariable ["ddtExclude", false]) exitWith { _override = "NONCOMBAT"; };
};
if (_override != "") exitWith { _override };

// 2. Check for Non-Combat Drone patterns (AL-6 Pelican, AR-2 Darter, Recon, Medical, Cargo)
// Must be evaluated first to ensure utility/recon variants of multirotor frames are never weaponized
private _isNonCombat = 
    // AL-6 Pelican / Jinaah (Laws of War utility / medical / cargo / demining)
    ((_lowerType find "uav_06" > -1 || 
     {_lowerType find "uas_06" > -1} || 
     {_lowerType find "al6" > -1} || 
     {_lowerType find "al-6" > -1} || 
     {_lowerType find "pelican" > -1} || 
     {_lowerType find "jinaah" > -1}) && {!(_lowerType find "antimine" > -1)}) ||
    // AR-2 Darter / Tayran (unarmed surveillance quadcopters)
    ((_lowerType find "uav_01" > -1 || {_lowerType find "darter" > -1} || {_lowerType find "tayran" > -1}) && {!(_lowerType find "dra_uav_01g" > -1)}) ||
    // Micro surveillance & recon
    {_lowerType find "blackhornet" > -1} || 
    {_lowerType find "black_hornet" > -1} || 
    {_lowerType find "sps_black_hornet" > -1} ||
    {_lowerType find "mavic_3t" > -1} || 
    {_lowerType find "mavik_3t" > -1} ||
    {_lowerType find "sensor" > -1} || 
    {_lowerType find "smoke" > -1} ||
    // Utility, medical, cargo, transport, logistics, civilian IDAP
    {_lowerType find "medical" > -1} || 
    {_lowerType find "antidote" > -1} || 
    {_lowerType find "cargo" > -1} || 
    {_lowerType find "utility" > -1} || 
    {_lowerType find "logistics" > -1} || 
    {_lowerType find "transport" > -1} ||
    ((_lowerType find "idap" > -1) && {!(_lowerType find "antimine" > -1)}) ||
    ((_lowerType find "recon" > -1) && {!(_lowerType find "rc40_he" > -1)});

if (_isNonCombat) exitWith { "NONCOMBAT" };

// 3. Check for Dropper / Bomber Drone patterns (munitions released from altitude)
private _isDropper = 
    // Western Sahara IED drones (Tura / Raider bomber)
    (_lowerType find "uav_02_ied" > -1) || 
    {_lowerType find "tura_uav" > -1} || 
    {_lowerType find "uav_02" > -1} ||
    // Drongo's Artillery 40mm grenade dropper
    {_lowerType find "dra_uav_01g" > -1} ||
    // Mavic grenade droppers (BLU/OPF/IND carrying VOG-17 / cup)
    {_lowerType find "mavic_3" > -1} || 
    {_lowerType find "mavik_3" > -1} ||
    // IDAP antimine explosive dropper
    {_lowerType find "antimine" > -1} ||
    // Heavy multirotor bombers & drone droppers
    {_lowerType find "dropper" > -1} || 
    {_lowerType find "bomber" > -1} || 
    {_lowerType find "baba_yaga" > -1} || 
    {_lowerType find "babayaga" > -1} || 
    {_lowerType find "r18" > -1} || 
    {_lowerType find "r-18" > -1} || 
    {_lowerType find "vampire" > -1} ||
    {_lowerType find "grenade" > -1 && {!(_lowerType find "rc40_he" > -1)}} ||
    {_lowerType find "mortar" > -1} ||
    {_lowerType find "_ied" > -1} ||
    // DDT Bomber class list if available
    {_type in (missionNamespace getVariable ["ddtClassesBomber", []])};

if (_isDropper) exitWith { "DROPPER" };

// 4. Check for FPV / Suicide / Kamikaze Drone patterns (physical impact detonation)
private _isSuicide = 
    (_lowerType find "crocus" > -1) || 
    {_lowerType find "kvn" > -1} || 
    {_lowerType find "uafpv" > -1} || 
    {_lowerType find "rc40_he" > -1} || 
    {_lowerType find "rc-40_he" > -1} || 
    {_lowerType find "switchblade" > -1} ||
    {_lowerType find "fpv" > -1} ||
    {_lowerType find "kamikaze" > -1} ||
    {_lowerType find "strike" > -1} ||
    {_type in ((missionNamespace getVariable ["ddtClassesFPV", []]) + (missionNamespace getVariable ["ddtClassesFPVAT", []]))};

if (_isSuicide) exitWith { "SUICIDE" };

// 5. Default fallback for unrecognized UAV types: treat as NONCOMBAT for safety
// Prevents generic UAVs (Greyhawk, Ababil, civilian drones, mod quadcopters) from kamikaze diving
"NONCOMBAT"
