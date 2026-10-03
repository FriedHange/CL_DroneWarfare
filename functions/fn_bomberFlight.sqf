if (isNil "DDT_fnc_GuideToTarget2" || {isNil "DDT_fnc_GuideToTarget3"}) exitWith {};

params ["_drone", "_target"];
if (isNull _drone || {isNull _target} || {!alive _drone} || {!alive _target}) exitWith {};
if (_drone getVariable ["CLDW_Orphaned",false]) exitWith {};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};

private _dropperSpeed = ((missionNamespace getVariable ["CLDW_Setting_DropperSpeed", 35]) / 3.6) min 10;
private _minDistanceToTarget = 9;
// One managed controller owns both takeoff and bombing.
_drone flyInHeight 80;
private _climbEnd = time + 45;
while {alive _drone && {local _drone} && {alive driver _drone} &&
    {!(_drone getVariable ["CLDW_Orphaned",false])} &&
    {(getPosATL _drone select 2) < 70} && {time < _climbEnd}} do {
    if ([_drone] call CLDW_fnc_getEWState) exitWith {};
    _drone setVelocity [0, 0, 4];
    sleep 0.05;
};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState} ||
    {(getPosATL _drone select 2) < 70}) exitWith {};
private _z = (getPosASL _drone) select 2;

_drone setCombatMode "BLUE";
_drone setBehaviour "CARELESS";
_drone setSpeedMode "NORMAL";
_drone forceSpeed _dropperSpeed;

private _targetVelocity = [];
while {!isNull _drone && {!isNull _target} && {alive _drone} && {alive _target} &&
    {!(_drone getVariable ["CLDW_Orphaned",false])}} do {
    if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};
    private _currentPos = getPosASLVisual _drone;
    private _targetPos = getPosASLVisual _target;
    _targetPos set [2, _z];

    if (((getPosASLVisual _drone) distance _targetPos) <= _minDistanceToTarget) exitWith {};

    private _forwardVector = vectorNormalized (_targetPos vectorDiff _currentPos);
    private _rightVector = (_forwardVector vectorCrossProduct [0,0,1]) vectorMultiply -1;
    private _upVector = _forwardVector vectorCrossProduct _rightVector;

    // Move smoothly at realistic calm bomber speed (~30-35 km/h, 8-9.7 m/s)
    _targetVelocity = _forwardVector vectorMultiply _dropperSpeed;
    _drone setVelocity _targetVelocity;

    sleep 0.3;
    if (isNull _drone || {!alive _drone}) exitWith {};
    _drone setVectorDirAndUp [_forwardVector, _upVector];
};

if (!alive _drone || isNull _drone || {_drone getVariable ["CLDW_Orphaned",false]}) exitWith {};
if (!local _drone || {!alive driver _drone} || {[_drone] call CLDW_fnc_getEWState}) exitWith {};

if (isNull _target || {!alive _target} || {!([_drone, _target] call CLDW_fnc_isEnemy)}) exitWith {};
private _lowerDrone = toLower (typeOf _drone);
private _isIEDDrone = _lowerDrone in [
    "c_idap_uav_06_antimine_f",
    "b_g_uav_02_ied_lxws",
    "b_tura_uav_02_ied_lxws",
    "o_g_uav_02_ied_lxws",
    "o_tura_uav_02_ied_lxws",
    "i_g_uav_02_ied_lxws",
    "i_tura_uav_02_ied_lxws"
] || {(_lowerDrone find "uav_02_ied" > -1) || {(_lowerDrone find "tura_uav" > -1)}};

private _operator = _drone getVariable ["CLDW_CurrentOperator", objNull];
if (isNull _operator) then { _operator = _drone getVariable ["CLDW_LastController", objNull]; };
if (isNull _operator) then { _operator = _drone getVariable ["ddtOwner", objNull]; };
if (!isNull _operator && {!isNull _target}) then {
    _target setVariable ["CLDW_LastDroneAttacker", _operator, true];
    _target setVariable ["CLDW_LastDroneAttackerTime", time, true];
    _target setVariable ["CLDW_LastDroneAttackerSide", side group _operator, true];
};

if (_isIEDDrone) exitWith {
    if !(someAmmo _drone) exitWith { _drone setVariable ["ddtHasAmmo", false, true]; };
    _drone setVariable ["ddtTargetPos", (getPosASL _target), true];
    private _EH = _drone addEventHandler ["Fired", {
        params ["_unit", "_weapon", "_muzzle", "_mode", "_ammo", "_magazine", "_projectile", "_gunner"];
        private _op = _unit getVariable ["CLDW_CurrentOperator", objNull];
        if (isNull _op) then { _op = _unit getVariable ["CLDW_LastController", objNull]; };
        if (!isNull _op) then { _projectile setVariable ["CLDW_CurrentOperator", _op, true]; };
        [_projectile, _unit] spawn DDT_fnc_GuideToTarget3;
        true
    }];
    _drone setVariable ["CLDW_BomberFiredEH", _EH];
    _drone setCombatMode "RED";
    _drone fire (currentWeapon _drone);
    _target = objNull;
    sleep 1;
    if (!alive _drone) exitWith {};
    _drone removeEventHandler ["Fired", _EH];
    _drone setVariable ["CLDW_BomberFiredEH", -1];
    _drone setCombatMode "BLUE";
    _drone setBehaviour "AWARE";
    _drone setSpeedMode "NORMAL";
    _drone forceSpeed _dropperSpeed;
    _drone flyInHeight 80;
    if !(someAmmo _drone) exitWith { _drone setVariable ["ddtHasAmmo", false, true]; };
    sleep 10;
    if (!alive _drone) exitWith {};
    _drone setVariable ["ddtBusy", false, true];
};

{ deleteVehicle _x; } forEach (attachedObjects _drone);
private _shellPos = getPosATL _drone;
private _sz = (_shellPos select 2) - 0.2;
_shellPos set [2, _sz];
private _shellType = "G_40mm_HE";
private _shell = createVehicle [_shellType, _shellPos, [], 0, "FLY"];
_shell setVectorUp [0, 0.99, 0.01];
if (!isNull _operator) then {
    _shell setVariable ["CLDW_CurrentOperator", _operator, true];
};
[_shell, _target, 10] spawn DDT_fnc_GuideToTarget2;

_drone setSpeedMode "NORMAL";
_drone forceSpeed _dropperSpeed;
_drone flyInHeight 80;
_drone setVariable ["ddtHasAmmo", false, true];
_drone setVariable ["ddtBusy", false, true];
