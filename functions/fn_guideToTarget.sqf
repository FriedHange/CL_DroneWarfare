// Retain the public guidance signature used by DDT and other integrations.
private _drone = _this param [0, objNull];
[_drone, "GUIDE", _this] call CLDW_fnc_startController;
