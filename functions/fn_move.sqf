params [["_drone", objNull], ["_pos", [0,0,0]]];

if (isNull _drone || {!alive _drone}) exitWith { [0,0,0] };

private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
if (isNull _man || {!alive _man}) then {
    private _ownerVar = _drone getVariable ["ddtOwner", objNull];
    if (_ownerVar isEqualType objNull && {!isNull _ownerVar}) then {
        _man = _ownerVar;
    } else {
        if (_ownerVar isEqualType "" && {_ownerVar != ""}) then {
            { if (str _x == _ownerVar) exitWith { _man = _x; }; } forEach allUnits;
        };
    };
    if (isNull _man) then {
        private _opGrp = _drone getVariable ["CLDW_OperatorGroup", grpNull];
        if (!isNull _opGrp) then {
            private _aliveUnits = (units _opGrp) select { alive _x };
            if (count _aliveUnits > 0) then { _man = leader _opGrp; };
        };
    };
};

// Fallback for invalid/empty coordinates to prevent false teleport guards
if (_pos isEqualTo [0,0,0] || {count _pos < 2}) then {
    if (!isNull _man && {alive _man}) then {
        _pos = getPosATL _man;
    } else {
        _pos = getPosATL _drone;
    };
};

// Check if the target is too far (teleport guard)
private _target = _drone getVariable ["CLDW_CurrentTarget", objNull];
private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500];
private _maxRange = _maxRangeSetting + (if (!isNull _target) then { 1500 } else { 800 }); 

private _isTooFar = false;
if (!isNull _target && {alive _target}) then {
    if ((_drone distance _target) > _maxRange) then {
        _isTooFar = true;
    };
} else {
    if (!isNull _man && {(_drone distance _man) > _maxRange}) then {
        _isTooFar = true;
    };
};

if (_isTooFar) exitWith {
    if (missionNamespace getVariable ["CLDW_Setting_EnableMod", true]) then {
        if (alive _drone && !isNull _man) then {
            [_drone, getPosASLVisual _drone, _man] spawn CLDW_fnc_disengage;
        } else {
            _drone setFuel 0;
            if (!isNil "DB_fnc_fpv_onDestroy") then { _drone call DB_fnc_fpv_onDestroy; };
            _drone setDamage 1;
        };
    };
    _pos
};

// Standard move behavior
private _grp = group (driver _drone);
private _isMerged = (!isNull _man && {group _man == _grp});

if (!_isMerged && {!isNull _grp}) then {
    {deleteWaypoint _x} forEach (wayPoints _grp);
    private _wp = _grp addWaypoint [_pos, 0];
    _wp setWaypointType "MOVE";
};

// Always command the drone pilot directly
(driver _drone) doMove _pos;
_drone doMove _pos;

private _cruiseSpeed = (missionNamespace getVariable ["CLDW_Setting_CruiseSpeed", 85]) / 3.6;
_drone forceSpeed _cruiseSpeed;

// Active velocity assistance with smooth acceleration so quadcopters cruise realistically
private _dronePos = getPosASLVisual _drone;
private _posASL = if (count _pos > 2) then { AGLToASL _pos } else { AGLToASL [_pos select 0, _pos select 1, 30] };
private _distToPos = _dronePos distance _posASL;
if (_distToPos > 3) then {
    private _dirVector = vectorNormalized (_posASL vectorDiff _dronePos);
    private _targetVel = _dirVector vectorMultiply _cruiseSpeed;
    private _curVel = velocity _drone;
    private _curHorizVel = [(_curVel select 0), (_curVel select 1), 0];
    private _desiredHorizVel = [(_targetVel select 0), (_targetVel select 1), 0];
    
    private _accelRate = 18; // m/s² cruise acceleration rate
    private _maxVelChange = _accelRate * 0.1; // 10Hz tick step
    private _velDiff = _desiredHorizVel vectorDiff _curHorizVel;
    private _diffMag = vectorMagnitude _velDiff;
    private _newHorizVel = if (_diffMag <= _maxVelChange) then { _desiredHorizVel } else { _curHorizVel vectorAdd ((vectorNormalized _velDiff) vectorMultiply _maxVelChange) };
    
    _drone setVelocity [(_newHorizVel select 0), (_newHorizVel select 1), (_curVel select 2) max -2];
};

_pos
