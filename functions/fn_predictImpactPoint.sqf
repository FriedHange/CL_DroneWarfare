/*
    Returns an ASL aim point for direct or predictive terminal guidance.
*/
params [
    ["_drone", objNull],
    ["_target", objNull],
    ["_droneSpeed", 1],
    ["_fastTargetThreshold", 5],
    ["_leadOffset", 1.2],
    ["_predictionTimeCap", 2.5],
    ["_vehicleAimHeightOffset", 0.2]
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

private _targetVelocity = velocity _targetVehicle;
private _velocityMagnitude = vectorMagnitude _targetVelocity;

// Exit with current center position if target is infantry walking slowly or stationary vehicle
if (_target isKindOf "CAManBase") then {
    if (abs speed _targetVehicle < 15) exitWith { _targetPos };
} else {
    if (abs speed _targetVehicle < _fastTargetThreshold || {_velocityMagnitude < 0.3}) exitWith { _targetPos };
};

// Calculate exact quadratic time-to-intercept for moving target
private _dronePos = getPosASLVisual _drone;
private _relPos = _targetPos vectorDiff _dronePos;
private _droneSpeedVal = _droneSpeed max 1;
private _droneSpeedSqr = _droneSpeedVal * _droneSpeedVal;
private _targetSpeedSqr = _targetVelocity vectorDotProduct _targetVelocity;
private _timeToImpact = 0;

if (_targetSpeedSqr > 0.25) then {
    private _a = _droneSpeedSqr - _targetSpeedSqr;
    private _b = -2 * (_relPos vectorDotProduct _targetVelocity);
    private _c = -(_relPos vectorDotProduct _relPos);
    if (_a > 1) then {
        private _disc = (_b * _b) - (4 * _a * _c);
        if (_disc >= 0) then {
            _timeToImpact = ((-_b + sqrt _disc) / (2 * _a)) max 0;
        };
    };
};
if (_timeToImpact <= 0) then {
    _timeToImpact = (_dronePos distance _targetPos) / _droneSpeedVal;
};

_timeToImpact = (_timeToImpact min (_predictionTimeCap max 0)) max 0;
private _velocityLead = _targetVelocity vectorMultiply _timeToImpact;
private _forwardLead = (vectorNormalized _targetVelocity) vectorMultiply (_leadOffset max 0);

(_targetPos vectorAdd _velocityLead) vectorAdd _forwardLead
