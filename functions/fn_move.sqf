params [["_drone", objNull], ["_pos", [0,0,0]]];

if (isNull _drone) exitWith { [0,0,0] };

// Check if the target is too far (teleport guard)
private _target = _drone getVariable ["CLDW_CurrentTarget", objNull];
private _maxRangeSetting = missionNamespace getVariable ["CLDW_Setting_MaxRange", 1500];
private _maxRange = _maxRangeSetting + (if (!isNull _target) then { 1500 } else { 800 }); 

private _isTooFar = false;
if (!isNull _target) then {
    if ((_drone distance _target) > _maxRange) then {
        _isTooFar = true;
    };
} else {
    if ((_drone distance _pos) > _maxRange) then {
        _isTooFar = true;
    };
};

if (_isTooFar) exitWith {
    if (missionNamespace getVariable ["CLDW_Setting_EnableMod", true]) then {
        private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
        if (alive _drone && !isNull _man) then {
            // Spawn disengage logic, using current drone position as last seen target position
            [_drone, getPosASLVisual _drone, _man] spawn CLDW_fnc_disengage;
        } else {
            _drone setFuel 0;
            _drone call DB_fnc_fpv_onDestroy;
        };
    };
    _pos
};

// Standard move behavior from Drongos Drone Tweaks
private _grp = group _drone;
private _man = _drone getVariable ["CLDW_CurrentOperator", objNull];
private _isMerged = (!isNull _man && {group _man == _grp});

if (!_isMerged) then {
    {deleteWaypoint _x} forEach (wayPoints _grp);
    _grp addWaypoint [_pos, 0];
    {_x setWaypointType "MOVE"} forEach (wayPoints _grp);
};
private _cruiseSpeed = (missionNamespace getVariable ["CLDW_Setting_CruiseSpeed", 85]) / 3.6;
_drone forceSpeed _cruiseSpeed;

// Active velocity assistance with smooth acceleration so quadcopters cruise realistically
private _dronePos = getPosASLVisual _drone;
private _distToPos = _dronePos distance _pos;
if (_distToPos > 3) then {
    private _dirVector = vectorNormalized (_pos vectorDiff _dronePos);
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
