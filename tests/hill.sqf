[] spawn {
    sleep 8;
    private _failures = 0;
    private _check = {
        params ["_ok","_name"];
        diag_log format ["CLDW_SMOKE %1 %2",["FAIL","PASS"] select _ok,_name];
        if (!_ok) then {_failures = _failures + 1;};
    };
    private _from = [];
    private _to = [];
    for "_mapX" from 5000 to 17000 step 400 do {
        if !(_from isEqualTo []) exitWith {};
        for "_mapY" from 5000 to 17000 step 400 do {
            if !(_from isEqualTo []) exitWith {};
            private _startH = getTerrainHeightASL [_mapX,_mapY];
            {
                private _direction = _x;
                private _end = [_mapX + (_direction select 0) * 80,_mapY + (_direction select 1) * 80];
                private _mid = [_mapX + (_direction select 0) * 40,_mapY + (_direction select 1) * 40];
                private _endH = getTerrainHeightASL _end;
                if (_startH > 1 && {_endH - _startH > 16} &&
                    {(getTerrainHeightASL _mid) - _startH > 10} &&
                    {!surfaceIsWater [_mapX,_mapY]} && {!surfaceIsWater _end} &&
                    {(nearestObjects [[_mapX,_mapY,0],["House"],30]) isEqualTo []} &&
                    {(nearestObjects [[_end select 0,_end select 1,0],["House"],30]) isEqualTo []}) exitWith {
                    _from = [_mapX,_mapY,_startH];
                    _to = [_end select 0,_end select 1,_endH];
                };
            } forEach [[1,0],[0,1],[-1,0],[0,-1]];
        };
    };
    [!(_from isEqualTo []),"Altis fixture finds a rising open hillside"] call _check;
    if !(_from isEqualTo []) then {
        private _start = [_from select 0,_from select 1,(_from select 2) + 6];
        private _ridge = [_start,_to,15,3] call CLDW_fnc_terrainLookahead;
        [(_ridge select 0) > (_start select 2) + 2,
            "terrain lookahead detects rising ground before the target"] call _check;
        private _friends = createGroup [west,true];
        private _op = _friends createUnit ["B_Soldier_F",[_from select 0,(_from select 1) - 20,0],[],0,"NONE"];
        _op disableAI "MOVE";
        private _enemyGroup = createGroup [east,true];
        private _target = createVehicle ["B_MRAP_01_F",[_to select 0,_to select 1,0],[],0,"NONE"];
        private _driver = _enemyGroup createUnit ["O_Soldier_F",[_to select 0,_to select 1,0],[],0,"NONE"];
        _driver moveInDriver _target;
        _driver disableAI "MOVE";
        _driver disableAI "TARGET";
        private _drone = createVehicle ["B_Crocus_AP",[_from select 0,_from select 1,6],[],0,"FLY"];
        createVehicleCrew _drone;
        _drone setPosASL _start;
        _drone setDir (_drone getDir _target);
        _drone setVariable ["CLDW_CurrentOperator",_op,true];
        _drone setVariable ["CLDW_OperatorGroup",_friends,true];
        _drone setVariable ["CLDW_DroneSide",west,true];
        private _initial = getPosASLVisual _drone;
        private _last = _initial;
        private _maxStep = 0;
        private _maxUp = 0;
        [_drone,"GUIDE",[_drone,_target,0,0.1]] call CLDW_fnc_startController;
        for "_sample" from 1 to 45 do {
            sleep 0.1;
            if (isNull _drone || {!alive _drone}) exitWith {};
            private _now = getPosASLVisual _drone;
            _maxStep = _maxStep max (_now distance _last);
            _maxUp = _maxUp max ((velocity _drone) select 2);
            _last = _now;
        };
        diag_log format ["CLDW_SMOKE hill from=%1 actualStart=%2 to=%3 ridge=%4 maxStep=%5 maxUp=%6 traveled=%7 avoiding=%8 intent=%9",
            _from,_initial,_to,_ridge,_maxStep,_maxUp,_drone distance2D _from,
            _drone getVariable ["CLDW_TerrainAvoidSeen",false],
            (_drone getVariable ["CLDW_ControlIntent",[]]) param [0,""]];
        [_drone getVariable ["CLDW_TerrainAvoidSeen",false] &&
            {_drone distance2D _from > 3} && {_maxStep < 3} && {_maxUp <= 6},
            "hillside pursuit climbs ahead smoothly without an upward jump"] call _check;
        if (!isNull _drone) then {
            terminate (_drone getVariable ["CLDW_Controller",scriptNull]);
            {_drone deleteVehicleCrew _x} forEach crew _drone;
            deleteVehicle _drone;
        };
        _op setPosATL [_to select 0,_to select 1,0];
        private _return = createVehicle ["B_KVN_AP_TI",[_from select 0,_from select 1,6],[],0,"FLY"];
        createVehicleCrew _return;
        _return setPosASL _start;
        _return setVariable ["CLDW_CurrentOperator",_op,true];
        _return setVariable ["CLDW_OperatorGroup",_friends,true];
        _return setVariable ["CLDW_DroneSide",west,true];
        private _returnLast = getPosASLVisual _return;
        private _returnMaxStep = 0;
        private _returnMaxUp = 0;
        private _returnMaxCommand = 0;
        [_return,"RETURN",[_return,_returnLast,_op]] call CLDW_fnc_startController;
        for "_sample" from 1 to 45 do {
            sleep 0.1;
            if (isNull _return || {!alive _return}) exitWith {};
            private _now = getPosASLVisual _return;
            _returnMaxStep = _returnMaxStep max (_now distance _returnLast);
            _returnMaxUp = _returnMaxUp max ((velocity _return) select 2);
            _returnMaxCommand = _returnMaxCommand max (_return getVariable ["CLDW_ReturnCommandedUp",0]);
            _returnLast = _now;
        };
        diag_log format ["CLDW_SMOKE hill return traveled=%1 maxStep=%2 maxUp=%3 commandedUp=%4 fallback=%5",
            _return distance2D _from,_returnMaxStep,_returnMaxUp,_returnMaxCommand,
            _return getVariable ["CLDW_ReturnFallback",false]];
        [_return distance2D _from > 3 && {_returnMaxStep < 3} &&
            {_returnMaxUp <= 8} && {_returnMaxCommand <= 4.5} && {_returnMaxCommand > 0},
            "hillside return keeps moving while climbing without a vertical kick"] call _check;
        if (!isNull _return) then {
            terminate (_return getVariable ["CLDW_Controller",scriptNull]);
            {_return deleteVehicleCrew _x} forEach crew _return;
            deleteVehicle _return;
        };
        deleteVehicle _target;
        deleteVehicle _driver;
        deleteVehicle _op;
    };
    diag_log format ["CLDW_SMOKE DONE failures=%1",_failures];
};
