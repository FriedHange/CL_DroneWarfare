params [["_drone", objNull], ["_lastSeenPos", [0,0,0]], ["_man", objNull]];

if (isNull _drone || {!alive _drone}) exitWith {};

{
    if (_x in switchableUnits) then { removeSwitchableUnit _x; };
} forEach (crew _drone);

// Resolve operator dynamically if dead/null (teleport/despawn guard)
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

// Leave the operator group during disengage return flight to prevent overwriting squad waypoints
private _side = side _drone;
private _grp = createGroup _side;
(crew _drone) joinSilent _grp;
_grp setVariable ["daoExclude", true, true];
_grp setVariable ["dceExclude", true, true];
_grp setVariable ["Vcm_Disable", true, true];

_drone enableAI "PATH";
_drone enableAI "MOVE";
_drone doWatch objNull;
_grp setBehaviour "AWARE";
_grp setCombatMode "BLUE";

if (!isNull _man && {alive _man}) then {
    private _cruiseSpeed = (missionNamespace getVariable ["CLDW_Setting_CruiseSpeed", 85]) / 3.6;
    _drone forceSpeed _cruiseSpeed;

    // Set destination immediately so the drone never hovers during the first sleep gap
    private _manPos2DImmediate = [getPosATL _man select 0, getPosATL _man select 1, 0];
    private _wpImmediate = _grp addWaypoint [_manPos2DImmediate, 15];
    _wpImmediate setWaypointType "MOVE";
    _wpImmediate setWaypointSpeed "FULL";
    (driver _drone) doMove _manPos2DImmediate;
    _drone doMove _manPos2DImmediate;
    _drone flyInHeight 25;

    private _timeout = time + 45;
    waitUntil {
        sleep 1;

        // Check if player took control
        private _controller = uavControl _drone select 0;
        if (!isNull _controller && {isPlayer _controller}) exitWith {
            _drone setVariable ["CLDW_Disengaged", false, true];
            _drone setVariable ["CLDW_CurrentTarget", objNull, true];
            true
        };

        // Resolve operator dynamically if they die or teleport during flight
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

        if (isNull _man || {!alive _man}) exitWith { true };
        if (isNull _drone || {!alive _drone}) exitWith { true };

        private _manPos2D = [getPosATL _man select 0, getPosATL _man select 1, 0];

        // Update return waypoint and move order dynamically so the drone tracks a moving squad
        if (count (wayPoints _grp) > 0) then {
            (wayPoints _grp select 0) setWPPos _manPos2D;
        } else {
            private _wpReturn = _grp addWaypoint [_manPos2D, 15];
            _wpReturn setWaypointType "MOVE";
        };
        (driver _drone) doMove _manPos2D;
        _drone doMove _manPos2D;

        private _dronePos = getPosASLVisual _drone;
        private _manPosASL = getPosASLVisual _man;
        private _distToMan = _dronePos distance _manPosASL;
        if (_distToMan > 15) then {
            private _dirVector = vectorNormalized (_manPosASL vectorDiff _dronePos);
            private _targetVel = _dirVector vectorMultiply _cruiseSpeed;
            private _curVel = velocity _drone;
            private _curHorizVel = [(_curVel select 0), (_curVel select 1), 0];
            private _desiredHorizVel = [(_targetVel select 0), (_targetVel select 1), 0];
            
            private _accelRate = 18; // m/s² cruise acceleration rate
            private _maxVelChange = _accelRate * 1.0; // 1s sleep step
            private _velDiff = _desiredHorizVel vectorDiff _curHorizVel;
            private _diffMag = vectorMagnitude _velDiff;
            private _newHorizVel = if (_diffMag <= _maxVelChange) then { _desiredHorizVel } else { _curHorizVel vectorAdd ((vectorNormalized _velDiff) vectorMultiply _maxVelChange) };
            
            _drone setVelocity [(_newHorizVel select 0), (_newHorizVel select 1), (_curVel select 2) max -2];
        };

        ((getPosVisual _drone) distance2D _manPos2D < 35) || {time > _timeout}
    };

    if (!alive _drone || isNull _drone) exitWith {};

    private _controller2 = uavControl _drone select 0;
    if (!isNull _controller2 && {isPlayer _controller2}) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Player took control of drone; disengage aborted.";
        };
    };

    if (isNull _man || {!alive _man}) exitWith {
        if (missionNamespace getVariable ["ddtDebug", false]) then {
            systemChat "Drone returning: Operator died during flight, deleting crew to crash.";
        };
        { deleteVehicle _x } forEach (crew _drone);
        deleteGroup _grp;
    };

    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "Drone disengaging: Returned to squad. Rejoining group...";
    };

    private _opGrp = group _man;
    private _shouldJoin = !isNull _opGrp && {!({isPlayer _x} count (units _opGrp) > 0)};
    if (_shouldJoin) then {
        (crew _drone) joinSilent _opGrp;

        private _crew = crew _drone;
        if (count _crew > 0) then {
            private _joinTimeout = time + 5;
            waitUntil {
                sleep 0.1;
                (group (_crew select 0) == _opGrp) || {time > _joinTimeout}
            };
        };

        _drone setVariable ["CLDW_Disengaged", false, true];
        _drone setVariable ["CLDW_CurrentTarget", objNull, true];
        _drone setVariable ["ddtOwner", _man, true];
        _drone setVariable ["ddtOwner", str _man, true];

        sleep 1;
        deleteGroup _grp;

        private _uavType = toLower (typeOf _drone);
        private _isSuicide = (_uavType find "crocus" > -1) || 
                             {_uavType find "kvn" > -1} || 
                             {_uavType find "uafpv" > -1} || 
                             {_uavType find "rc40_he" > -1};
        if (_isSuicide) then {
            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
        } else {
            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Unassigned.sqf";
        };
    } else {
        _drone setVariable ["CLDW_Disengaged", false, true];
        _drone setVariable ["CLDW_CurrentTarget", objNull, true];
        _drone setVariable ["ddtOwner", _man, true];
        _drone setVariable ["ddtOwner", str _man, true];

        private _uavType = toLower (typeOf _drone);
        private _isSuicide = (_uavType find "crocus" > -1) || 
                             {_uavType find "kvn" > -1} || 
                             {_uavType find "uafpv" > -1} || 
                             {_uavType find "rc40_he" > -1};
        if (_isSuicide) then {
            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_FPV.sqf";
        } else {
            [_drone, _man] execVM "DrongosDroneTweaks\Scripts\Drones\AI_Unassigned.sqf";
        };
    };
} else {
    if (missionNamespace getVariable ["ddtDebug", false]) then {
        systemChat "Drone disengaging: Operator dead, deleting crew to crash.";
    };
    { deleteVehicle _x } forEach (crew _drone);
    deleteGroup _grp;
};
