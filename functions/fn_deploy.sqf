// Called unscheduled from the server queue: cap check and creation cannot interleave.
params ["_operator"];
if (!isServer || {isNull _operator} || {!alive _operator} || {isPlayer _operator}) exitWith {true};
private _groupSide = side group _operator;
private _allowSetting = switch (_groupSide) do {
    case west: {"CLDW_Setting_AllowBlufor"}; case east: {"CLDW_Setting_AllowOpfor"};
    case independent: {"CLDW_Setting_AllowIndependent"}; default {""};
};
if (_allowSetting == "" || {!(missionNamespace getVariable [_allowSetting, false])}) exitWith {true};
if ((missionNamespace getVariable ["CLDW_Setting_ExcludePlayerGroup", true]) && {{isPlayer _x} count units group _operator > 0}) exitWith {true};
if ((_operator getVariable ["CLDW_Stock", 0]) <= 0) exitWith {true};
if (!(missionNamespace getVariable ["CLDW_Setting_EnableMod", true])) exitWith {false};
if (!(_operator getVariable ["CLDW_InventoryReady", false])) exitWith {false};
private _existing = _operator getVariable ["CLDW_ActiveDrone", objNull];
if (!isNull _existing && {alive _existing}) exitWith {true};
if (vehicle _operator != _operator || {(getPosATL _operator select 2) >= 1.8}) exitWith {true};
// Revalidate the roster after group merges or transfers while queued.
private _roster = (units group _operator) select {alive _x && {!isPlayer _x} && {_x getVariable ["CLDW_SupplyOperator", false]}};
private _defaultCeiling = missionNamespace getVariable ["CLDW_Setting_MaxDrones", 2];
private _ceiling = (group _operator) getVariable ["CLDW_OperatorCeiling", round _defaultCeiling];
if ((_roster find _operator) >= _ceiling) exitWith {true};
private _droneBackpack = _operator getVariable ["CLDW_SupplyBag", ""];
if ((_operator getVariable ["CLDW_PhysicalSupply", false]) && {backpack _operator != _droneBackpack}) exitWith {true};
if (time - (_operator getVariable ["CLDW_Last_Drone_Deploy_Time", -9999]) < 30) exitWith {false};
if (time - ((group _operator) getVariable ["CLDW_Group_Last_Launch", -9999]) < (missionNamespace getVariable ["CLDW_Setting_LaunchStagger", 10])) exitWith {false};
if (!([_groupSide] call CLDW_fnc_canLaunch)) exitWith {false};
private _droneClass = getText (configFile >> "CfgVehicles" >> _droneBackpack >> "assembleInfo" >> "assembleTo");
if (_droneClass == "") then {
    _droneClass = _droneBackpack;
    private _bagIndex = _droneBackpack find "_Bag";
    if (_bagIndex != -1) then {
        _droneClass = _droneBackpack select [0, _bagIndex];
    } else {
        private _bpIndex = _droneBackpack find "_backpack_F";
        if (_bpIndex != -1) then {
            _droneClass = (_droneBackpack select [0, _bpIndex]) + "_F";
        };
    };
};

if (isClass (configFile >> "CfgVehicles" >> _droneClass)) then {
    private _spawnPos = getPosATL _operator;
    private _spawnPosFinal = if (missionNamespace getVariable ["CLDW_Setting_SpawnInAir", false]) then {
        [_spawnPos select 0, _spawnPos select 1, 100]
    } else {
        _spawnPos vectorAdd [(sin (getDir _operator)) * 1.5, (cos (getDir _operator)) * 1.5, 1.5]
    };
    private _drone = createVehicle [_droneClass, _spawnPosFinal, [], 0, "FLY"];

    if (!isNull _drone) then {
        // Suppress ACE marking laser checks on turretless FPV drones during spawn
        _drone setVariable ["ace_markinglaser_hasLaser", false];

        diag_log format ["CLDW [Deploy]: '%1' deployed '%2' at %3 (machine %4).", name _operator, _droneClass, mapGridPosition _drone, clientOwner];
        _drone setVariable ["CLDW_AI_Spawned", true, true];
        _drone setVariable ["CLDW_AssignedOperator", _operator, true];
        _drone setVariable ["CLDW_OperatorBound", true, true];
        _drone setVariable ["CLDW_CurrentOperator", _operator, true];
        _drone setVariable ["CLDW_OperatorGroup", group _operator, true];
        _drone setVariable ["CLDW_DroneSide", _groupSide, true];
        _drone setVariable ["ddtOwner", _operator, true];

        // Track in thread-safe active drones list
        CLDW_activeDrones pushBack _drone;

        createVehicleCrew _drone;
        if (!alive driver _drone) exitWith {
            { _drone deleteVehicleCrew _x; } forEach crew _drone;
            deleteVehicle _drone;
        };
        private _remaining = (_operator getVariable ["CLDW_Stock", 0]) - 1;
        _operator setVariable ["CLDW_Stock", _remaining max 0, true];
        _operator setVariable ["CLDW_ActiveDrone", _drone, true];
        _operator setVariable ["CLDW_Last_Drone_Deploy_Time", time, true];
        (group _operator) setVariable ["CLDW_Group_Last_Launch", time];
        private _revision = (_operator getVariable ["CLDW_InventoryRevision", 0]) + 1;
        private _nextBag = if (_remaining > 0) then {_droneBackpack} else {""};
        private _request = [_operator, _revision, _nextBag, _operator getVariable ["CLDW_PhysicalSupply", false], false];
        _operator setVariable ["CLDW_InventoryReady", false, true];
        _operator setVariable ["CLDW_InventoryRevision", _revision, true];
        _operator setVariable ["CLDW_InventoryRequest", _request, true];
        _request remoteExecCall ["CLDW_fnc_supplyInventory", _operator];
        if (isPlayer _operator) then {
            _operator connectTerminalToUAV _drone;
        };

        private _crew = crew _drone;
        {
            _x setVariable ["CLDW_IsDroneCrew", true, true];
            _x setVariable ["CLDW_DroneCrewUsed", true, true];
            _x setVariable ["CLDW_CurrentOperator", _operator, true];
            _x setVariable ["A3A_isIrrelevant", true, true];
            if (_x in switchableUnits) then { removeSwitchableUnit _x; };
        } forEach _crew;

        private _opGrp = group _operator;
        private _separateGrp = createGroup [_groupSide, true];
        _crew joinSilent _separateGrp;
        _separateGrp deleteGroupWhenEmpty true;
        _separateGrp setBehaviour "CARELESS";
        _separateGrp setCombatMode "BLUE";

        // Keep newly created drones on the server. External transfers are handled by owner ticks.
        // Disable collisions with all other active UAVs immediately
        private _otherActive = (+CLDW_activeDrones) select { !isNull _x && {alive _x} };
        {
            if (_x != _drone) then {
                _drone disableCollisionWith _x;
                _x disableCollisionWith _drone;
            };
        } forEach _otherActive;


        [_drone] remoteExecCall ["CLDW_fnc_droneTick", _drone];
    };
} else {
    if !(_operator getVariable ["CLDW_InvalidBagReported", false]) then {
        diag_log format ["CLDW: Invalid drone vehicle '%1' for backpack '%2'; stock retained.", _droneClass, _droneBackpack];
        _operator setVariable ["CLDW_InvalidBagReported", true];
    };
};
true
