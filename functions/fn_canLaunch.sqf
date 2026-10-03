params ["_side"];
if (!isServer) exitWith { false };
if (isNil "CLDW_activeDrones") then {CLDW_activeDrones = [];};
// Reconcile vehicles tagged by this addon in case another framework moved or
// rebuilt the registry. The scan is cached for one second under queue load.
if (diag_tickTime >= (missionNamespace getVariable ["CLDW_NextCapReconcile",0])) then {
    CLDW_NextCapReconcile = diag_tickTime + 1;
    {
        if (_x getVariable ["CLDW_AI_Spawned",false] &&
            {!(_x getVariable ["CLDW_Orphaned",false])}) then {CLDW_activeDrones pushBackUnique _x;};
    } forEach vehicles;
};
private _live = CLDW_activeDrones select {
    !isNull _x && {alive _x} && {_x getVariable ["CLDW_AI_Spawned", false]} &&
    {!(_x getVariable ["CLDW_Orphaned",false])}
};
CLDW_activeDrones = _live;
private _sideSetting = switch (_side) do {
    case west: {"CLDW_Setting_MaxActiveWest"};
    case east: {"CLDW_Setting_MaxActiveEast"};
    case independent: {"CLDW_Setting_MaxActiveIndependent"};
    default {""};
};
if (_sideSetting == "") exitWith { false };
private _globalCap = round (missionNamespace getVariable ["CLDW_Setting_MaxActiveGlobal",12]) max 0;
private _sideCap = round (missionNamespace getVariable [_sideSetting,6]) max 0;
private _sideCount = {
    private _taggedSide = _x getVariable ["CLDW_DroneSide",sideUnknown];
    if (_taggedSide == sideUnknown) then {
        private _op = _x getVariable ["CLDW_CurrentOperator",objNull];
        if (!isNull _op) then {_taggedSide = side group _op;};
    };
    _taggedSide == _side
} count _live;
private _allowed = (count _live < _globalCap) && {_sideCount < _sideCap};
if (!_allowed && {diag_tickTime >= (missionNamespace getVariable ["CLDW_NextCapLog",0])}) then {
    CLDW_NextCapLog = diag_tickTime + 10;
    diag_log format ["CLDW [Cap]: Denied %1 launch; global %2/%3, side %4/%5, stagger %6.",
        _side,count _live,_globalCap,_sideCount,_sideCap,
        missionNamespace getVariable ["CLDW_Setting_LaunchStagger",10]];
};
_allowed
