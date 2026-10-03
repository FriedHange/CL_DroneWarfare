if (isNil "CLDW_controllers") then {CLDW_controllers = [];};
// Verified against Sania Workshop 3147611501, functions/fn_jammerInit.sqf.
// Its AI path kills crew and clears this transient flag immediately.
// The live-pilot guard below preserves that native outcome.
if (!isNil "DB_fnc_jammerInit") then {
    ["Sania", {params ["_drone"]; _drone getVariable ["DB_jammer_isUavJamming", false]}] call CLDW_fnc_registerEWAdapter;
};
// Verified against EW Drone Jammer 3804407201 (ew_core softJam/hardKill).
if (!isNil "EWDJ_fnc_softJam") then {
    ["EW Drone Jammer", {
        params ["_drone"];
        (_drone getVariable ["EWDJ_hardKilled", false]) ||
        {(_drone getVariable ["EWDJ_jamState", ""]) == "hard"} ||
        {((missionNamespace getVariable ["EWDJ_cfg", createHashMap]) getOrDefault ["affectAI", true]) &&
            {(_drone getVariable ["EWDJ_jamState", ""]) == "soft" ||
            {_drone getVariable ["CLDW_EWReturnPending", false]}}}
    }] call CLDW_fnc_registerEWAdapter;
    if (isServer) then {
        ["EWDJ_droneJammed", {
            params ["_drone", "_state"];
            if (_state == "soft") then {_drone setVariable ["CLDW_EWSoftSeen", true];};
            if (_state == "" && {_drone getVariable ["CLDW_EWSoftSeen", false]}) then {
                _drone setVariable ["CLDW_EWSoftSeen", false];
                private _cfg = missionNamespace getVariable ["EWDJ_cfg", createHashMap];
                private _home = _drone getVariable ["EWDJ_home", []];
                if ((_cfg getOrDefault ["affectAI", true]) && {_cfg getOrDefault ["softReturnHome", true]} &&
                    {count _home == 3} && {_drone distance2D _home > 30} &&
                    {!(_drone getVariable ["EWDJ_hardKilled", false])}) then {
                    _drone setVariable ["CLDW_EWReturnPending", true, true];
                    _drone setVariable ["CLDW_ControlIntent", [], true];
                    _drone setVariable ["CLDW_CurrentTarget", objNull, true];
                };
            };
        }] call CBA_fnc_addEventHandler;
    };
};
[{
    private _keep = [];
    {
        _x params ["_drone", "_handle"];
        if (!scriptDone _handle) then {
            private _invalid = isNull _drone || {!alive _drone} || {!local _drone};
            private _playerControl = false;
            if (!_invalid) then {
                _playerControl = [_drone] call CLDW_fnc_playerPiloting;
                _invalid = !alive driver _drone || {_playerControl} || {[_drone] call CLDW_fnc_getEWState};
            };
            if (_invalid) then {
                terminate _handle;
                if (!isNull _drone && {_handle isEqualTo (_drone getVariable ["CLDW_Controller", scriptNull])}) then {
private _firedEH = _drone getVariable ["CLDW_BomberFiredEH", -1];
if (_firedEH >= 0) then {
    _drone removeEventHandler ["Fired", _firedEH];
    _drone setVariable ["CLDW_BomberFiredEH", -1];
};
                };
                if (!isNull _drone && {local _drone}) then {
                    _drone setVariable ["ddtBusy", false, true];
                    _drone setVariable ["CLDW_Disengaged", false, true];
                    if (_playerControl) then {
                        _drone enableAI "PATH";
                        _drone setVariable ["CLDW_CurrentTarget", objNull, true];
                    };
                };
            } else {
                _keep pushBack _x;
            };
        };
    } forEach CLDW_controllers;
    CLDW_controllers = _keep;
}, 0.05] call CBA_fnc_addPerFrameHandler;
