// Payload eligibility only. Callers also check hostility, visibility and range.
params [['_drone',objNull],['_vehicle',objNull],['_isAP',false]];
if (isNull _vehicle || {!alive _vehicle} ||
    {!(_vehicle isKindOf 'LandVehicle' || {_vehicle isKindOf 'Ship'} ||
        {_vehicle isKindOf 'Air'} || {_vehicle isKindOf 'StaticWeapon'})} ||
    {(crew _vehicle findIf {alive _x}) < 0}) exitWith {false};
if (!_isAP) exitWith {true};

private _wheeled = _vehicle isKindOf 'Car' || {_vehicle isKindOf 'Truck'} ||
    {_vehicle isKindOf 'Motorcycle'} || {_vehicle isKindOf 'Wheeled_APC_F'};
private _class = toLower typeOf _vehicle;
// Stock tracked APCs inherit Tank rather than APC; addon BMPs commonly do too.
private _ifv = _vehicle isKindOf 'APC' || {'apc' in _class} ||
    {'ifv' in _class} || {'bmp' in _class};
if (_wheeled || {_ifv} || {_vehicle isKindOf 'Ship'} ||
    {_vehicle isKindOf 'Air'} || {_vehicle isKindOf 'StaticWeapon'}) exitWith {true};
// Keep main battle tanks for AT drones. Armor values alone are unreliable
// for distinguishing a tracked IFV from an MBT in addon vehicle configs.
if (_vehicle isKindOf 'Tank') exitWith {false};
private _armor = getNumber (configFile >> 'CfgVehicles' >> typeOf _vehicle >> 'armor');
_armor <= ((missionNamespace getVariable ['ddtSoftThreshold',100]) max 150)
