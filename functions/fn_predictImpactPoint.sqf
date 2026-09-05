/*
    Returns an ASL aim point for direct or predictive terminal guidance.
*/
params [
    ["_drone", objNull],
    ["_target", objNull],
    ["_droneSpeed", 1],
    ["_fastTargetThreshold", 80],
    ["_leadOffset", 1],
    ["_predictionTimeCap", 2.5],
    ["_vehicleAimHeightOffset", 0.0]
];

if (isNull _drone || {isNull _target}) exitWith { [0, 0, 0] };

private _targetVehicle = vehicle _target;
private _targetPos = AGLToASL (_targetVehicle modelToWorldVisual (boundingCenter _targetVehicle));

// Aim at vehicle center of mass (bounding center) clamped above ground level
if !(_target isKindOf "CAManBase") then {
    private _targetTerrainH = getTerrainHeightASL _targetPos;
    private _adjustedZ = ((_targetPos select 2) + _vehicleAimHeightOffset) max (_targetTerrainH + 0.8);
    _targetPos set [2, _adjustedZ];
};

if (_target isKindOf "CAManBase" || {abs speed _targetVehicle < _fastTargetThreshold}) exitWith {
    _targetPos
};

private _targetVelocity = velocity _targetVehicle;
private _velocityMagnitude = vectorMagnitude _targetVelocity;
if (_velocityMagnitude < 0.1) exitWith { _targetPos };

private _distance = (getPosASLVisual _drone) distance _targetPos;
private _timeToImpact = (_distance / (_droneSpeed max 1)) min (_predictionTimeCap max 0);
private _velocityLead = _targetVelocity vectorMultiply _timeToImpact;
private _forwardLead = (vectorNormalized _targetVelocity) vectorMultiply (_leadOffset max 0);

(_targetPos vectorAdd _velocityLead) vectorAdd _forwardLead
