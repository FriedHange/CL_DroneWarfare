// Ordinary missions get finite supply. RIS reissues supply to surviving squads
// after a pause, since its battle can reuse the same groups indefinitely.
params ["_group"];
if (!isServer || {isNull _group}) exitWith {};
if (_group getVariable ["CLDW_SupplyRolled", false]) then {
    if (!(missionNamespace getVariable ["CLDW_RISMode", false]) ||
        {time - (_group getVariable ["CLDW_LastSupplyTime", 0]) < 120}) exitWith {};
    private _oldOps = (units _group) select {alive _x && {_x getVariable ["CLDW_SupplyOperator", false]}};
    if ((_oldOps findIf {
        (_x getVariable ["CLDW_Stock", 0]) > 0 ||
        {private _active = _x getVariable ["CLDW_ActiveDrone", objNull]; !isNull _active && {alive _active}}
    }) >= 0) exitWith {};
    {
        _x setVariable ["CLDW_SupplyOperator", false, true];
        _x setVariable ["CLDW_SupplySeen", false, true];
    } forEach units _group;
    _group setVariable ["CLDW_SupplyRolled", false, true];
    diag_log format ["CLDW [RIS]: Reissuing drone supply to surviving %1 squad after exhaustion.", side _group];
};
if (_group getVariable ["CLDW_SupplyRolled", false]) exitWith {};
private _members = units _group;
if (count _members < round (missionNamespace getVariable ["CLDW_Setting_MinSquadSize", 4])) exitWith {};
if ((missionNamespace getVariable ["CLDW_Setting_ExcludePlayerGroup", true]) && {{isPlayer _x} count _members > 0}) exitWith {};
private _eligible = _members select {
    alive _x && {!isPlayer _x} && {vehicle _x == _x} &&
    {(getPosATL _x select 2) < 1.8} && {!(_x getVariable ["CLDW_SupplySeen", false])} &&
    {!(_x getVariable ["CLDW_IsDroneCrew", false])}
};
if (_eligible isEqualTo []) exitWith {};
private _pools = [side _group] call CLDW_fnc_getDronePools;
_pools params ["_ap", "_at", "_all"];
if (_all isEqualTo []) exitWith {};
_group setVariable ["CLDW_SupplyRolled", true, true];
_group setVariable ["CLDW_LastSupplyTime", time];
{ _x setVariable ["CLDW_SupplySeen", true, true]; } forEach _members;
if (random 100 >= (missionNamespace getVariable ["CLDW_Setting_DroneSpawnChance", 30])) exitWith {};
private _maxStock = round (missionNamespace getVariable ["CLDW_Setting_MaxSquadStock", 4]) max 1 min 10;
private _stock = 1 + floor random _maxStock;
private _maxOps = round (missionNamespace getVariable ["CLDW_Setting_MaxDrones", 2]) max 1 min 10;
private _count = (1 + floor random _maxOps) min count _eligible min _stock;
_group setVariable ["CLDW_OperatorCeiling", _maxOps, true];
private _replace = missionNamespace getVariable ["CLDW_Setting_ReplaceBackpacks", false];
private _operators = [];
for "_i" from 0 to (_count - 1) do {
    private _op = _eligible deleteAt floor random count _eligible;
    private _share = floor (_stock / _count) + ([0, 1] select (_i < (_stock mod _count)));
    private _pool = if (random 100 < (missionNamespace getVariable ["CLDW_Setting_APRatio", 80])) then { _ap } else { _at };
    if (_pool isEqualTo []) then { _pool = _all; };
    private _bag = selectRandom _pool;
    _op setVariable ["CLDW_SupplyOperator", true, true];
    _op setVariable ["CLDW_Stock", _share, true];
    _op setVariable ["CLDW_SupplyBag", _bag, true];
    _op setVariable ["CLDW_PhysicalSupply", _replace, true];
    _op setVariable ["CLDW_InventoryReady", false, true];
    private _revision = (_op getVariable ["CLDW_InventoryRevision", 0]) + 1;
    _op setVariable ["CLDW_InventoryRevision", _revision, true];
    _op setVariable ["CLDW_InventoryRequest", [_op, _revision, _bag, _replace, true], true];
    [_op, _revision, _bag, _replace, true] remoteExecCall ["CLDW_fnc_supplyInventory", _op];
    _operators pushBack _op;
};
_group setVariable ["CLDW_SupplyOperators", _operators, true];
_group setVariable ["CLDW_InitialStock", _stock, true];
