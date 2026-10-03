params [['_drone',objNull]];
if (isNull _drone) exitWith {false};
private _class = toLower typeOf _drone;
if ('_at' in _class || {'pg7' in _class}) exitWith {false};
('_ap' in _class) || {'rkg' in _class} || {'og7v' in _class} ||
    {'rc40' in _class} || {'rc-40' in _class} || {'_he' in _class} ||
    {'frag' in _class} || {'personnel' in _class} ||
    {'uafpv' in _class} || {'fpv' in _class}
