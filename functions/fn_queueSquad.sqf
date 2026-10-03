params ["_group"];
if (!isServer) exitWith {};
if ((missionNamespace getVariable ["CLDW_Setting_ExcludePlayerGroup", true]) && {{isPlayer _x} count units _group > 0}) exitWith {};
private _maxOps = round (missionNamespace getVariable ["CLDW_Setting_MaxDrones", 2]) max 1 min 10;
private _operators = (units _group) select {alive _x && {!isPlayer _x} && {_x getVariable ["CLDW_SupplyOperator", false]}};
_operators resize ((count _operators) min (_group getVariable ["CLDW_OperatorCeiling", _maxOps]));
{
    private _op = _x;
    if (alive _op && {!isPlayer _op} && {_op getVariable ["CLDW_SupplyOperator", false]}) then {
        if (!(_op getVariable ["CLDW_InventoryReady", false])) then {
            (_op getVariable ["CLDW_InventoryRequest", []]) remoteExecCall ["CLDW_fnc_supplyInventory", _op];
        } else {
            private _active = _op getVariable ["CLDW_ActiveDrone", objNull];
            private _bagOK = !(_op getVariable ["CLDW_PhysicalSupply", false]) || {backpack _op == (_op getVariable ["CLDW_SupplyBag", ""])};
            if ((_op getVariable ["CLDW_Stock", 0]) > 0 && {_bagOK} &&
                {isNull _active || {!alive _active}} && {vehicle _op == _op} &&
                {(getPosATL _op select 2) < 1.8} &&
                {time - (_op getVariable ["CLDW_Last_Drone_Deploy_Time", -9999]) >= 30} &&
                {!(_op getVariable ["CLDW_Drone_Queued", false])}) then {
                private _range = missionNamespace getVariable ["CLDW_Setting_MaxRange", 750];
                private _enemy = _op findNearestEnemy _op;
                if (isNull _enemy) then { _enemy = (leader _group) findNearestEnemy (leader _group); };
                if (behaviour _op in ["COMBAT", "STEALTH"] ||
                    {!isNull _enemy && {_op distance _enemy <= _range}} ||
                    {!((_op targets [true, _range]) isEqualTo [])}) then {
                    _op setVariable ["CLDW_Drone_Queued", true];
                    CLDW_deployQueue pushBack _op;
                };
            };
        };
    };
} forEach _operators;
