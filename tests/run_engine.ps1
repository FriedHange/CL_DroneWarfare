param(
    [Parameter(Mandatory=$true)][string]$ArmaDir,
    [int]$Port = 24362,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runDir = Join-Path $env:TEMP ('CLDW-engine-' + [guid]::NewGuid().ToString('N'))
$missionRelative = 'CLDW_Validation\' + [guid]::NewGuid().ToString('N')
$missionRoot = Join-Path $ArmaDir $missionRelative
$missionDir = Join-Path $missionRoot 'CLDW_Validation.VR'
$profileDir = Join-Path $runDir 'profiles'
New-Item -ItemType Directory -Path $missionDir,$profileDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'functions') -Destination $missionDir -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'mission.sqm') -Destination $missionDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'engine.sqf') -Destination (Join-Path $missionDir 'test.sqf')
'[] execVM "test.sqf";' | Set-Content -LiteralPath (Join-Path $missionDir 'initServer.sqf')
'author="CLDW"; onLoadName="CLDW validation"; disabledAI=0;' | Set-Content -LiteralPath (Join-Path $missionDir 'description.ext')
$serverConfig = @'
hostname="CLDW local validation";
password="cldw-local-validation";
passwordAdmin="cldw-local-validation-admin";
BattlEye=0;
verifySignatures=0;
persistent=1;
maxPlayers=2;
class Missions {class Validation {template="CLDW_Validation.VR"; difficulty="Regular";};};
'@
$serverConfig | Set-Content -LiteralPath (Join-Path $runDir 'server.cfg')
$arguments = @(
    '-autoInit','-noSound','-filePatching','-ip=127.0.0.1',"-port=$Port",
    ('-config="' + (Join-Path $runDir 'server.cfg') + '"'),
    ('-profiles="' + $profileDir + '"'),
    ('-mpmissions="' + $missionRelative + '"')
)
$process = Start-Process -FilePath (Join-Path $ArmaDir 'arma3server_x64.exe') -ArgumentList $arguments -WorkingDirectory $ArmaDir -WindowStyle Hidden -PassThru
Write-Output "Validation PID $($process.Id); logs: $profileDir"
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$passed = $false
try {
    while ([DateTime]::UtcNow -lt $deadline -and !$process.HasExited) {
        Start-Sleep -Seconds 1
        $rpt = Get-ChildItem -LiteralPath $profileDir -Filter '*.rpt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($rpt) {
            $log = Get-Content -LiteralPath $rpt.FullName -Raw
            if ($log -match 'CLDW_TEST DONE tests=\d+ failures=(\d+)') {
                $passed = $Matches[1] -eq '0' -and !($log -match 'Error in expression|Error position|Error Undefined|Unknown enum value')
                $log -split [Environment]::NewLine | Where-Object {$_ -match 'CLDW_TEST|Error in expression|Error position|Error Undefined|Unknown enum value'}
                break
            }
        }
    }
} finally {
    if (!$process.HasExited) {Stop-Process -Id $process.Id -Force}
    $process.WaitForExit(5000) | Out-Null
    $checkedRoot = [IO.Path]::GetFullPath($missionRoot)
    $expectedParent = [IO.Path]::GetFullPath((Join-Path $ArmaDir 'CLDW_Validation')) + '\'
    if (!$checkedRoot.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase)) {throw 'Unexpected validation directory'}
    Remove-Item -LiteralPath $checkedRoot -Recurse -Force
}
if (!$passed) {throw "Validation failed or timed out. Inspect $profileDir"}
