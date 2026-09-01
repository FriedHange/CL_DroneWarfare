/*
    File: fn_disengage.sqf
    Author: Carl Lorenzo
    Description:
        Guarantees reliable, uninterrupted return flight for disengaging drones back to their squad/operator.
*/

params [["_drone", objNull], ["_lastSeenPos", [0,0,0]], ["_man", objNull]];

if (isNull _drone || {!alive _drone}) exitWith {};

{
    if (_x in switchableUnits) then { removeSwitchableUnit _x; };
} forEach (crew _drone);

// Mark drone as disengaging
_drone setVariable ["CLDW_Disengaged", true, true];
_drone setVariable ["CLDW_CurrentTarget", objNull, true];

// Resolve operator dynamically if dead/null
if (isNull _man || {!alive _man}) then {
    private _ownerVar = _drone getVariable ["ddtOwner", objNull];
    if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
        _man = _ownerVar;
    } else {
        if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
            { if (str _x == _ownerVar) exitWith { _man = _x; }; } forEach allUnits;
        };
    };
    if (isNull _man || {!alive _man}) then {
        private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
        if (!isNull _opGrp) then {
            private _aliveUnits = (units _opGrp) select { alive _x };
            if (count _aliveUnits > 0) then {
                _man = leader _opGrp;
                _drone setVariable ["CLDW_CurrentOperator", _man, true];
                _drone setVariable ["ddtOwner", _man, true];
                _drone setVariable ["ddtOwner", str _man, true];
            };
        };
    };
};

if (isNull _man || {!alive _man}) exitWith {
    _drone setFuel 0;
};

private _side = side _drone;
private _grp = group (driver _drone);
if (isNull _grp) then {
    _grp = createGroup _side;
    (crew _drone) joinSilent _grp;
};

_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone doWatch objNull;
_grp setBehaviour "CARELESS";
_grp setCombatMode "BLUE";

private _cruiseSpeed = (missionNamespace getVariable ["CLDW_Setting_CruiseSpeed", 85]) / 3.6;
_drone setSpeedMode "FULL";
_drone forceSpeed _cruiseSpeed;
_drone flyInHeight 30;

private _timeout = time + 60;

while {alive _drone && {!isNull _drone} && {alive _man} && {!isNull _man} && {time < _timeout}} do {
    // Check if player took manual control
    private _controller = uavControl _drone select 0;
    if (!isNull _controller && {isPlayer _controller}) exitWith {
        _drone setVariable ["CLDW_Disengaged", false, true];
    };

    private _dronePos = getPosASLVisual _drone;
    private _manPosASL = getPosASLVisual _man;
    private _distToMan = _dronePos distance2D _manPosASL;

    // Reached squad formation zone (< 25m)
    if (_distToMan <= 25) exitWith {};

    private _curManPos2D = [getPosATL _man select 0, getPosATL _man select 1, 0];
    (driver _drone) doMove _curManPos2D;
    _drone doMove _curManPos2D;

    sleep 1.0;
};

if (!alive _drone || isNull _drone) exitWith {};

// Successfully back with the squad
_drone setVariable ["CLDW_Disengaged", false, true];
_drone setVariable ["CLDW_CurrentTarget", objNull, true];
_drone setVariable ["ddtOwner", _man, true];
_drone setVariable ["ddtOwner", str _man, true];
_drone setVariable ["CLDW_CurrentOperator", _man, true];

// Settle into formation hover above squad
_drone flyInHeight 30;
(driver _drone) doMove (getPosATL _man);

private _uavType = toLower (typeOf _drone);
private _isSuicide = ((_uavType find "crocus" > -1) || 
                     {_uavType find "kvn" > -1} || 
                     {_uavType find "uafpv" > -1} || 
                     {_uavType find "rc40_he" > -1} ||
                     {_uavType find "rc-40_he" > -1} ||
                     {_uavType find "fpv" > -1}) &&
                     {!(_uavType find "uav_01" > -1)} &&
                     {!(_uavType find "darter" > -1)} &&
                     {!(_uavType find "tayran" > -1)} &&
                     {!(_uavType find "uav_06" > -1)} &&
                     {!(_uavType find "uas_06" > -1)} &&
                     {!(_uavType find "al6" > -1)} &&
                     {!(_uavType find "al-6" > -1)} &&
                     {!(_uavType find "sensor" > -1)} &&
                     {!(_uavType find "smoke" > -1)} &&
                     {!(_uavType find "recon" > -1)} &&
                     {!(_uavType find "mavic" > -1)} &&
                     {!(_uavType find "blackhornet" > -1)} &&
                     {!(_uavType find "ied" > -1)};

if (_isSuicide) then {
    if (fileExists "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf") then {
        [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
    };
} else {
    if (fileExists "DrongosDroneTweaks\Scripts\Drones\AI_Unassigned.sqf") then {
        [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Unassigned.sqf";
    };
};
