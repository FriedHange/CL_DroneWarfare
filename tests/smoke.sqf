
[] spawn {
    sleep 8;
    if (missionNamespace getVariable ["CLDW_SMOKE_ExpectHC",false]) then {
        private _deadline = time + 35;
        waitUntil {sleep 0.5; count (entities "HeadlessClient_F") > 0 || {time >= _deadline}};
    };
    private _failures = 0;
    private _check = {
        params ["_good","_label"];
        diag_log format ["CLDW_SMOKE %1 %2",["FAIL","PASS"] select _good,_label];
        if (!_good) then {_failures = _failures + 1;};
    };
    if (missionNamespace getVariable ["CLDW_SMOKE_BuildingOnly",false]) exitWith {
        private _group = createGroup [east,true];
        private _house = createVehicle ["Land_Cargo_House_V1_F",[1550,1200,0],[],0,"NONE"];
        private _positions = _house buildingPos -1;
        private _target = _group createUnit ["O_Soldier_F",_positions select 0,[],0,"NONE"];
        _target disableAI "MOVE";
        _target setPosATL (_positions select 0);
        private _drone = createVehicle ["B_Crocus_AP",[1585,1200,12],[],0,"FLY"];
        createVehicleCrew _drone;
        private _opGroup = createGroup [west,true];
        private _op = _opGroup createUnit ["B_Soldier_F",[1500,1100,0],[],0,"NONE"];
        _op disableAI "MOVE";
        _drone setVariable ["CLDW_CurrentOperator",_op,true];
        _drone setVariable ["CLDW_OperatorGroup",_opGroup,true];
        _drone setVariable ["CLDW_DroneSide",west,true];
        private _plan = [];
        CLDW_DebugRoutes = true;
        for "_bearing" from 0 to 330 step 30 do {
            private _base = getPosASLVisual _target;
            _drone setPosASL [(_base select 0) + (sin _bearing) * 35,
                (_base select 1) + (cos _bearing) * 35,(_base select 2) + 12];
            private _aim = [_drone,_target] call CLDW_fnc_visibleAimPoint;
            if !(_aim isEqualTo []) then {
                _plan = [_drone,_target,_aim] call CLDW_fnc_planAttack;
                diag_log format ["CLDW_SMOKE building bearing=%1 aim=%2 plan=%3",_bearing,_aim,_plan];
            };
            if !(_plan isEqualTo []) exitWith {};
        };
        CLDW_DebugRoutes = false;
        [_plan isEqualTo [],"Crocus refuses the cargo-house window when its hull cannot fit"] call _check;
        private _openRoute = false;
        {
            private _class = _x;
            if (isClass (configFile >> "CfgVehicles" >> _class)) then {
                private _structure = createVehicle [_class,[1800 + _forEachIndex * 250,1200,0],[],0,"NONE"];
                _structure setDir 37;
                private _interior = _structure modelToWorld [0,0,0];
                _interior set [2,1.2];
                _target setPosATL _interior;
                _target setVelocity [0,0,0];
                sleep 0.2;
                private _found = [];
                for "_bearing" from 0 to 330 step 30 do {
                    private _base = getPosASLVisual _target;
                    _drone setPosASL [(_base select 0) + (sin _bearing) * 45,
                        (_base select 1) + (cos _bearing) * 45,(_base select 2) + 8];
                    private _aim = [_drone,_target] call CLDW_fnc_visibleAimPoint;
                    if !(_aim isEqualTo []) then {
                        _found = [_drone,_target,_aim] call CLDW_fnc_planAttack;
                    };
                    if !(_found isEqualTo []) exitWith {};
                };
                diag_log format ["CLDW_SMOKE open building=%1 plan=%2 target=%3",_class,_found,getPosASLVisual _target];
                if !(_found isEqualTo []) then {_openRoute = true;};
                if (_class == "Land_Hangar_F" && {_found param [3,false]}) then {
                    [_drone,"GUIDE",[_drone,_target,0,0.1]] call CLDW_fnc_startController;
                    private _nearest = 1e9;
                    for "_sample" from 1 to 220 do {
                        sleep 0.1;
                        if (alive _drone) then {
                            _nearest = _nearest min (_drone distance _target);
                        };
                    };
                    diag_log format ["CLDW_SMOKE open building approach nearest=%1 droneAlive=%2 targetAlive=%3 phase=%4",
                        _nearest,alive _drone,alive _target,_drone getVariable ["CLDW_AttackPhase",-1]];
                    [_nearest < 3,"Crocus reaches close contact through a large opening"] call _check;
                    terminate (_drone getVariable ["CLDW_Controller",scriptNull]);
                };
                deleteVehicle _structure;
            };
        } forEach ["Land_Hangar_F"];
        [_openRoute,"Crocus finds a clear entry through an open large building"] call _check;
        diag_log format ["CLDW_SMOKE DONE failures=%1",_failures];
    };
    if (missionNamespace getVariable ["CLDW_SMOKE_SearchOnly",false]) exitWith {
        private _group = createGroup [west,true];
        private _op = _group createUnit ["B_Soldier_F",[1000,1000,0],[],0,"NONE"];
        _op disableAI "MOVE";
        for "_i" from 1 to 5 do {
            private _squadmate = _group createUnit ["B_Soldier_F",[1000+_i*2,1000,0],[],0,"NONE"];
            _squadmate disableAI "MOVE";
        };
        private _other = createVehicle ["B_KVN_AP_TI",[1040,1000,35],[],0,"FLY"];
        createVehicleCrew _other;
        _other setVariable ["CLDW_AI_Spawned",true,true];
        _other setVariable ["CLDW_CurrentOperator",_op,true];
        _other setVariable ["CLDW_OperatorGroup",_group,true];
        _other setVariable ["CLDW_DroneSide",west,true];
        CLDW_activeDrones pushBack _other;
        [_other] call CLDW_fnc_droneTick;
        sleep 8;
        {
            private _class = _x;
            private _search = createVehicle [_class,[1160,1000,40],[],0,"FLY"];
            createVehicleCrew _search;
            _search setVariable ["CLDW_AI_Spawned",true,true];
            _search setVariable ["CLDW_CurrentOperator",_op,true];
            _search setVariable ["CLDW_OperatorGroup",_group,true];
            _search setVariable ["CLDW_DroneSide",west,true];
            CLDW_activeDrones pushBack _search;
            private _start = getPosASLVisual _search;
            [_search,"SEARCH",[_search,_start,objNull,_op]] call CLDW_fnc_startController;
            sleep 12;
            private _pilotGroup = group driver _search;
            diag_log format ["CLDW_SMOKE %1 search movement=%2 speed=%3 height=%4 groupJoined=%5 waypoints=%6 forced=%7 leg=%8 fallback=%9",
                _class,round (_search distance2D _start),round (speed _search),round ((getPosATL _search) select 2),
                _pilotGroup == _group,count (waypoints _pilotGroup),getForcedSpeed _search,
                _search getVariable ["CLDW_SearchLeg",[]],_search getVariable ["CLDW_SearchFallback",false]];
            [_search distance2D _start > 8 && {abs (speed _search) <= 55},
                format ["%1 search moves slowly",_class]] call _check;
            if (_class == "B_KVN_AP_TI") then {
                [_search getVariable ["CLDW_SearchFallback",false],
                    "concurrent KVN is recovered without deleting it"] call _check;
            };
            terminate (_search getVariable ["CLDW_Controller",scriptNull]);
            {_search deleteVehicleCrew _x} forEach crew _search;
            deleteVehicle _search;
        } forEach ["B_KVN_AP_TI","B_UAFPV_AP","B_Crocus_AP"];
        private _enemyGroup = createGroup [east,true];
        private _enemy = _enemyGroup createUnit ["O_Soldier_F",[1320,1000,0],[],0,"NONE"];
        _enemy disableAI "MOVE";
        private _reacquire = createVehicle ["B_Crocus_AP",[1200,1000,35],[],0,"FLY"];
        createVehicleCrew _reacquire;
        _reacquire setVariable ["CLDW_CurrentOperator",_op,true];
        _reacquire setVariable ["CLDW_OperatorGroup",_group,true];
        _reacquire setVariable ["CLDW_DroneSide",west,true];
        _reacquire setDir 90;
        [_reacquire,"SEARCH",[_reacquire,getPosASLVisual _reacquire,_enemy,_op]] call CLDW_fnc_startController;
        private _attackDeadline = time + 5;
        waitUntil {sleep 0.1; ((_reacquire getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE" || {time >= _attackDeadline}};
        sleep 0.6;
        diag_log format ["CLDW_SMOKE search reacquisition intent=%1 forwardSpeed=%2 groundSpeed=%3 boostPending=%4 controllerDone=%5 targetAlive=%6",
            (_reacquire getVariable ["CLDW_ControlIntent",[]]) param [0,""],
            round (abs (speed _reacquire)),round (vectorMagnitude (velocity _reacquire) * 3.6),
            _reacquire getVariable ["CLDW_SearchAttackBoost",false],
            scriptDone (_reacquire getVariable ["CLDW_Controller",scriptNull]),alive _enemy];
        sleep 0.8;
        diag_log format ["CLDW_SMOKE search reacquisition after 1.4s groundSpeed=%1 intent=%2 controllerDone=%3",
            round (vectorMagnitude (velocity _reacquire) * 3.6),
            (_reacquire getVariable ["CLDW_ControlIntent",[]]) param [0,""],
            scriptDone (_reacquire getVariable ["CLDW_Controller",scriptNull])];
        [((_reacquire getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE" &&
            {vectorMagnitude (velocity _reacquire) * 3.6 <= 60} &&
            {!(_reacquire getVariable ["CLDW_SearchAttackBoost",false])},
            "visible infantry resumes controlled attack after search"] call _check;
        terminate (_reacquire getVariable ["CLDW_Controller",scriptNull]);
        {_reacquire deleteVehicleCrew _x} forEach crew _reacquire;
        deleteVehicle _reacquire;
        deleteVehicle _enemy;
        private _boarder = _enemyGroup createUnit ['O_Soldier_F',[1270,1100,0],[],0,'NONE'];
        private _escapeCar = createVehicle ['B_MRAP_01_F',[1270,1100,0],[],0,'NONE'];
        _boarder moveInDriver _escapeCar;
        private _pursuer = createVehicle ['B_Crocus_AP',[1160,1100,35],[],0,'FLY'];
        createVehicleCrew _pursuer;
        _pursuer setVariable ['CLDW_CurrentOperator',_op,true];
        _pursuer setVariable ['CLDW_OperatorGroup',_group,true];
        _pursuer setVariable ['CLDW_DroneSide',west,true];
        [_pursuer,'SEARCH',[_pursuer,getPosASLVisual _pursuer,_boarder,_op]] call CLDW_fnc_startController;
        private _boardDeadline = time + 5;
        waitUntil {sleep 0.1; (_pursuer getVariable ['CLDW_CurrentTarget',objNull]) == _escapeCar ||
            {time >= _boardDeadline}};
        [(_pursuer getVariable ['CLDW_CurrentTarget',objNull]) == _escapeCar &&
            {((_pursuer getVariable ['CLDW_ControlIntent',[]]) param [0,'']) == 'GUIDE'},
            'search follows a boarded soldier into an occupied AP-eligible vehicle'] call _check;
        terminate (_pursuer getVariable ['CLDW_Controller',scriptNull]);
        {_pursuer deleteVehicleCrew _x} forEach crew _pursuer;
        deleteVehicle _pursuer;
        deleteVehicle _escapeCar;
        deleteVehicle _boarder;
        private _turnTarget = _enemyGroup createUnit ["O_Soldier_F",[1520,1000,0],[],0,"NONE"];
        _turnTarget disableAI "MOVE";
        private _turnDrone = createVehicle ["B_Crocus_AP",[1400,1000,30],[],0,"FLY"];
        createVehicleCrew _turnDrone;
        _turnDrone setDir 270;
        _turnDrone setVariable ["CLDW_CurrentOperator",_op,true];
        _turnDrone setVariable ["CLDW_OperatorGroup",_group,true];
        _turnDrone setVariable ["CLDW_DroneSide",west,true];
        _turnDrone setVariable ["CLDW_SearchAttackBoost",true];
        [_turnDrone,"GUIDE",[_turnDrone,_turnTarget,0,0.1]] call CLDW_fnc_startController;
        sleep 0.3;
        [alive _turnDrone && {vectorMagnitude (velocity _turnDrone) * 3.6 < 45} &&
            {((getPosATL _turnDrone) select 2) > 10},
            "rear target triggers a slow level turn before boost"] call _check;
        sleep 2;
        diag_log format ["CLDW_SMOKE rear turn dir=%1 targetDir=%2 speed=%3 pos=%4 intent=%5 plan=%6",
            getDir _turnDrone,_turnDrone getDir _turnTarget,
            vectorMagnitude (velocity _turnDrone) * 3.6,getPosATL _turnDrone,
            (_turnDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""],
            _turnDrone getVariable ["CLDW_InitialAttackPlan",[]]];
        [alive _turnDrone && {abs (((_turnDrone getDir _turnTarget) - (getDir _turnDrone) + 540) mod 360 - 180) < 60},
            "drone points toward rear target without looping into ground"] call _check;
        terminate (_turnDrone getVariable ["CLDW_Controller",scriptNull]);
        {_turnDrone deleteVehicleCrew _x} forEach crew _turnDrone;
        deleteVehicle _turnDrone;
        deleteVehicle _turnTarget;
        private _memoryTarget = _enemyGroup createUnit ["O_Soldier_F",[2825,1000,0],[],0,"NONE"];
        _memoryTarget disableAI "MOVE";
        private _memoryDrone = createVehicle ["B_Crocus_AP",[2500,1000,30],[],0,"FLY"];
        createVehicleCrew _memoryDrone;
        _memoryDrone setVariable ["CLDW_CurrentOperator",_op,true];
        _memoryDrone setVariable ["CLDW_OperatorGroup",_group,true];
        _memoryDrone setVariable ["CLDW_DroneSide",west,true];
        private _oldStrikeSpeed = missionNamespace getVariable ["CLDW_Setting_DroneSpeed",150];
        missionNamespace setVariable ["CLDW_Setting_DroneSpeed",50];
        [_memoryDrone,"GUIDE",[_memoryDrone,_memoryTarget,0,0.1]] call CLDW_fnc_startController;
        sleep 0.6;
        private _firstSight = _memoryDrone getVariable ["CLDW_LastSeenTime",-100];
        private _screenMemory = createVehicle ["Land_Cargo_HQ_V1_F",[2826,1000,0],[],0,"NONE"];
        _memoryTarget setPosATL [2840,1000,0];
        sleep 2;
        private _remembered = _memoryDrone getVariable ["CLDW_LastSeenPosASL",[]];
        diag_log format ["CLDW_SMOKE memory first=%1 now=%2 visible=%3 remembered=%4 live=%5 intent=%6",
            _firstSight,_memoryDrone getVariable ["CLDW_LastSeenTime",-100],
            [_memoryDrone,_memoryTarget] call CLDW_fnc_hasVisualTarget,_remembered,
            getPosASLVisual _memoryTarget,_memoryDrone getVariable ["CLDW_ControlIntent",[]]];
        [_firstSight >= 0 && {!([_memoryDrone,_memoryTarget] call CLDW_fnc_hasVisualTarget)} &&
            {count _remembered == 3} &&
            {_remembered distance2D (getPosASLVisual _memoryTarget) > 8} &&
            {(_memoryDrone getVariable ["CLDW_LastSeenTime",-100]) == _firstSight} &&
            {((_memoryDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE"},
            "brief cover keeps pursuit on the confirmed position"] call _check;
        deleteVehicle _screenMemory;
        sleep 1.5;
        private _renewedSight = _memoryDrone getVariable ["CLDW_LastSeenTime",-100];
        [_renewedSight > _firstSight &&
            {((_memoryDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE"},
            "reappearance renews sight and the same attack"] call _check;
        _screenMemory = createVehicle ["Land_Cargo_HQ_V1_F",[2826,1000,0],[],0,"NONE"];
        sleep 11;
        private _searchIntent = _memoryDrone getVariable ["CLDW_ControlIntent",[]];
        diag_log format ["CLDW_SMOKE memory expiry seen=%1 now=%2 visible=%3 intent=%4 alive=%5",
            _memoryDrone getVariable ["CLDW_LastSeenTime",-100],time,
            [_memoryDrone,_memoryTarget] call CLDW_fnc_hasVisualTarget,_searchIntent,alive _memoryDrone];
        [_searchIntent param [0,""] == "SEARCH" &&
            {count ((_searchIntent param [1,[]]) param [1,[]]) == 3} &&
            {((_searchIntent param [1,[]]) param [1,[]]) distance2D
                (_memoryDrone getVariable ["CLDW_LastSeenPosASL",[]]) < 1},
            "ten seconds without sight starts search at the last confirmed location"] call _check;
        terminate (_memoryDrone getVariable ["CLDW_Controller",scriptNull]);
        {_memoryDrone deleteVehicleCrew _x} forEach crew _memoryDrone;
        deleteVehicle _memoryDrone;
        deleteVehicle _memoryTarget;
        deleteVehicle _screenMemory;
        missionNamespace setVariable ["CLDW_Setting_DroneSpeed",_oldStrikeSpeed];
        {
            private _class = _x;
            private _missX = 3100 + 150 * _forEachIndex;
            private _missTarget = _enemyGroup createUnit ["O_Soldier_F",[_missX,1000,0],[],0,"NONE"];
            _missTarget disableAI "MOVE";
            private _missDrone = createVehicle [_class,[_missX - 30,1000,5],[],0,"FLY"];
            createVehicleCrew _missDrone;
            _missDrone setDir 90;
            _missDrone setVelocity [15,0,0];
            _missDrone setVariable ["CLDW_CurrentOperator",_op,true];
            _missDrone setVariable ["CLDW_OperatorGroup",_group,true];
            _missDrone setVariable ["CLDW_DroneSide",west,true];
            [_missDrone,"GUIDE",[_missDrone,_missTarget,0,0.1]] call CLDW_fnc_startController;
            sleep 0.3;
            private _missAim = getPosASLVisual _missTarget;
            _missDrone setPosASL [(_missAim select 0) + 5,_missAim select 1,
                (getTerrainHeightASL _missAim) + 5];
            _missDrone setDir 90;
            _missDrone setVelocity [15,0,0];
            sleep 0.2;
            _missDrone setPosASL [(_missAim select 0) + 15,_missAim select 1,
                (getTerrainHeightASL _missAim) + 5];
            sleep 0.5;
            diag_log format ["CLDW_SMOKE %1 missed pass count=%2 intent=%3 target=%4 speed=%5",
                _class,_missDrone getVariable ["CLDW_MissedPassCount",0],
                _missDrone getVariable ["CLDW_ControlIntent",[]],
                _missDrone getVariable ["CLDW_CurrentTarget",objNull],
                vectorMagnitude (velocity _missDrone) * 3.6];
            [alive _missDrone && {_missDrone getVariable ["CLDW_MissedPassCount",0] > 0} &&
                {((_missDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE"} &&
                {(_missDrone getVariable ["CLDW_CurrentTarget",objNull]) == _missTarget},
                format ["%1 close miss keeps its target and turns for another pass",_class]] call _check;
            terminate (_missDrone getVariable ["CLDW_Controller",scriptNull]);
            {_missDrone deleteVehicleCrew _x} forEach crew _missDrone;
            deleteVehicle _missDrone;
            deleteVehicle _missTarget;
        } forEach ["B_Crocus_AP","B_KVN_AP_TI","B_UAFPV_AP"];
        private _tent = createVehicle ["Land_DeconTent_01_white_F",[1800,1000,0],[],0,"NONE"];
        private _tentDrone = createVehicle ["B_UAFPV_AP",[1800,1000,30],[],0,"FLY"];
        createVehicleCrew _tentDrone;
        _tentDrone setVariable ["CLDW_CurrentOperator",_op,true];
        _tentDrone setVariable ["CLDW_OperatorGroup",_group,true];
        _tentDrone setVariable ["CLDW_DroneSide",west,true];
        private _tentCenter = getPosASLVisual _tent;
        [_tentDrone,"SEARCH",[_tentDrone,_tentCenter,objNull,_op]] call CLDW_fnc_startController;
        private _lowest = 100;
        for "_sample" from 1 to 220 do {
            sleep 0.1;
            if (alive _tentDrone) then {_lowest = _lowest min ((getPosATL _tentDrone) select 2);};
        };
        diag_log format ["CLDW_SMOKE tent low=%1 alive=%2 distance=%3 shelter=%4 stage=%5",
            _lowest,alive _tentDrone,_tentDrone distance2D _tent,
            _tentDrone getVariable ["CLDW_BuildingSearch",false],
            _tentDrone getVariable ["CLDW_SearchLeg",[]]];
        [alive _tentDrone && {_lowest < 10} && {_tentDrone distance2D _tent < 55} &&
            {_tentDrone getVariable ["CLDW_BuildingSearch",false]},
            "decon tent search descends to inspect its openings"] call _check;
        terminate (_tentDrone getVariable ["CLDW_Controller",scriptNull]);
        {_tentDrone deleteVehicleCrew _x} forEach crew _tentDrone;
        deleteVehicle _tentDrone;
        deleteVehicle _tent;
        private _searchHouse = createVehicle ["Land_Cargo_House_V1_F",[1950,1000,0],[],0,"NONE"];
        private _houseDrone = createVehicle ["B_UAFPV_AP",[1950,1000,30],[],0,"FLY"];
        createVehicleCrew _houseDrone;
        _houseDrone setVariable ["CLDW_CurrentOperator",_op,true];
        _houseDrone setVariable ["CLDW_OperatorGroup",_group,true];
        _houseDrone setVariable ["CLDW_DroneSide",west,true];
        [_houseDrone,"SEARCH",[_houseDrone,getPosASLVisual _searchHouse,objNull,_op]] call CLDW_fnc_startController;
        private _houseLowest = 100;
        private _houseFastPass = false;
        for "_sample" from 1 to 220 do {
            sleep 0.1;
            if (alive _houseDrone) then {
                _houseLowest = _houseLowest min ((getPosATL _houseDrone) select 2);
                private _passSpeed = vectorMagnitude (velocity _houseDrone) * 3.6;
                if (_passSpeed >= 55 && {_passSpeed <= 70} &&
                    {_houseDrone getVariable ["CLDW_BuildingSearch",false]}) then {
                    _houseFastPass = true;
                };
            };
        };
        diag_log format ["CLDW_SMOKE house search low=%1 alive=%2 distance=%3 building=%4 leg=%5",
            _houseLowest,alive _houseDrone,_houseDrone distance2D _searchHouse,
            _houseDrone getVariable ["CLDW_BuildingSearch",false],
            _houseDrone getVariable ["CLDW_SearchLeg",[]]];
        [alive _houseDrone && {_houseLowest >= 4} && {_houseLowest < 9} &&
            {_houseDrone distance2D _searchHouse < 55} &&
            {_houseDrone getVariable ["CLDW_BuildingSearch",false]},
            "ordinary building receives a wide low perimeter search"] call _check;
        [_houseFastPass,"clear exterior building pass reaches 55-70 km/h"] call _check;
        private _outsidePos = _searchHouse getPos [30,_searchHouse getDir _houseDrone];
        private _outsideTarget = _enemyGroup createUnit ["O_Soldier_F",_outsidePos,[],0,"NONE"];
        _outsideTarget disableAI "MOVE";
        private _handoffDeadline = time + 7;
        waitUntil {
            sleep 0.1;
            ((_houseDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE" ||
                {time >= _handoffDeadline}
        };
        [alive _houseDrone &&
            {((_houseDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE"} &&
            {!scriptDone (_houseDrone getVariable ["CLDW_Controller",scriptNull])},
            "building-search drone acquires another enemy emerging outside"] call _check;
        terminate (_houseDrone getVariable ["CLDW_Controller",scriptNull]);
        {_houseDrone deleteVehicleCrew _x} forEach crew _houseDrone;
        deleteVehicle _houseDrone;
        deleteVehicle _outsideTarget;
        deleteVehicle _searchHouse;
        private _compoundFirst = createVehicle ["Land_Cargo_House_V1_F",[2180,1000,0],[],0,"NONE"];
        private _compoundSecond = createVehicle ["Land_Cargo_House_V1_F",[2208,1000,0],[],0,"NONE"];
        _compoundSecond setDir 37;
        private _compoundDrone = createVehicle ["B_UAFPV_AP",[2180,1000,30],[],0,"FLY"];
        createVehicleCrew _compoundDrone;
        _compoundDrone setVariable ["CLDW_CurrentOperator",_op,true];
        _compoundDrone setVariable ["CLDW_OperatorGroup",_group,true];
        _compoundDrone setVariable ["CLDW_DroneSide",west,true];
        private _compoundStart = time;
        [_compoundDrone,"SEARCH",[_compoundDrone,getPosASLVisual _compoundFirst,objNull,_op]] call CLDW_fnc_startController;
        private _facedBuilding = false;
        private _secondSelected = false;
        waitUntil {
            sleep 0.2;
            private _inspected = _compoundDrone getVariable ["CLDW_InspectionBuilding",objNull];
            if (!isNull _inspected && {_compoundDrone distance2D _inspected < 30}) then {
                private _toward = vectorNormalized [
                    (getPosASLVisual _inspected select 0) - (getPosASLVisual _compoundDrone select 0),
                    (getPosASLVisual _inspected select 1) - (getPosASLVisual _compoundDrone select 1),0];
                private _cameraDir = if (hasPilotCamera _compoundDrone) then {
                    _compoundDrone vectorModelToWorld (getPilotCameraDirection _compoundDrone)
                } else {vectorDirVisual _compoundDrone};
                _cameraDir set [2,0];
                if ((vectorNormalized _cameraDir) vectorDotProduct _toward > 0.6) then {
                    _facedBuilding = true;
                };
            };
            _secondSelected = _compoundSecond in (_compoundDrone getVariable ["CLDW_SearchVisitedBuildings",[]]);
            _secondSelected || {time - _compoundStart >= 57}
        };
        diag_log format ["CLDW_SMOKE compound first=%1 second=%2 visited=%3 facing=%4 elapsed=%5 stage=%6 radius=%7 goal=%8 pos=%9",
            _compoundFirst,_compoundSecond,
            _compoundDrone getVariable ["CLDW_SearchVisitedBuildings",[]],_facedBuilding,time - _compoundStart,
            _compoundDrone getVariable ["CLDW_InspectionStage",-1],
            _compoundDrone getVariable ["CLDW_InspectionRadius",-1],
            _compoundDrone getVariable ["CLDW_SearchLeg",[]],getPosATL _compoundDrone];
        [_secondSelected && {_compoundFirst in (_compoundDrone getVariable ["CLDW_SearchVisitedBuildings",[]])} &&
            {_compoundSecond in (_compoundDrone getVariable ["CLDW_SearchVisitedBuildings",[]])},
            "search inspects neighboring mission buildings once each"] call _check;
        [_facedBuilding,"search camera faces the building during its slow perimeter pass"] call _check;
        if (_secondSelected) then {
            private _compoundTarget = _enemyGroup createUnit ["O_Soldier_F",
                _compoundSecond getPos [25,_compoundSecond getDir _compoundDrone],[],0,"NONE"];
            _compoundTarget disableAI "MOVE";
            private _compoundHandoff = time + 7;
            waitUntil {
                sleep 0.1;
                ((_compoundDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE" ||
                    {time >= _compoundHandoff}
            };
            [((_compoundDrone getVariable ["CLDW_ControlIntent",[]]) param [0,""]) == "GUIDE",
                "drone acquires a target beside the second building"] call _check;
            deleteVehicle _compoundTarget;
        };
        terminate (_compoundDrone getVariable ["CLDW_Controller",scriptNull]);
        {_compoundDrone deleteVehicleCrew _x} forEach crew _compoundDrone;
        deleteVehicle _compoundDrone;
        deleteVehicle _compoundFirst;
        deleteVehicle _compoundSecond;
        private _house = createVehicle ["Land_Cargo_House_V1_F",[1550,1200,0],[],0,"NONE"];
        private _roomPositions = _house buildingPos -1;
        if !(_roomPositions isEqualTo []) then {
            private _roomTarget = _enemyGroup createUnit ["O_Soldier_F",_roomPositions select 0,[],0,"NONE"];
            _roomTarget disableAI "MOVE";
            _roomTarget setPosATL (_roomPositions select 0);
            private _entry = createVehicle ["B_Crocus_AP",[1585,1200,12],[],0,"FLY"];
            createVehicleCrew _entry;
            _entry setVariable ["CLDW_CurrentOperator",_op,true];
            _entry setVariable ["CLDW_OperatorGroup",_group,true];
            _entry setVariable ["CLDW_DroneSide",west,true];
            private _entryPlan = [];
            for "_bearing" from 0 to 330 step 30 do {
                private _base = getPosASLVisual _roomTarget;
                _entry setPosASL [(_base select 0) + (sin _bearing) * 35,
                    (_base select 1) + (cos _bearing) * 35,(_base select 2) + 12];
                private _point = [_entry,_roomTarget] call CLDW_fnc_visibleAimPoint;
                if !(_point isEqualTo []) then {
                    _entryPlan = [_entry,_roomTarget,_point] call CLDW_fnc_planAttack;
                };
                if !(_entryPlan isEqualTo []) exitWith {};
            };
            [_entryPlan isEqualTo [] || {
                (_entryPlan select 3) &&
                {[_entryPlan select 0,_entryPlan select 1,_entry,_roomTarget,0.35] call CLDW_fnc_clearFlightPath} &&
                {[_entryPlan select 1,_entryPlan select 2,_entry,_roomTarget,0.35] call CLDW_fnc_clearFlightPath}},
                "Crocus rejects a cargo-house entry unless the hull fits"] call _check;
            if !(_entryPlan isEqualTo []) then {
                [_entry,"GUIDE",[_entry,_roomTarget,0,0.1]] call CLDW_fnc_startController;
                private _nearest = 999;
                private _slowNear = false;
                for "_sample" from 1 to 220 do {
                    sleep 0.1;
                    if (alive _entry) then {
                        private _range = _entry distance _roomTarget;
                        _nearest = _nearest min _range;
                        if (_range < 25 && {abs (speed _entry) < 45}) then {_slowNear = true;};
                    };
                };
                diag_log format ["CLDW_SMOKE indoor Crocus nearest=%1 slowNear=%2 droneAlive=%3 targetAlive=%4 intent=%5 phase=%6 position=%7 speed=%8 target=%9",
                    _nearest,_slowNear,alive _entry,alive _roomTarget,
                    (_entry getVariable ["CLDW_ControlIntent",[]]) param [0,""],
                    _entry getVariable ["CLDW_AttackPhase",-1],getPosASLVisual _entry,
                    speed _entry,getPosASLVisual _roomTarget];
                [_slowNear && {(_nearest < 2.5) || {alive _entry && {_nearest < 15}}},
                    "Crocus enters or safely repositions after a slow building approach"] call _check;
            };
            if (alive _entry) then {terminate (_entry getVariable ["CLDW_Controller",scriptNull]);};
            {_entry deleteVehicleCrew _x} forEach crew _entry;
            deleteVehicle _entry;
            deleteVehicle _roomTarget;
        };
        deleteVehicle _house;
        private _returnDrone = createVehicle ["B_Crocus_AP",[2200,1200,25],[],0,"FLY"];
        createVehicleCrew _returnDrone;
        _returnDrone setVariable ["CLDW_CurrentOperator",_op,true];
        _returnDrone setVariable ["CLDW_OperatorGroup",_group,true];
        _returnDrone setVariable ["CLDW_DroneSide",west,true];
        private _returnStart = getPosASLVisual _returnDrone;
        [_returnDrone,"RETURN",[_returnDrone,_returnStart,_op]] call CLDW_fnc_startController;
        sleep 0.5;
        (driver _returnDrone) disableAI "PATH";
        _returnDrone disableAI "PATH";
        _returnDrone setVelocity [0,0,0];
        sleep 16;
        diag_log format ["CLDW_SMOKE Crocus return fallback=%1 movement=%2 distanceToOperator=%3 alive=%4",
            _returnDrone getVariable ["CLDW_ReturnFallback",false],
            _returnDrone distance2D _returnStart,_returnDrone distance2D _op,alive _returnDrone];
        [alive _returnDrone && {_returnDrone getVariable ["CLDW_ReturnFallback",false]} &&
            {_returnDrone distance2D _returnStart > 15} && {_returnDrone distance2D _op > 100},
            "stalled Crocus returns physically without teleporting"] call _check;
        terminate (_returnDrone getVariable ["CLDW_Controller",scriptNull]);
        {_returnDrone deleteVehicleCrew _x} forEach crew _returnDrone;
        deleteVehicle _returnDrone;
        diag_log format ["CLDW_SMOKE DONE failures=%1",_failures];
    };
    [!isNil "CLDW_fnc_droneLoop" && {!isNil "CLDW_fnc_assignSquad"} &&
        {!isNil "CLDW_fnc_initRuntime"}, "addon functions registered"] call _check;
    [!isNil "DB_fnc_jammerInit" && {!isNil "EWDJ_fnc_softJam"},
        "both installed EW providers loaded"] call _check;
    if (missionNamespace getVariable ["CLDW_SMOKE_ExpectHC",false]) then {
        [count (entities "HeadlessClient_F") > 0, "HC is connected"] call _check;
    };
    private _adapters = missionNamespace getVariable ["CLDW_ewAdapters", createHashMap];
    ["Sania" in keys _adapters && {"EW Drone Jammer" in keys _adapters},
        "both EW adapters registered at postInit"] call _check;
    CLDW_Setting_DroneSpawnChance = 100;
    CLDW_Setting_ReplaceBackpacks = false;
    CLDW_Setting_MinSquadSize = 4;
    CLDW_Setting_MaxActiveGlobal = 12;
    CLDW_Setting_MaxActiveWest = 6;
    CLDW_Setting_ExcludePlayerGroup = false;
    if (missionNamespace getVariable ["CLDW_SMOKE_ExtraFPV",false]) then {
        CLDW_Mod_Crocus = false;
        CLDW_Mod_UAFPV_Tom = false;
        CLDW_Mod_UAFPV_BIG = false;
        CLDW_Mod_KVN = true;
    };
    private _pool = [west] call CLDW_fnc_getDronePools;
    [count (_pool select 2) > 0, "enabled FPV backpack class pool is populated"] call _check;
    private _g = createGroup [west,true];
    for "_i" from 0 to 5 do {
        private _u = _g createUnit ["B_Soldier_F", [1000+_i*2,1000,0], [], 0, "NONE"];
        _u disableAI "MOVE";
        _u addBackpack "B_AssaultPack_mcamo";
    };
    [_g] call CLDW_fnc_assignSquad;
    sleep 1;
    private _ops = _g getVariable ["CLDW_SupplyOperators", []];
    [count _ops >= 1 && {count _ops <= 2}, "addon allocates configured operator count"] call _check;
    if !(_ops isEqualTo []) then {
        private _op = _ops select 0;
        private _before = _op getVariable ["CLDW_Stock",0];
        [_op] call CLDW_fnc_deploy;
        sleep 1;
        private _drone = _op getVariable ["CLDW_ActiveDrone",objNull];
        [!isNull _drone && {(_op getVariable ["CLDW_Stock",0]) == _before-1},
            "packaged addon creates and accounts for drone"] call _check;
        if (!isNull _drone) then {
            sleep 2;
            private _idleWp = _drone getVariable ["CLDW_LoiterWaypoint", []];
            private _scriptedIdle = !scriptDone (_drone getVariable ["CLDW_IdleHandle",scriptNull]);
            [_drone getVariable ["CLDW_LoiterActive",false] && {!_scriptedIdle} &&
                {count _idleWp > 0 && {waypointType _idleWp == "MOVE"}},
                "deployed drone receives a native idle patrol order"] call _check;
            private _idleStart = getPosATL _drone;
            sleep 8;
            diag_log format ["CLDW_SMOKE idle movement=%1m speed=%2kmh scripted=%3 waypoint=%4", round (_drone distance2D _idleStart), round (speed _drone),_scriptedIdle,if (count _idleWp > 0) then {waypointType _idleWp} else {"none"}];
            [_drone distance2D _idleStart > 10, "deployed drone actually moves while idle"] call _check;
            if (missionNamespace getVariable ["CLDW_SMOKE_ExpectHC",false]) then {
                [owner _drone == 2, "connected idle HC does not seize newly created drone"] call _check;
                private _hc = (entities "HeadlessClient_F") param [0,objNull];
                if (!isNull _hc) then {
                    private _owner = owner _hc;
                    private _grp = group driver _drone;
                    _grp setGroupOwner _owner;
                    sleep 2;
                    [owner _drone == _owner, "explicit HC group transfer moves drone ownership"] call _check;
                    [_drone] remoteExecCall ["CLDW_fnc_droneTick", _drone];
                    sleep 2;
                    [_drone getVariable ["CLDW_CollisionOwner",-1] == _owner, "HC runs owner-local drone tick"] call _check;
                    _grp setGroupOwner 2;
                    sleep 2;
                    [owner _drone == 2, "drone returns to server after HC ownership transfer"] call _check;
                };
            };
            _drone setVariable ["DB_jammer_isUavJamming",true];
            _drone setVariable ["CLDW_EWCache",[-1,false]];
            [[_drone] call CLDW_fnc_getEWState, "Sania hook suppresses packaged drone"] call _check;
            _drone setVariable ["DB_jammer_isUavJamming",false];
            _drone setVariable ["EWDJ_jamState","soft"];
            _drone setVariable ["CLDW_EWCache",[-1,false]];
            [[_drone] call CLDW_fnc_getEWState, "EW Drone Jammer hook suppresses packaged drone"] call _check;
            _drone setVariable ["EWDJ_jamState",""];
            _drone setVariable ["CLDW_EWCache",[-1,false]];
            private _opPos = getPosATL _op;
            _drone setPosATL [(_opPos select 0) + 120, _opPos select 1, 35];
            _drone setVariable ["CLDW_Disengaged",true,true];
            [_drone] call CLDW_fnc_droneTick;
            private _returnDeadline = time + 50;
            waitUntil {sleep 0.5; !alive _drone || {_drone distance2D _op <= 35} || {time >= _returnDeadline}};
            [alive _drone && {_drone distance2D _op <= 35},
                "disengaged drone returns within 35m of its squad"] call _check;
        };
    };
    if (missionNamespace getVariable ["CLDW_SMOKE_ExtraFPV",false] && {!(_ops isEqualTo [])}) then {
        private _variantOp = _ops select 0;
        {
            private _class = _x;
            private _variant = createVehicle [_class, (getPosATL _variantOp) vectorAdd [40 + 30 * _forEachIndex,0,35], [], 0, "FLY"];
            createVehicleCrew _variant;
            _variant setVariable ["CLDW_CurrentOperator",_variantOp,true];
            _variant setVariable ["CLDW_OperatorGroup",group _variantOp,true];
            _variant setVariable ["CLDW_DroneSide",west,true];
            _variant setVariable ['CLDW_AI_Spawned',true,true];
            CLDW_activeDrones pushBack _variant;
            [_variant] call CLDW_fnc_droneTick;
            sleep 2;
            private _first = getPosATL _variant;
            private _idleDeadline = time + 55;
            waitUntil {
                sleep 1;
                if (alive _variant) then {[_variant] call CLDW_fnc_droneTick;};
                !alive _variant || {_variant distance2D _first > 10} || {time >= _idleDeadline}
            };
            private _movement = _variant distance2D _first;
            private _wp = _variant getVariable ["CLDW_LoiterWaypoint",[]];
            diag_log format ["CLDW_SMOKE %1 idle movement=%2m speed=%3kmh loiter=%4 waypoint=%5 waypoints=%6 driver=%7 engine=%8 fuel=%9",_class,round _movement,round (speed _variant),_variant getVariable ["CLDW_LoiterActive",false],if (count _wp > 0) then {waypointType _wp} else {"none"},count (waypoints group driver _variant),alive driver _variant,isEngineOn _variant,fuel _variant];
            [alive _variant && {_movement > 10} &&
                {_variant getVariable ['CLDW_LoiterActive',false]} &&
                {scriptDone (_variant getVariable ['CLDW_IdleHandle',scriptNull])},
                format ["%1 moves under native loiter after bounded recovery",_class]] call _check;
            if (_class == "B_KVN_AP_TI" && {alive _variant}) then {
                private _enemyGroup = createGroup [east,true];
                private _enemy = _enemyGroup createUnit ["O_Soldier_F",(getPosATL _variant) vectorAdd [300,0,0],[],0,"NONE"];
                _enemy disableAI "MOVE";
                _variant setVariable ["CLDW_CurrentTarget",_enemy,true];
                [_variant] call CLDW_fnc_droneTick;
                private _intent = _variant getVariable ["CLDW_ControlIntent",[]];
                [scriptDone (_variant getVariable ["CLDW_IdleHandle",scriptNull]) && {_intent param [0,""] == "GUIDE"},
                    "KVN leaves idle orbit to attack infantry without joining its squad"] call _check;
                terminate (_variant getVariable ["CLDW_Controller",scriptNull]);
                deleteVehicle _enemy;
            };
            {_variant deleteVehicleCrew _x} forEach crew _variant;
            deleteVehicle _variant;
            CLDW_activeDrones = CLDW_activeDrones - [_variant];
        } forEach ["B_KVN_AP_TI","B_UAFPV_AP"];
        // A genuinely frozen, crewed FPV must not hold a low global cap forever.
        {_x setVariable ["CLDW_Stock",0,true]} forEach _ops;
        CLDW_deployQueue = [];
        private _oldCap = CLDW_Setting_MaxActiveGlobal;
        {
            private _frozenClass = _x;
            private _squadWp = (group _variantOp) addWaypoint [getPosATL _variantOp,0];
            _squadWp setWaypointType "MOVE";
            private _frozen = createVehicle [_frozenClass,(getPosATL _variantOp) vectorAdd [180,0,5],[],0,"FLY"];
            createVehicleCrew _frozen;
            _frozen setVariable ["CLDW_AI_Spawned",true,true];
            _frozen setVariable ["CLDW_CurrentOperator",_variantOp,true];
            _frozen setVariable ["CLDW_OperatorGroup",group _variantOp,true];
            _frozen setVariable ["CLDW_DroneSide",west,true];
            CLDW_activeDrones pushBack _frozen;
            CLDW_Setting_MaxActiveGlobal = {(!isNull _x) && {alive _x} && {_x getVariable ["CLDW_AI_Spawned",false]}} count CLDW_activeDrones;
            [!([west] call CLDW_fnc_canLaunch),format ["frozen %1 initially fills the global cap",_frozenClass]] call _check;
            // Scripted return can move a hull even with simulation disabled.
            // Pin the physical position to model a genuinely immobile UAV.
            private _frozenPos = getPosASL _frozen;
            private _originalPilot = driver _frozen;
            private _holdFrozen = [_frozen,_frozenPos] spawn {
                params ["_uav","_pos"];
                while {!isNull _uav} do {
                    _uav setPosASL _pos;
                    _uav setVelocity [0,0,0];
                    sleep 0.01;
                };
            };
            private _stallDeadline = time + 60;
            waitUntil {
                sleep 1;
                (!isNull _frozen && {_frozen getVariable ["CLDW_RecoveryJoined",false]} &&
                    {group (driver _frozen) == group _variantOp}) ||
                {time >= _stallDeadline}
            };
            terminate _holdFrozen;
            CLDW_Setting_MaxActiveGlobal = {(!isNull _x) && {alive _x} && {_x getVariable ["CLDW_AI_Spawned",false]}} count CLDW_activeDrones;
            [!isNull _frozen && {alive _frozen} && {_frozen in CLDW_activeDrones} && {!([west] call CLDW_fnc_canLaunch)},
                format ["stalled %1 retains the same drone and cap slot",_frozenClass]] call _check;
            [!isNull _frozen && {_frozen getVariable ["CLDW_RecoveryJoined",false]} &&
                {group (driver _frozen) == group _variantOp} &&
                {driver _frozen != _originalPilot} &&
                {_frozen distance2D _frozenPos < 8} &&
                {_frozen distance2D _variantOp > 100},
                format ["stalled %1 replaces its pilot and joins its squad in place",_frozenClass]] call _check;
            private _releasedPos = getPosASLVisual _frozen;
            private _moveDeadline = time + 8;
            waitUntil {sleep 0.5; (isNull _frozen || {_frozen distance2D _releasedPos > 8}) || {time >= _moveDeadline}};
            [!isNull _frozen && {_frozen distance2D _releasedPos > 8},
                format ["repaired %1 resumes flight",_frozenClass]] call _check;
            [_squadWp in (waypoints (group _variantOp)),
                format ["repaired %1 preserves infantry squad waypoints",_frozenClass]] call _check;
            deleteWaypoint _squadWp;
            if (!isNull _frozen) then {
                {_frozen deleteVehicleCrew _x} forEach crew _frozen;
                deleteVehicle _frozen;
            };
        } forEach ["B_KVN_AP_TI","B_UAFPV_AP"];
        CLDW_Setting_MaxActiveGlobal = _oldCap;
        private _search = createVehicle ["B_KVN_AP_TI",(getPosATL _variantOp) vectorAdd [160,0,40],[],0,"FLY"];
        createVehicleCrew _search;
        _search setVariable ["CLDW_AI_Spawned",true,true];
        _search setVariable ["CLDW_CurrentOperator",_variantOp,true];
        _search setVariable ["CLDW_OperatorGroup",group _variantOp,true];
        _search setVariable ["CLDW_DroneSide",west,true];
        CLDW_activeDrones pushBack _search;
        private _searchStart = getPosASLVisual _search;
        private _searchStarted = time;
        [_search,"SEARCH",[_search,_searchStart,objNull,_variantOp]] call CLDW_fnc_startController;
        sleep 12;
        private _searchAGL = (getPosATL _search) select 2;
        diag_log format ["CLDW_SMOKE AI search movement=%1m AGL=%2m speed=%3kmh until=%4 now=%5 intent=%6 groupJoined=%7 waypoints=%8 forced=%9 leg=%10 operatorAlive=%11",
            round (_search distance2D _searchStart),round _searchAGL,round (speed _search),
            _search getVariable ["CLDW_SearchUntil",0],time,
            (_search getVariable ["CLDW_ControlIntent",[]]) param [0,""],
            group driver _search == group _variantOp,count (waypoints group driver _search),
            getForcedSpeed _search,_search getVariable ["CLDW_SearchLeg",[]],alive _variantOp];
        [!isNull _search && {_search distance2D _searchStart > 8} &&
            {_searchAGL >= 15} && {_searchAGL <= 55} &&
            {abs (speed _search) <= 55} &&
            {!((_search getVariable ["CLDW_SearchLeg",[]]) isEqualTo [])} &&
            {_search getVariable ["CLDW_SearchUntil",0] >= _searchStarted + 59},
            "lost-target KVN searches slowly for one minute"] call _check;
        private _searchDeadline = time + 52;
        waitUntil {sleep 1; isNull _search || {_search getVariable ["CLDW_SearchUntil",-1] == 0} || {time >= _searchDeadline}};
        [!isNull _search && {_search getVariable ["CLDW_SearchUntil",-1] == 0} &&
            {_search getVariable ["CLDW_Disengaged",false] ||
                {(_search getVariable ["CLDW_ControlIntent",[]]) param [0,""] == "RETURN"}},
            "60-second search ends with a return order"] call _check;
        if (!isNull _search) then {
            terminate (_search getVariable ["CLDW_Controller",scriptNull]);
            {_search deleteVehicleCrew _x} forEach crew _search;
            deleteVehicle _search;
        };
    };
    // A deleted or dead assigned AI operator must retire the aircraft even if
    // another squad member exists and its current-controller field changed.
    {
        private _lossMode = _x;
        private _orphanGroup = createGroup [west,true];
        private _assigned = _orphanGroup createUnit ["B_Soldier_F",[2400,1000,0],[],0,"NONE"];
        private _teammate = _orphanGroup createUnit ["B_Soldier_F",[2402,1000,0],[],0,"NONE"];
        _assigned disableAI "MOVE";
        _teammate disableAI "MOVE";
        _assigned setVariable ["CLDW_Stock",0,true];
        _teammate setVariable ["CLDW_Stock",0,true];
        private _orphan = createVehicle ["B_Crocus_AP",[2480,1000,35],[],0,"FLY"];
        createVehicleCrew _orphan;
        _orphan setVariable ["CLDW_AI_Spawned",true,true];
        _orphan setVariable ["CLDW_OperatorBound",true,true];
        _orphan setVariable ["CLDW_AssignedOperator",_assigned,true];
        _orphan setVariable ["CLDW_CurrentOperator",_teammate,true];
        _orphan setVariable ["CLDW_OperatorGroup",_orphanGroup,true];
        _orphan setVariable ["CLDW_DroneSide",west,true];
        CLDW_activeDrones pushBack _orphan;
        private _originalPilot = driver _orphan;
        private _target = objNull;
        if (_lossMode == "death") then {
            private _enemyGroup = createGroup [east,true];
            _target = _enemyGroup createUnit ["O_Soldier_F",[2700,1000,0],[],0,"NONE"];
            _target disableAI "MOVE";
            _target disableAI "TARGET";
            _target setVariable ["CLDW_AssignedDrone",_orphan,true];
            _orphan setVariable ["CLDW_CurrentTarget",_target,true];
            [_orphan,"GUIDE",[_orphan,_target,0,0.1]] call CLDW_fnc_startController;
        } else {
            [_orphan,"SEARCH",[_orphan,getPosASLVisual _orphan,objNull,_assigned]] call CLDW_fnc_startController;
        };
        sleep 0.4;
        if (_lossMode == "despawn" && {missionNamespace getVariable ["CLDW_SMOKE_ExpectHC",false]}) then {
            private _hc = (entities "HeadlessClient_F") param [0,objNull];
            if (!isNull _hc) then {
                (group driver _orphan) setGroupOwner (owner _hc);
                sleep 1;
                [owner _orphan == owner _hc,
                    "orphan fixture transfers drone to HC before operator despawn"] call _check;
            };
        };
        if (_lossMode == "death") then {_assigned setDamage 1} else {deleteVehicle _assigned};
        private _retireDeadline = time + 6;
        waitUntil {sleep 0.2; _orphan getVariable ["CLDW_OrphanFinalized",false] || {time >= _retireDeadline}};
        [_orphan getVariable ["CLDW_OrphanFinalized",false] &&
            {!alive _originalPilot} && {alive _orphan} &&
            {!(_orphan in CLDW_activeDrones)} &&
            {_lossMode != "death" || {_assigned getVariable ["CLDW_Stock",0] == 0}} &&
            {_teammate getVariable ["CLDW_Stock",0] == 0} &&
            {isNull _target || {_target getVariable ["CLDW_AssignedDrone",objNull] != _orphan}},
            format ["%1 of assigned operator retires crew, clears target and cap without refund",_lossMode]] call _check;
        sleep 1.5;
        [!alive driver _orphan && {alive _orphan},
            format ["%1 does not revive orphaned pilot",_lossMode]] call _check;
        if (!isNull _orphan) then {
            {_orphan deleteVehicleCrew _x} forEach crew _orphan;
            deleteVehicle _orphan;
        };
        if (!isNull _target) then {deleteVehicle _target;};
        if (!isNull _teammate) then {deleteVehicle _teammate;};
        if (!isNull _assigned) then {deleteVehicle _assigned;};
    } forEach ["death","despawn"];
    diag_log format ["CLDW_SMOKE DONE failures=%1",_failures];
};
