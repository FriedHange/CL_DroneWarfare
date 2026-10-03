// Owner-local native AI search, with slow recovery for FPV pilots that stall.
params [['_drone',objNull],['_center',[0,0,0]],['_lostTarget',objNull],['_operator',objNull]];
if (isNull _drone || {!local _drone} || {!alive driver _drone}) exitWith {};
if (_drone getVariable ["CLDW_Orphaned",false]) exitWith {};
private _deadline = _drone getVariable ['CLDW_SearchWindowUntil',0];
if (_deadline == 0) then {
    _deadline = time + 60;
    _drone setVariable ['CLDW_SearchWindowUntil',_deadline];
};
if (_deadline <= time) exitWith {
    _drone setVariable ['CLDW_SearchUntil',0,true];
    _drone setVariable ['CLDW_Disengaged',true,true];
    [_drone,'RETURN',[_drone,_center,_operator]] call CLDW_fnc_startController;
};
_drone setVariable ['CLDW_SearchUntil',_deadline,true];
_drone setVariable ['CLDW_CurrentTarget',objNull,true];
_drone setVariable ['CLDW_SearchFallback',false];
_drone setVariable ['CLDW_BuildingSearch',false];
_drone setVariable ['CLDW_InspectionBuilding',objNull];
_drone setVariable ['CLDW_SearchVisitedBuildings',[]];

private _pilot = driver _drone;
private _group = group _pilot;
private _ownGroup = isNull _operator || {_group != group _operator};
private _type = toLower (typeOf _drone);
private _canFallback = (_type find 'kvn' > -1) || {_type find 'uafpv' > -1};
private _scriptedFallback = false;
_pilot enableAI 'PATH';
_pilot enableAI 'MOVE';
_drone enableAI 'PATH';
_drone enableAI 'MOVE';
_drone setBehaviour 'CARELESS';
_drone setSpeedMode 'LIMITED';
_drone forceSpeed -1;
_drone limitSpeed 35;
_drone flyInHeight 30;
if (_ownGroup) then {_group setSpeedMode 'LIMITED';};

private _angle = _drone getVariable ['CLDW_SearchAngle',(getDir _drone + 45) mod 360];
private _leg = [0,0,0];
private _waypoint = [];
private _lastOrder = -100;
private _lastProgressPos = getPosASLVisual _drone;
private _lastProgressTime = time;
private _nextVisualCheck = 0;
private _nextAreaScan = 0;
private _attackOpportunity = {
    params ['_candidate'];
    if (isNull _candidate || {!alive _candidate} ||
        {!([_drone,_candidate] call CLDW_fnc_hasVisualTarget)}) exitWith {false};
    if !(_candidate isKindOf 'CAManBase') exitWith {true};
    private _aim = [_drone,_candidate] call CLDW_fnc_visibleAimPoint;
    if (_aim isEqualTo []) exitWith {false};
    private _route = [_drone,_candidate,_aim] call CLDW_fnc_planAttack;
    if (_route param [3,false]) exitWith {true};
    !(([_drone,_aim,_candidate,true] call CLDW_fnc_findSafeApproach) isEqualTo [])
};
// Terrain houses and mission-placed houses are returned by different queries.
// Build the route once so crowded compounds do not trigger a scan every tick.
private _centerAGL = ASLToAGL _center;
private _candidates = nearestTerrainObjects [_centerAGL,['HOUSE','BUILDING','BUNKER','FORTRESS'],60,false,true];
_candidates append (nearestObjects [_centerAGL,['House','Building'],60,true]);
private _nearest = nearestBuilding _centerAGL;
if (!isNull _nearest && {_nearest distance2D _center <= 60}) then {
    _candidates pushBack _nearest;
};
private _buildings = [];
{
    if (!isNull _x && {!(_x in _buildings)} && {_x distance2D _center <= 60} &&
        {count (boundingBoxReal _x) >= 2}) then {
        _buildings pushBack _x;
    };
} forEach _candidates;
_buildings = [_buildings,[],{_x distance2D _center},'ASCEND'] call BIS_fnc_sortBy;
if (count _buildings > 4) then {_buildings resize 4;};
private _buildingSearch = !(_buildings isEqualTo []);
private _buildingIndex = 0;
private _building = objNull;
private _inspectionCenter = [0,0,0];
private _inspectionRadius = 14;
private _inspectionStage = -1;
private _inspectionAngle = 0;
private _inspectionGoal = [];
private _blockedLegs = 0;
private _inspectionStep = 45;
private _inspectionVelocity = velocity _drone;
private _loadBuilding = {
    _building = _buildings select _buildingIndex;
    private _box = boundingBoxReal _building;
    private _lo = _box select 0;
    private _hi = _box select 1;
    private _extentX = (abs (_lo select 0)) max (abs (_hi select 0));
    private _extentY = (abs (_lo select 1)) max (abs (_hi select 1));
    // The diagonal covers rotated corners; leave enough room for a fast arc.
    _inspectionRadius = ((sqrt (_extentX * _extentX + _extentY * _extentY) + 12) / 0.92388) max 40;
    _inspectionCenter = getPosASLVisual _building;
    _inspectionAngle = _inspectionCenter getDir _drone;
    _inspectionStep = 45;
    _inspectionStage = -1;
    _inspectionGoal = [];
    _blockedLegs = 0;
    _drone setVariable ['CLDW_InspectionBuilding',_building];
    _drone setVariable ['CLDW_InspectionRadius',_inspectionRadius];
    diag_log format ['CLDW [Search]: %1 inspecting building %2/%3 (%4).',typeOf _drone,
        _buildingIndex + 1,count _buildings,typeOf _building];
};
if (_buildingSearch) then {
    call _loadBuilding;
    _drone flyInHeight 6;
    _pilot disableAI 'PATH';
    _drone disableAI 'PATH';
    _drone setVariable ['CLDW_BuildingSearch',true];
};

private _handoff = false;
while {!_handoff && {!isNull _drone} && {alive _drone} && {local _drone} &&
    {!(_drone getVariable ["CLDW_Orphaned",false])} &&
    {alive driver _drone} && {time < _deadline} &&
    {!([_drone] call CLDW_fnc_getEWState)} &&
    {!([_drone] call CLDW_fnc_playerPiloting)}} do {
    if (time >= _nextVisualCheck) then {
        _nextVisualCheck = time + 0.75;
        private _boarded = if (!isNull _lostTarget && {_lostTarget isKindOf 'CAManBase'}) then {
            vehicle _lostTarget
        } else {objNull};
        if (!isNull _boarded && {_boarded != _lostTarget} &&
            {[_drone,_boarded,[_drone] call CLDW_fnc_isAPDrone] call CLDW_fnc_canAttackVehicle} &&
            {[_drone,_boarded] call CLDW_fnc_isEnemy} &&
            {_drone distance _boarded <= (missionNamespace getVariable ['CLDW_Setting_MaxRange',750])} &&
            {[_drone,_boarded] call CLDW_fnc_hasVisualTarget}) exitWith {
            if (_lostTarget getVariable ['CLDW_AssignedDrone',objNull] == _drone) then {
                _lostTarget setVariable ['CLDW_AssignedDrone',objNull,true];
            };
            _boarded setVariable ['CLDW_AssignedDrone',_drone,true];
            _drone setVariable ['CLDW_SearchUntil',0,true];
            _drone setVariable ['CLDW_CurrentTarget',_boarded,true];
            _drone forceSpeed -1;
            diag_log format ['CLDW [SearchHandoff]: %1 followed boarded target into %2.',
                typeOf _drone,typeOf _boarded];
            _handoff = true;
            [_drone,'GUIDE',[_drone,_boarded,0,0.1]] call CLDW_fnc_startController;
        };
        if (!isNull _lostTarget && {alive _lostTarget} &&
            {vehicle _lostTarget == _lostTarget} &&
            {_drone distance _lostTarget <= (missionNamespace getVariable ['CLDW_Setting_MaxRange',750])} &&
            {[_lostTarget] call _attackOpportunity}) exitWith {
            _drone setVariable ['CLDW_SearchUntil',0,true];
            _drone setVariable ['CLDW_CurrentTarget',_lostTarget,true];
            _drone setVariable ['CLDW_SearchAttackBoost',true];
            _drone forceSpeed -1;
            diag_log format ['CLDW [SearchHandoff]: %1 reacquired original target %2.',typeOf _drone,typeOf _lostTarget];
            _handoff = true;
            [_drone,'GUIDE',[_drone,_lostTarget,0,0.1]] call CLDW_fnc_startController;
        };
    };
    if (_handoff) exitWith {};
    if (time >= _nextAreaScan) then {
        _nextAreaScan = time + 2;
        private _nearby = ([_drone,150] call CLDW_fnc_getTargetsAT) select {
            _x distance2D _center <= 130 &&
            {[_x] call _attackOpportunity}
        };
        if !(_nearby isEqualTo []) exitWith {
            _drone setVariable ['CLDW_SearchUntil',0,true];
            _drone setVariable ['CLDW_CurrentTarget',_nearby select 0,true];
            _drone setVariable ['CLDW_SearchAttackBoost',true];
            _drone forceSpeed -1;
            diag_log format ['CLDW [SearchHandoff]: %1 acquired another target %2.',typeOf _drone,typeOf (_nearby select 0)];
            _handoff = true;
            [_drone,'GUIDE',[_drone,_nearby select 0,0,0.1]] call CLDW_fnc_startController;
        };
    };
    if (_handoff) exitWith {};

    if (_buildingSearch) then {
        private _here = getPosASLVisual _drone;
        if (_inspectionGoal isEqualTo [] || {_here distance _inspectionGoal <
            ((vectorMagnitude _inspectionVelocity * 0.45) max 8)}) then {
            if (_inspectionStage >= 10) then {
                _buildingIndex = _buildingIndex + 1;
                if (_buildingIndex >= count _buildings) then {
                    _buildingSearch = false;
                    _drone setVariable ['CLDW_BuildingSearch',false];
                    _drone setVariable ['CLDW_InspectionBuilding',objNull];
                    _pilot enableAI 'PATH';
                    _drone enableAI 'PATH';
                    _drone flyInHeight 30;
                    _lastProgressPos = _here;
                    _lastProgressTime = time;
                } else {
                    call _loadBuilding;
                };
            };
            if (_buildingSearch) then {
                if (_inspectionStage == -1) then {
                    // Reach a clear point outside the footprint before descending.
                    // Never fly across the roof and then drop beside the wall.
                    private _bestDistance = 1e9;
                    {
                        private _angle = (_inspectionAngle + _x) mod 360;
                        private _xPos = (_inspectionCenter select 0) + (sin _angle) * _inspectionRadius;
                        private _yPos = (_inspectionCenter select 1) + (cos _angle) * _inspectionRadius;
                        private _lowZ = (getTerrainHeightASL [_xPos,_yPos]) + 6;
                        private _candidate = [_xPos,_yPos,(_here select 2) max _lowZ];
                        if ([_here,_candidate,_drone,objNull,0.5] call CLDW_fnc_clearFlightPath &&
                            {_here distance _candidate < _bestDistance}) then {
                            _bestDistance = _here distance _candidate;
                            _inspectionGoal = _candidate;
                            _inspectionAngle = _angle;
                        };
                    } forEach [0,45,-45,90,-90,135,-135,180];
                    if (_inspectionGoal isEqualTo []) then {
                        _inspectionGoal = _here;
                        _inspectionStage = 10;
                    };
                } else {
                if (_inspectionStage == 0) then {
                    // Descend only after reaching the exterior point.
                    private _x = (_inspectionCenter select 0) + (sin _inspectionAngle) * _inspectionRadius;
                    private _y = (_inspectionCenter select 1) + (cos _inspectionAngle) * _inspectionRadius;
                    _inspectionGoal = [_x,_y,(getTerrainHeightASL [_x,_y]) + 6];
                } else {
                    if (_inspectionStage > 1) then {
                        _inspectionAngle = (_inspectionAngle + _inspectionStep + 360) mod 360;
                    };
                    private _x = (_inspectionCenter select 0) + (sin _inspectionAngle) * _inspectionRadius;
                    private _y = (_inspectionCenter select 1) + (cos _inspectionAngle) * _inspectionRadius;
                    _inspectionGoal = [_x,_y,(getTerrainHeightASL [_x,_y]) + 6];
                    if (_inspectionStage == 2) then {
                        private _visited = _drone getVariable ['CLDW_SearchVisitedBuildings',[]];
                        if !(_building in _visited) then {
                            _visited pushBack _building;
                            _drone setVariable ['CLDW_SearchVisitedBuildings',_visited];
                        };
                    };
                };
                };
                _inspectionStage = _inspectionStage + 1;
                _drone setVariable ['CLDW_InspectionStage',_inspectionStage];
                _drone setVariable ['CLDW_SearchLeg',ASLToAGL _inspectionGoal];
                _drone setVariable ['CLDW_ProgressGoalASL',_inspectionGoal];
            };
        };
        if (_buildingSearch) then {
        private _toGoal = _inspectionGoal vectorDiff _here;
        private _direction = vectorNormalized _toGoal;
        private _next = _here vectorAdd (_direction vectorMultiply ((_here distance _inspectionGoal) min 2));
        if ([_here,_inspectionGoal,_drone,objNull,0.5] call CLDW_fnc_clearFlightPath &&
            {[_here,_next,_drone,objNull,0.5] call CLDW_fnc_clearFlightPath}) then {
            if (_here distance _inspectionGoal < 3) then {_blockedLegs = 0;};
            private _horizontal = vectorNormalized [_direction select 0,_direction select 1,0];
            private _look = vectorNormalized [(_inspectionCenter select 0) - (_here select 0),
                (_inspectionCenter select 1) - (_here select 1),
                ((_inspectionCenter select 2) + 2) - (_here select 2)];
            if (hasPilotCamera _drone) then {
                if !(_horizontal isEqualTo [0,0,0]) then {
                    _drone setVectorDirAndUp [_horizontal,[0,0,1]];
                };
                private _cameraHeld = false;
                private _control = uavControl _drone;
                for '_i' from 0 to ((count _control) - 2) step 2 do {
                    if ((_control select (_i + 1)) == 'GUNNER' &&
                        {isPlayer (_control select _i)}) exitWith {_cameraHeld = true;};
                };
                if (!_cameraHeld) then {
                    _drone setPilotCameraDirection (_drone vectorWorldToModel _look);
                };
            } else {
                // FPV cameras are fixed to the hull; face the wall with a
                // bounded yaw and a small bank while the path curves around it.
                if !(_look isEqualTo [0,0,0]) then {
                    private _facing = vectorDirVisual _drone;
                    private _faceAngle = acos (((_facing vectorDotProduct _look) min 1) max -1);
                    private _blend = if (_faceAngle < 0.01) then {1} else {(8 / _faceAngle) min 1};
                    private _newFace = vectorNormalized ((_facing vectorMultiply (1 - _blend))
                        vectorAdd (_look vectorMultiply _blend));
                    private _right = vectorNormalized (_newFace vectorCrossProduct [0,0,1]);
                    private _turnSign = ((_facing select 0) * (_look select 1) -
                        (_facing select 1) * (_look select 0));
                    private _bank = ((_turnSign * 15) max -15 min 15) * (pi / 180);
                    private _bankedUp = ([0,0,1] vectorMultiply (cos _bank)) vectorAdd
                        (_right vectorMultiply (sin _bank));
                    _drone setVectorDirAndUp [_newFace,_bankedUp];
                };
            };
            private _desiredSpeed = if (_inspectionStage <= 1) then {8} else {17};
            private _desired = [(_direction select 0) * _desiredSpeed,
                (_direction select 1) * _desiredSpeed,((_toGoal select 2) * 0.8) min 5 max -5];
            private _change = _desired vectorDiff _inspectionVelocity;
            private _changeLength = vectorMagnitude _change;
            if (_changeLength > 0.8) then {_change = (vectorNormalized _change) vectorMultiply 0.8;};
            _inspectionVelocity = _inspectionVelocity vectorAdd _change;
            private _motionEnd = _here vectorAdd (_inspectionVelocity vectorMultiply 0.2);
            if !([_here,_motionEnd,_drone,objNull,0.5] call CLDW_fnc_clearFlightPath) then {
                _inspectionVelocity = [0,0,0];
                _inspectionGoal = [];
                _blockedLegs = _blockedLegs + 1;
                _inspectionRadius = _inspectionRadius + 8;
                _drone setVariable ['CLDW_InspectionRadius',_inspectionRadius];
            };
            _drone setVelocity _inspectionVelocity;
        } else {
            // Keep circulating in one direction. Expand around neighboring
            // geometry instead of oscillating between two blocked chords.
            _blockedLegs = _blockedLegs + 1;
            _inspectionVelocity = _inspectionVelocity vectorMultiply 0.8;
            _drone setVelocity _inspectionVelocity;
            if (_blockedLegs >= 4 || {_inspectionRadius > 55}) then {
                _inspectionStage = 10;
            } else {
                _inspectionRadius = _inspectionRadius + 8;
                _drone setVariable ['CLDW_InspectionRadius',_inspectionRadius];
                _inspectionAngle = (_inspectionAngle + _inspectionStep + 360) mod 360;
                _inspectionStage = 1;
            };
            _inspectionGoal = [];
        };
        };
        sleep 0.1;
    } else {
    private _pos = getPosASLVisual _drone;
    if (_pos distance2D _lastProgressPos > 6) then {
        _lastProgressPos = _pos;
        _lastProgressTime = time;
    };
    private _stalled = time - _lastProgressTime > 7;
    if (_stalled && {_canFallback} && {!_scriptedFallback}) then {
        // These addons can ignore otherwise valid AI orders when another FPV
        // is active. Preserve the search and its cap slot instead of hovering.
        _scriptedFallback = true;
        _drone setVariable ['CLDW_SearchFallback',true];
        _pilot disableAI 'PATH';
        _drone disableAI 'PATH';
        diag_log format ['CLDW [Search]: %1 pilot ignored native orders; using slow search recovery.',typeOf _drone];
    };
    if (_leg isEqualTo [0,0,0] || {_drone distance2D _leg < 18}) then {
        _leg = [(_center select 0) + (sin _angle) * 60,
            (_center select 1) + (cos _angle) * 60,30];
        _angle = (_angle + 45) mod 360;
        _drone setVariable ['CLDW_SearchAngle',_angle];
        _drone setVariable ['CLDW_SearchLeg',_leg];
        _drone setVariable ['CLDW_ProgressGoalASL',AGLToASL _leg];
        if (_ownGroup) then {
            if (_waypoint isEqualTo []) then {
                _waypoint = _group addWaypoint [_leg,0];
                _waypoint setWaypointType 'MOVE';
                _waypoint setWaypointSpeed 'LIMITED';
            } else {
                _waypoint setWaypointPosition [_leg,0];
            };
        };
        if (!_scriptedFallback) then {
            _pilot doMove _leg;
            _drone doMove _leg;
        };
        _lastOrder = time;
    } else {
        if (_stalled && {!_scriptedFallback} && {time - _lastOrder >= 5}) then {
            // Native orders may be discarded by some FPV addons; retry without
            // forcing velocity or touching an infantry squad's waypoints.
            _pilot doMove _leg;
            _drone doMove _leg;
            _lastOrder = time;
        };
    };
    if (_scriptedFallback) then {
        private _current = getPosASLVisual _drone;
        private _toward = vectorNormalized [(_leg select 0) - (_current select 0),
            (_leg select 1) - (_current select 1),0];
        private _forward = vectorDirVisual _drone;
        _forward set [2,0];
        _forward = vectorNormalized _forward;
        if (_forward isEqualTo [0,0,0]) then {_forward = _toward;};
        private _heading = vectorNormalized ((_forward vectorMultiply 0.82) vectorAdd (_toward vectorMultiply 0.18));
        if (_heading isEqualTo [0,0,0]) then {_heading = _toward;};
        private _ground = getTerrainHeightASL _current;
        private _ridge = [_current,AGLToASL _leg,8,12] call CLDW_fnc_terrainLookahead;
        private _safeHeight = (_ground + 30) max (_ridge select 0);
        private _climb = ((_safeHeight - (_current select 2)) * 0.5) min 3 max -3;
        private _speedForRidge = 8;
        private _ridgeClimb = (_ridge select 0) - (_current select 2);
        if (_ridgeClimb > 1) then {
            _speedForRidge = _speedForRidge min ((((_ridge select 1) - 4) max 2) * 3 / _ridgeClimb) max 2.5;
        };
        _drone setVectorDirAndUp [_heading,[0,0,1]];
        _drone setVelocity [(_heading select 0) * _speedForRidge,
            (_heading select 1) * _speedForRidge,_climb];
        sleep 0.1;
    } else {
        sleep 0.5;
    };
    };
};
if (_handoff || {isNull _drone} || {!local _drone}) exitWith {};
if (_scriptedFallback || {_buildingSearch}) then {
    _pilot enableAI 'PATH';
    _drone enableAI 'PATH';
};
_drone setVariable ['CLDW_SearchFallback',false];
_drone setVariable ['CLDW_BuildingSearch',false];
_drone setVariable ['CLDW_InspectionBuilding',objNull];
_drone setVariable ['CLDW_ProgressGoalASL',[]];
_drone limitSpeed false;
if (_deadline > time) exitWith {
    // An attack, player takeover, jammer, or watchdog already owns the next state.
    _drone setVariable ['CLDW_SearchUntil',0,true];
};
_drone setVariable ['CLDW_SearchUntil',0,true];
_drone setVariable ['CLDW_SearchLeg',[]];
_drone forceSpeed -1;
if (!alive _drone || {[_drone] call CLDW_fnc_getEWState} ||
    {[_drone] call CLDW_fnc_playerPiloting}) exitWith {};
_drone setVariable ['CLDW_Disengaged',true,true];
[_drone,'RETURN',[_drone,_center,_operator]] call CLDW_fnc_startController;
