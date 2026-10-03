// Only the server can request inventory changes. Revision makes retries idempotent.
params ["_op", "_revision", "_bag", "_physical", "_initial"];
if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {};
if (isNull _op || {!local _op} || {!alive _op} || {isPlayer _op}) exitWith {};
if (_revision != (_op getVariable ["CLDW_InventoryRevision", -1])) exitWith {};
if (_revision <= (_op getVariable ["CLDW_InventoryApplied", 0])) exitWith {
    _op setVariable ["CLDW_InventoryReady", true, true];
};
if (_physical) then {
    // Initial assignment is authorized to replace the bag. Later operations touch only our bag.
    private _oldBag = _op getVariable ["CLDW_SupplyBag", ""];
    if (_initial || {backpack _op == _oldBag}) then {
        removeBackpack _op;
        if (_bag != "") then { _op addBackpack _bag; };
    };
};
if (missionNamespace getVariable ["CLDW_Setting_GiveAITerminal", true]) then {
    private _terminal = switch (side group _op) do {
        case west: {"B_UavTerminal"}; case east: {"O_UavTerminal"}; default {"I_UavTerminal"};
    };
    if !(_terminal in assignedItems _op) then { _op linkItem _terminal; };
};
_op setVariable ["CLDW_InventoryApplied", _revision, true];
_op setVariable ["CLDW_InventoryReady", true, true];
