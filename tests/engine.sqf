
// Isolated server regression mission; no background distribution loop.
{
    missionNamespace setVariable ["CLDW_fnc_" + _x, compile preprocessFileLineNumbers ("functions\fn_" + _x + ".sqf")];
} forEach ["assignSquad","getDronePools","supplyInventory","canLaunch","deploy",
    "getEWState","registerEWAdapter","initRuntime","startController","guideFlight","isAPDrone","canAttackVehicle",
    "returnFlight","bomberFlight","droneTick","getDroneRole","classifyDroneRole","predictImpactPoint","move","watchdog","rejoinSquad","retireOrphan","retireOrphanCrew","droneGroupAlive","playerPiloting","hasVisualTarget","visibleAimPoint","clearFlightPath","terrainLookahead","findSafeApproach","planAttack","searchFlight"];
private _realDroneTick = CLDW_fnc_droneTick;
CLDW_testFailures = 0;
CLDW_testCount = 0;
private _assert = {
    params ["_condition", "_label"];
    CLDW_testCount = CLDW_testCount + 1;
    if (!_condition) then {CLDW_testFailures = CLDW_testFailures + 1;};
    diag_log format ["CLDW_TEST %1 %2", ["FAIL","PASS"] select _condition, _label];
};
private _makeGroup = {
    params ["_offset"];
    private _g = createGroup [west, true];
    for "_i" from 0 to 5 do {
        private _u = _g createUnit ["B_Soldier_F", [1000 + _offset + _i * 2,1000,0], [], 0, "NONE"];
        _u disableAI "MOVE";
        _u addBackpack "B_AssaultPack_mcamo";
    };
    _g
};
// Vanilla assembly fixture; actual assignment and deployment remain under test.
CLDW_fnc_getDronePools = {[["B_UAV_01_backpack_F"], [], ["B_UAV_01_backpack_F"]]};
CLDW_fnc_droneTick = {}; // Trajectory requires a live scenario.
CLDW_activeDrones = [];
CLDW_Setting_EnableMod = true;
CLDW_Setting_AllowBlufor = true;
CLDW_Setting_AllowOpfor = true;
CLDW_Setting_ExcludePlayerGroup = false;
CLDW_Setting_MinSquadSize = 4;
CLDW_Setting_DroneSpawnChance = 100;
CLDW_Setting_MaxDrones = 2;
CLDW_Setting_MaxSquadStock = 5;
CLDW_Setting_ReplaceBackpacks = false;
CLDW_Setting_GiveAITerminal = false;
CLDW_Setting_LaunchStagger = 0;
CLDW_Setting_MaxActiveGlobal = 12;
CLDW_Setting_MaxActiveWest = 6;
CLDW_Setting_MaxActiveEast = 6;

private _group = [0] call _makeGroup;
private _loadouts = (units _group) apply {getUnitLoadout _x};
[_group] call CLDW_fnc_assignSquad;
sleep 0.5;
private _ops = _group getVariable ["CLDW_SupplyOperators", []];
[count _ops >= 1 && {count _ops <= 2}, "operator roll respects maximum"] call _assert;
private _shares = _ops apply {_x getVariable ["CLDW_Stock", 0]};
[(_shares findIf {_x < 1}) == -1 && {(count _shares) <= 2} &&
    {count _shares >= 1} && {(_shares select 0) <= 5},
    "stock is split among selected operators"] call _assert;
[((units _group) apply {getUnitLoadout _x}) isEqualTo _loadouts, "virtual supply preserves every loadout"] call _assert;
[_group] call CLDW_fnc_assignSquad;
[(_ops apply {_x getVariable ["CLDW_Stock",0]}) isEqualTo _shares, "rescan does not refill stock"] call _assert;
private _op = _ops select 0;
private _stock = _op getVariable ["CLDW_Stock",0];
CLDW_Setting_MaxActiveGlobal = 0;
[!([_op] call CLDW_fnc_deploy), "zero global cap retains queued request"] call _assert;
[(_op getVariable ["CLDW_Stock",0]) == _stock, "capacity rejection retains stock"] call _assert;
CLDW_Setting_MaxActiveGlobal = 12;
CLDW_Setting_MaxActiveWest = 0;
[!([_op] call CLDW_fnc_deploy), "zero side cap rejects launch"] call _assert;
CLDW_Setting_MaxActiveWest = 6;
[[_op] call CLDW_fnc_deploy, "valid launch accepted"] call _assert;
sleep 0.5;
[count CLDW_activeDrones == 1, "exactly one vehicle created"] call _assert;
[(_op getVariable ["CLDW_Stock",0]) == _stock - 1, "launch consumes one drone"] call _assert;
[_op] call CLDW_fnc_deploy;
[count CLDW_activeDrones == 1, "duplicate request cannot launch again"] call _assert;
[backpack _op == "B_AssaultPack_mcamo", "virtual launch preserves original bag"] call _assert;
CLDW_Setting_MaxActiveGlobal = 1;
[!([east] call CLDW_fnc_canLaunch), "global cap blocks another side"] call _assert;
CLDW_Setting_MaxActiveGlobal = 12;
CLDW_Setting_MaxActiveWest = 1;
[!([west] call CLDW_fnc_canLaunch) && {[east] call CLDW_fnc_canLaunch}, "side cap is independent"] call _assert;
CLDW_Setting_MaxActiveWest = 6;

// A zero launch stagger must never override a one-drone faction cap. Also
// reconcile CLDW vehicles that a mission framework omitted from the registry.
CLDW_Setting_LaunchStagger = 0;
CLDW_Setting_MaxActiveGlobal = 4;
CLDW_Setting_MaxActiveWest = 1;
CLDW_Setting_MaxActiveEast = 1;
[!([west] call CLDW_fnc_canLaunch) && {[east] call CLDW_fnc_canLaunch},
    "zero stagger still enforces the NATO one-drone cap"] call _assert;
private _queuedGroup = [170] call _makeGroup;
[_queuedGroup] call CLDW_fnc_assignSquad;
sleep 0.5;
private _queuedOp = (_queuedGroup getVariable ["CLDW_SupplyOperators",[]]) select 0;
private _queuedStock = _queuedOp getVariable ["CLDW_Stock",0];
[!([_queuedOp] call CLDW_fnc_deploy) &&
    {(_queuedOp getVariable ["CLDW_Stock",0]) == _queuedStock} &&
    {{alive _x && {_x getVariable ["CLDW_DroneSide",sideUnknown] == west}} count CLDW_activeDrones == 1},
    "queued NATO deployment cannot exceed one active drone with zero delay"] call _assert;
private _missingRegistry = createVehicle ["B_UAV_01_F",[1200,1200,5],[],0,"FLY"];
_missingRegistry setVariable ["CLDW_AI_Spawned",true];
_missingRegistry setVariable ["CLDW_DroneSide",west];
CLDW_NextCapReconcile = 0;
[!([west] call CLDW_fnc_canLaunch) && {_missingRegistry in CLDW_activeDrones},
    "cap check reconciles an unregistered CLDW drone"] call _assert;
deleteVehicle _missingRegistry;
CLDW_Setting_MaxActiveGlobal = 12;
CLDW_Setting_MaxActiveWest = 6;
CLDW_Setting_MaxActiveEast = 6;

private _physicalGroup = [40] call _makeGroup;
CLDW_Setting_MaxDrones = 1;
CLDW_Setting_MaxSquadStock = 1;
CLDW_Setting_ReplaceBackpacks = true;
[_physicalGroup] call CLDW_fnc_assignSquad;
sleep 0.5;
private _physicalOp = (_physicalGroup getVariable ["CLDW_SupplyOperators", []]) select 0;
[backpack _physicalOp == "B_UAV_01_backpack_F", "physical operator receives drone bag"] call _assert;
[{backpack _x == "B_AssaultPack_mcamo"} count units _physicalGroup == 5, "nonoperators retain their bags"] call _assert;
[_physicalOp] call CLDW_fnc_deploy;
sleep 0.5;
[(_physicalOp getVariable ["CLDW_Stock",-1]) == 0 && {backpack _physicalOp == ""}, "last physical launch exhausts stock and bag"] call _assert;
[_physicalOp,1,"B_UAV_01_backpack_F",true,true] call CLDW_fnc_supplyInventory;
[backpack _physicalOp == "", "stale inventory revision cannot duplicate bag"] call _assert;
[_physicalGroup] call CLDW_fnc_assignSquad;
[(_physicalOp getVariable ["CLDW_Stock",-1]) == 0, "exhausted operator is not replenished"] call _assert;
_physicalOp setDamage 1;
[_physicalGroup] call CLDW_fnc_assignSquad;
[count (_physicalGroup getVariable ["CLDW_SupplyOperators",[]]) == 1, "casualty does not create replacement"] call _assert;
private _moved = createGroup [west,true];
(units _group) joinSilent _moved;
[_moved] call CLDW_fnc_assignSquad;
[isNil {_moved getVariable "CLDW_InitialStock"}, "group transfer cannot mint supplies"] call _assert;
private _failedGroup = [80] call _makeGroup;
CLDW_Setting_DroneSpawnChance = 0;
[_failedGroup] call CLDW_fnc_assignSquad;
CLDW_Setting_DroneSpawnChance = 100;
[_failedGroup] call CLDW_fnc_assignSquad;
[isNil {_failedGroup getVariable "CLDW_InitialStock"}, "failed chance is not rerolled"] call _assert;

// RIS battles retain squads; spent allocations can be reissued after a delay.
CLDW_RISMode = true;
CLDW_Setting_MaxSquadStock = 1;
private _risGroup = [120] call _makeGroup;
[_risGroup] call CLDW_fnc_assignSquad;
sleep 0.5;
private _risOp = (_risGroup getVariable ["CLDW_SupplyOperators", []]) select 0;
private _firstRevision = _risOp getVariable ["CLDW_InventoryRevision", 0];
_risOp setVariable ["CLDW_Stock", 0];
[_risGroup] call CLDW_fnc_assignSquad;
[(_risOp getVariable ["CLDW_Stock", -1]) == 0, "RIS resupply waits for cooldown"] call _assert;
_risGroup setVariable ["CLDW_LastSupplyTime", time - 121];
_risOp setVariable ["CLDW_ActiveDrone", CLDW_activeDrones select 0];
[_risGroup] call CLDW_fnc_assignSquad;
[(_risOp getVariable ["CLDW_Stock", -1]) == 0, "RIS resupply waits for active drone"] call _assert;
_risOp setVariable ["CLDW_ActiveDrone", objNull];
[_risGroup] call CLDW_fnc_assignSquad;
private _risOps = _risGroup getVariable ["CLDW_SupplyOperators", []];
[!(_risOps isEqualTo []) && {((_risOps select 0) getVariable ["CLDW_Stock", 0]) == 1},
    "RIS resupplies an exhausted squad"] call _assert;
[(_risOp getVariable ["CLDW_InventoryRevision", 0]) > _firstRevision ||
    {!(_risOp getVariable ["CLDW_SupplyOperator", false])},
    "RIS reissue advances inventory revision or changes operator"] call _assert;
CLDW_RISMode = false;

// Provider-state fixtures exercise adapters; native EW effects require a live scenario.
CBA_fnc_addPerFrameHandler = {CLDW_testPFH = _this select 0; 0};
CLDW_testEvents = createHashMap;
CBA_fnc_addEventHandler = {params ["_event","_code"]; CLDW_testEvents set [_event,_code]; 0};
DB_fnc_jammerInit = {};
EWDJ_fnc_softJam = {};
EWDJ_cfg = createHashMapFromArray [["affectAI",true],["softReturnHome",true]];
[] call CLDW_fnc_initRuntime;
private _drone = CLDW_activeDrones select 0;
_drone setVariable ["DB_jammer_isUavJamming",true];
_drone setVariable ["CLDW_EWCache",[-1,false]];
[[_drone] call CLDW_fnc_getEWState, "Sania suppression blocks CLDW"] call _assert;
_drone setVariable ["DB_jammer_isUavJamming",false];
_drone setVariable ["EWDJ_jamState","soft"];
_drone setVariable ["CLDW_EWCache",[-1,false]];
[[_drone] call CLDW_fnc_getEWState, "EWDJ soft jam blocks CLDW"] call _assert;
EWDJ_cfg set ["affectAI",false];
_drone setVariable ["CLDW_EWCache",[-1,false]];
[!([_drone] call CLDW_fnc_getEWState), "EWDJ affectAI=false respected"] call _assert;
_drone setVariable ["EWDJ_hardKilled",true];
_drone setVariable ["CLDW_EWCache",[-1,false]];
[[_drone] call CLDW_fnc_getEWState, "hard kill remains blocked"] call _assert;
_drone setVariable ["EWDJ_hardKilled",false];
_drone setVariable ["EWDJ_jamState",""];
EWDJ_cfg set ["affectAI",true];
_drone setVariable ["EWDJ_home",[0,0,0]];
[_drone,"soft"] call (CLDW_testEvents get "EWDJ_droneJammed");
[_drone,""] call (CLDW_testEvents get "EWDJ_droneJammed");
[_drone getVariable ["CLDW_EWReturnPending",false], "release preserves native return home"] call _assert;
_drone setVariable ["CLDW_EWReturnPending",false];
_drone setVariable ["CLDW_EWCache",[-1,false]];
CLDW_fnc_guideFlight = {sleep 30};
[_drone,"GUIDE",[_drone,objNull]] call CLDW_fnc_startController;
private _first = _drone getVariable ["CLDW_Controller",scriptNull];
[!isNull _first, "controller actually starts"] call _assert;
[_drone,"GUIDE",[_drone,objNull]] call CLDW_fnc_startController;
sleep 0.1;
[scriptDone _first, "new controller terminates previous controller"] call _assert;
private _second = _drone getVariable ["CLDW_Controller",scriptNull];
(driver _drone) setDamage 1;
[] call CLDW_testPFH;
sleep 0.1;
[scriptDone _second, "crew death stops scripted flight"] call _assert;

[_drone] call CLDW_fnc_getDroneRole;
_drone setVariable ["CLDW_IsSuicide", true];
[([_drone] call CLDW_fnc_getDroneRole) == "SUICIDE", "role cache responds to suicide override"] call _assert;
_drone setVariable ["CLDW_IsSuicide", false];
_drone setVariable ["ddtExclude", true];
[([_drone] call CLDW_fnc_getDroneRole) == "NONCOMBAT", "role cache responds to exclusion"] call _assert;
private _reverseGroup = [120] call _makeGroup;
CLDW_Setting_MaxDrones = 1;
CLDW_Setting_MaxSquadStock = 1;
[_reverseGroup] call CLDW_fnc_assignSquad;
private _reverseOps = _reverseGroup getVariable ["CLDW_SupplyOperators", []];
private _total = 0;
{_total = _total + (_x getVariable ["CLDW_Stock",0]);} forEach _reverseOps;
[_total >= 1 && {_total <= 10} && {count _reverseOps <= 6} && {count _reverseOps <= _total},
    "maximum-only stock and operator rolls stay within eligible soldiers"] call _assert;
private _before = count CLDW_activeDrones;
_op setVariable ["CLDW_ActiveDrone",objNull];
_op setVariable ["CLDW_Last_Drone_Deploy_Time",-9999];
_op setVariable ["CLDW_SupplyBag","CLDW_Invalid_Test_Backpack"];
_op setVariable ["CLDW_Stock",1];
[_op] call CLDW_fnc_deploy;
[count CLDW_activeDrones == _before && {(_op getVariable ["CLDW_Stock",0]) == 1}, "invalid class retains stock without spawning"] call _assert;
private _mrap = createVehicle ["B_MRAP_01_F", [1400,1400,0], [], 0, "NONE"];
private _aimDrone = createVehicle ["B_UAV_01_F", [1400,1320,5], [], 0, "FLY"];
private _box = boundingBoxReal _mrap;
private _hullCenter = AGLToASL (_mrap modelToWorldVisual (((_box select 0) vectorAdd (_box select 1)) vectorMultiply 0.5));
private _stationaryAim = [_aimDrone,_mrap,55,5,0,8,0] call CLDW_fnc_predictImpactPoint;
[_stationaryAim distance2D _hullCenter < 0.5 && {(_stationaryAim select 2) >= (getTerrainHeightASL _stationaryAim) + 0.8},
    "MRAP guidance aims at hull center with terrain clearance"] call _assert;
_mrap setVelocity [0,27.78,0];
sleep 0.2;
private _movingAim = [_aimDrone,_mrap,55,5,0,8,0] call CLDW_fnc_predictImpactPoint;
[_movingAim select 1 > (_stationaryAim select 1) + 10, "100 km/h MRAP receives forward lead"] call _assert;
private _wheeledAPC = createVehicle ['B_APC_Wheeled_01_cannon_F',[1430,1400,0],[],0,'NONE'];
private _trackedIFV = createVehicle ['B_APC_Tracked_01_rcws_F',[1460,1400,0],[],0,'NONE'];
private _mbt = createVehicle ['B_MBT_01_cannon_F',[1490,1400,0],[],0,'NONE'];
{createVehicleCrew _x} forEach [_wheeledAPC,_trackedIFV,_mbt];
[[_aimDrone,_wheeledAPC,true] call CLDW_fnc_canAttackVehicle,
    'AP payload accepts an occupied wheeled APC'] call _assert;
[[_aimDrone,_trackedIFV,true] call CLDW_fnc_canAttackVehicle,
    'AP payload accepts an occupied tracked IFV'] call _assert;
{_wheeledAPC deleteVehicleCrew _x} forEach crew _wheeledAPC;
[!([_aimDrone,_wheeledAPC,true] call CLDW_fnc_canAttackVehicle),
    'AP payload does not target an empty APC'] call _assert;
[!([_aimDrone,_mbt,true] call CLDW_fnc_canAttackVehicle) &&
    {[_aimDrone,_mbt,false] call CLDW_fnc_canAttackVehicle},
    'main battle tank remains an AT target'] call _assert;
{private _vehicle = _x; {_vehicle deleteVehicleCrew _x} forEach crew _vehicle; deleteVehicle _vehicle}
    forEach [_wheeledAPC,_trackedIFV,_mbt];
deleteVehicle _aimDrone;
private _sightGroup = createGroup [east,true];
private _visibleTarget = _sightGroup createUnit ["O_Soldier_F",[1540,1500,0],[],0,"NONE"];
_visibleTarget disableAI "MOVE";
private _observer = createVehicle ["B_UAV_01_F",[1500,1500,4],[],0,"NONE"];
[_observer,_visibleTarget] call CLDW_fnc_hasVisualTarget;
[[_observer,_visibleTarget] call CLDW_fnc_hasVisualTarget,
    "clear target is visually acquired"] call _assert;
private _clearTargetPoint = [_observer,_visibleTarget] call CLDW_fnc_visibleAimPoint;
[!(_clearTargetPoint isEqualTo []) &&
    {[(getPosASL _observer) vectorAdd [0,0,0.4],_clearTargetPoint,_observer,_visibleTarget,0.25] call CLDW_fnc_clearFlightPath},
    "unobstructed target has a clear flight corridor"] call _assert;
private _clearApproach = [_observer,_clearTargetPoint,_visibleTarget,true] call CLDW_fnc_findSafeApproach;
[(_clearApproach param [1,false]) && {(_clearApproach select 0) distance _clearTargetPoint < 0.1},
    "clear infantry corridor permits a direct final approach"] call _assert;
private _screen = createVehicle ["Land_Cargo_House_V1_F",[1520,1500,0],[],0,"NONE"];
[!([_observer,_visibleTarget] call CLDW_fnc_hasVisualTarget),
    "building hides infantry from drone acquisition"] call _assert;
[!([(getPosASL _observer) vectorAdd [0,0,0.4],_clearTargetPoint,_observer,_visibleTarget,0.25] call CLDW_fnc_clearFlightPath),
    "building blocks a physical flight corridor"] call _assert;
private _coveredApproach = [_observer,_clearTargetPoint,_visibleTarget,false] call CLDW_fnc_findSafeApproach;
[!(_coveredApproach param [1,false]) &&
    {_coveredApproach isEqualTo [] || {((_coveredApproach select 0) select 2) <=
        (getTerrainHeightASL (getPosASLVisual _observer)) + 10}},
    "covered infantry cannot trigger a fast strike or a high pull-up"] call _assert;
deleteVehicle _screen;
sleep 0.3;
[[_observer,_visibleTarget] call CLDW_fnc_hasVisualTarget,
    "soldier emerging from cover is reacquired"] call _assert;
_observer setPosATL [1200,1500,50];
private _highCover = createVehicle ["Land_Cargo_HQ_V1_F",[1530,1500,0],[],0,"NONE"];
[!([_observer,_visibleTarget] call CLDW_fnc_hasVisualTarget),
    "building near infantry blocks a high distant drone"] call _assert;
deleteVehicle _highCover;
deleteVehicle _observer;
deleteVehicle _visibleTarget;
deleteVehicle _mrap;
private _testHouse = createVehicle ["Land_Cargo_House_V1_F",[1700,1500,0],[],0,"NONE"];
private _roomPositions = _testHouse buildingPos -1;
if !(_roomPositions isEqualTo []) then {
    private _roomTarget = _sightGroup createUnit ["O_Soldier_F",_roomPositions select 0,[],0,"NONE"];
    _roomTarget disableAI "MOVE";
    _roomTarget setPosATL (_roomPositions select 0);
    private _testDrone = createVehicle ["B_UAV_01_F",[1725,1500,8],[],0,"NONE"];
    private _entryFound = false;
    private _roomPoint = [];
    private _entryPlan = [];
    for "_bearing" from 0 to 330 step 30 do {
        private _base = getPosASLVisual _roomTarget;
        _testDrone setPosASL [(_base select 0) + (sin _bearing) * 35,
            (_base select 1) + (cos _bearing) * 35,(_base select 2) + 12];
        _roomPoint = [_testDrone,_roomTarget] call CLDW_fnc_visibleAimPoint;
        if !(_roomPoint isEqualTo []) then {
            _entryPlan = [_testDrone,_roomTarget,_roomPoint] call CLDW_fnc_planAttack;
        };
        if !(_entryPlan isEqualTo []) exitWith {_entryFound = true;};
    };
    diag_log format ["CLDW_TEST indoor positions=%1 inside=%2 entryFound=%3 plan=%4",
        count _roomPositions,insideBuilding _roomTarget,_entryFound,_entryPlan];
    [!_entryFound || {(_entryPlan select 3) &&
        {[(getPosASLVisual _testDrone),_entryPlan select 0,_testDrone,objNull,0.8] call CLDW_fnc_clearFlightPath} &&
        {[_entryPlan select 0,_entryPlan select 1,_testDrone,objNull,0.8] call CLDW_fnc_clearFlightPath} &&
        {[_entryPlan select 1,_entryPlan select 2,_testDrone,_roomTarget,0.8] call CLDW_fnc_clearFlightPath}},
        "building entry plan clears every leg for the full drone hull"] call _assert;
    deleteVehicle _testDrone;
    deleteVehicle _roomTarget;
};
deleteVehicle _testHouse;
private _deconClass = "Land_DeconTent_01_white_F";
if (isClass (configFile >> "CfgVehicles" >> _deconClass)) then {
    private _decon = createVehicle [_deconClass,[1760,1500,0],[],0,"NONE"];
    private _deconTarget = _sightGroup createUnit ["O_Soldier_F",[1760,1500,0],[],0,"NONE"];
    _deconTarget disableAI "MOVE";
    _deconTarget setPosATL (getPosATL _decon);
    private _deconObserver = createVehicle ["B_UAV_01_F",[1780,1500,20],[],0,"NONE"];
    private _highVisible = [_deconObserver,_deconTarget] call CLDW_fnc_hasVisualTarget;
    private _deconViews = [];
    for "_bearing" from 0 to 330 step 30 do {
        {
            _deconObserver setPosASL [1760 + (sin _bearing) * 14,
                1500 + (cos _bearing) * 14,(getTerrainHeightASL [1760,1500]) + _x];
            if ([_deconObserver,_deconTarget] call CLDW_fnc_hasVisualTarget) then {
                _deconViews pushBack [_bearing,_x];
            };
        } forEach [3,6,10,20];
    };
    [!_highVisible && {[0,6] in _deconViews} && {[180,6] in _deconViews},
        "decon tent roof hides infantry but low openings expose them"] call _assert;
    _deconObserver setPosASL [1760,1514,(getTerrainHeightASL [1760,1500]) + 6];
    private _deconAim = [_deconObserver,_deconTarget] call CLDW_fnc_visibleAimPoint;
    private _deconPlan = [_deconObserver,_deconTarget,_deconAim] call CLDW_fnc_planAttack;
    [!(_deconPlan isEqualTo []) && {_deconPlan select 3},
        "visible decon tent opening admits a slow entry plan"] call _assert;
    deleteVehicle _deconObserver;
    deleteVehicle _deconTarget;
    deleteVehicle _decon;
};
private _idleDrone = createVehicle ["B_UAV_01_F", [1010,1010,3], [], 0, "FLY"];
createVehicleCrew _idleDrone;
_idleDrone setVariable ["CLDW_CurrentOperator", _op];
_idleDrone setVariable ["CLDW_OperatorGroup", group _op];
_idleDrone setVariable ["CLDW_DroneSide", west];
_idleDrone setVariable ["ddtExclude", true];
[_idleDrone] call _realDroneTick;
[_idleDrone getVariable ["CLDW_LoiterActive",false], "new idle drone receives a loiter order"] call _assert;
[scriptDone (_idleDrone getVariable ['CLDW_IdleHandle',scriptNull]),
    'idle loiter remains under native pilot control'] call _assert;
private _idleWp = _idleDrone getVariable ["CLDW_LoiterWaypoint",[]];
[waypointType _idleWp == "MOVE", "idle drone has a patrol waypoint"] call _assert;
deleteWaypoint _idleWp;
[_idleDrone] call _realDroneTick;
private _repairedWp = _idleDrone getVariable ["CLDW_LoiterWaypoint",[]];
[waypointType _repairedWp == "MOVE", "lost idle waypoint is repaired"] call _assert;
_idleDrone setVariable ['CLDW_AI_Spawned',true];
_idleDrone setVariable ['CLDW_IsSuicide',true];
_idleDrone setVariable ['CLDW_StallState',[getPosASLVisual _idleDrone,diag_tickTime - 13,-1]];
[_idleDrone] call CLDW_fnc_watchdog;
[(_idleDrone getVariable ['CLDW_StallState',[]]) param [3,-1] == 3 &&
    {_idleDrone getVariable ['CLDW_LoiterActive',false]} &&
    {scriptDone (_idleDrone getVariable ['CLDW_IdleHandle',scriptNull])},
    'stalled idle pilot gets a native waypoint retry without scripted flight'] call _assert;
_idleDrone setVariable ['CLDW_AI_Spawned',false];
_idleDrone setVariable ['CLDW_IsSuicide',false];
_idleDrone setVariable ['CLDW_StallState',[]];
_idleDrone setVariable ["ddtExclude",false];
_idleDrone setVariable ["CLDW_RecoveryUntil",time + 10];
_idleDrone setVariable ["CLDW_NextAcquire",0];
CLDW_testScans = 0;
CLDW_fnc_getTargetsAT = {CLDW_testScans = CLDW_testScans + 1; []};
[_idleDrone] call _realDroneTick;
[CLDW_testScans == 0, "temporary recovery keeps target scanning from interrupting pull-up"] call _assert;
_idleDrone setVariable ["CLDW_RecoveryUntil",0];
_idleDrone setVariable ["CLDW_Disengaged",true];
CLDW_fnc_returnFlight = {sleep 20};
[_idleDrone] call _realDroneTick;
private _returnIntent = _idleDrone getVariable ["CLDW_ControlIntent",[]];
[_returnIntent param [0,""] == "RETURN" && {!(_idleDrone getVariable ["CLDW_LoiterActive",true])},
    "unfinished disengagement overrides loiter and target scan"] call _assert;
private _searchWindow = time + 24;
_idleDrone setVariable ["CLDW_SearchWindowUntil",_searchWindow];
[_idleDrone,"SEARCH",[_idleDrone,getPosASLVisual _idleDrone,objNull,_op]] call CLDW_fnc_startController;
sleep 0.2;
[abs ((_idleDrone getVariable ["CLDW_SearchUntil",0]) - _searchWindow) < 0.1,
    "search restart keeps its original one-minute deadline"] call _assert;
[_idleDrone,"RETURN",[_idleDrone,getPosASLVisual _idleDrone,_op]] call CLDW_fnc_startController;
[_idleDrone getVariable ["CLDW_SearchWindowUntil",-1] == 0,
    "return clears the search window for a future engagement"] call _assert;
terminate (_idleDrone getVariable ["CLDW_Controller",scriptNull]);
{_idleDrone deleteVehicleCrew _x} forEach crew _idleDrone;
deleteVehicle _idleDrone;
waitUntil {sleep 0.1; diag_tickTime > 18};
private _liveBefore = {(!isNull _x) && {alive _x} && {_x getVariable ["CLDW_AI_Spawned",false]}} count CLDW_activeDrones;
private _stuckDrone = createVehicle ["B_UAV_01_F",[1080,1080,5],[],0,"FLY"];
createVehicleCrew _stuckDrone;
_stuckDrone setVariable ["CLDW_AI_Spawned",true];
_stuckDrone setVariable ["CLDW_IsSuicide",true];
_stuckDrone setVariable ["CLDW_DroneSide",west];
_stuckDrone setVariable ["CLDW_CurrentOperator",_op];
_op setVariable ["CLDW_ActiveDrone",_stuckDrone];
CLDW_activeDrones pushBack _stuckDrone;
CLDW_Setting_MaxActiveGlobal = _liveBefore + 1;
[!([west] call CLDW_fnc_canLaunch), "stalled drone initially occupies global cap"] call _assert;
_stuckDrone setVariable ["CLDW_StallState",[getPosASLVisual _stuckDrone,diag_tickTime - 13,-1]];
[_stuckDrone] call CLDW_fnc_watchdog;
[!isNull _stuckDrone && {_stuckDrone getVariable ["CLDW_Disengaged",false]},
    "watchdog tries return recovery before crew repair"] call _assert;
_stuckDrone setPosATL ((getPosATL _stuckDrone) vectorAdd [12,0,0]);
[_stuckDrone] call CLDW_fnc_watchdog;
[!isNull _stuckDrone && {(_stuckDrone getVariable ["CLDW_StallState",[]]) param [2,0] < 0},
    "real movement cancels stall recovery"] call _assert;
_stuckDrone setVariable ["CLDW_StallState",[getPosASLVisual _stuckDrone,diag_tickTime - 30,diag_tickTime - 16,0]];
private _repairPos = getPosASLVisual _stuckDrone;
private _repairPilot = driver _stuckDrone;
[_stuckDrone] call CLDW_fnc_watchdog;
[!isNull _stuckDrone && {alive _stuckDrone} && {!([west] call CLDW_fnc_canLaunch)},
    "unrecovered drone is repaired without consuming or freeing its cap slot"] call _assert;
[driver _stuckDrone != _repairPilot && {(getPosASLVisual _stuckDrone) distance _repairPos < 1},
    "watchdog replaces pilot without teleporting the hull"] call _assert;
_stuckDrone setVariable ["CLDW_StallState",[getPosASLVisual _stuckDrone,diag_tickTime - 10,diag_tickTime - 9,1]];
private _rejoinPos = getPosASLVisual _stuckDrone;
[_stuckDrone] call CLDW_fnc_watchdog;
[group (driver _stuckDrone) == group _op &&
    {_stuckDrone getVariable ["CLDW_RecoveryJoined",false]} &&
    {(getPosASLVisual _stuckDrone) distance _rejoinPos < 1},
    "persistent stall joins operator squad without moving the hull"] call _assert;
[_stuckDrone,true] call CLDW_fnc_rejoinSquad;
[group (driver _stuckDrone) != group _op &&
    {!(_stuckDrone getVariable ["CLDW_RecoveryJoined",true])},
    "recovered pilot detaches to a separate UAV group"] call _assert;
[_op getVariable ["CLDW_ActiveDrone",objNull] == _stuckDrone,
    "repair preserves the operator's active drone"] call _assert;
private _oldPilot = driver _stuckDrone;
_oldPilot setDamage 1;
_stuckDrone setVariable ["CLDW_PilotLostAt",diag_tickTime - 6];
[_stuckDrone] call CLDW_fnc_watchdog;
[alive driver _stuckDrone && {driver _stuckDrone != _oldPilot},
    "lost AI pilot is replaced without deleting drone"] call _assert;
{_stuckDrone deleteVehicleCrew _x} forEach crew _stuckDrone;
deleteVehicle _stuckDrone;
private _flatFrom = [1500,1500,(getTerrainHeightASL [1500,1500]) + 5];
private _flatTo = [1580,1500,(getTerrainHeightASL [1580,1500]) + 5];
private _flatRidge = [_flatFrom,_flatTo,15,3] call CLDW_fnc_terrainLookahead;
[_flatRidge select 0 <= (_flatFrom select 2) && {(_flatRidge select 1) > 0},
    "terrain lookahead leaves a clear flat approach alone"] call _assert;
private _lostOp = (group _op) createUnit ["B_Soldier_F",[1120,1120,0],[],0,"NONE"];
private _orphan = createVehicle ["B_UAV_01_F",[1130,1120,20],[],0,"FLY"];
createVehicleCrew _orphan;
_orphan setVariable ["CLDW_AI_Spawned",true];
_orphan setVariable ["CLDW_OperatorBound",true];
_orphan setVariable ["CLDW_AssignedOperator",_lostOp];
_orphan setVariable ["CLDW_CurrentOperator",_op];
_orphan setVariable ["CLDW_DroneSide",west];
CLDW_activeDrones pushBack _orphan;
deleteVehicle _lostOp;
sleep 0.2;
diag_log format ["CLDW_TEST orphan fixture assignedNull=%1 assignedAlive=%2 bound=%3",
    isNull (_orphan getVariable ["CLDW_AssignedOperator",objNull]),
    alive (_orphan getVariable ["CLDW_AssignedOperator",objNull]),
    _orphan getVariable ["CLDW_OperatorBound",false]];
[!([_orphan,objNull] call CLDW_fnc_droneGroupAlive),
    "despawned assigned operator cannot be replaced by another squad member"] call _assert;
_orphan setVariable ["CLDW_Orphaned",true];
CLDW_Setting_MaxActiveGlobal = ({alive _x && {!(_x getVariable ["CLDW_Orphaned",false])}} count CLDW_activeDrones) + 1;
[[west] call CLDW_fnc_canLaunch,
    "retired hull releases an active cap slot without refunding stock"] call _assert;
[_orphan] call CLDW_fnc_retireOrphan;
[(_orphan getVariable ["CLDW_OrphanFinalized",false]),
    "retirement only finalizes after local AI crew is dead"] call _assert;
[alive _orphan && {!alive driver _orphan} && {_orphan getVariable ["CLDW_OrphanFinalized",false]},
    "retirement kills AI crew and leaves hull in place"] call _assert;
[_orphan] call CLDW_fnc_watchdog;
[!alive driver _orphan,"watchdog never revives retired drone crew"] call _assert;
{_orphan deleteVehicleCrew _x} forEach crew _orphan;
deleteVehicle _orphan;
diag_log format ["CLDW_TEST DONE tests=%1 failures=%2",CLDW_testCount,CLDW_testFailures];
