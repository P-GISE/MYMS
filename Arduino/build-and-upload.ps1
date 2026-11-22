param(
    [string]$Port = 'COM5',
    [switch]$Upload,
    [string]$ArduinoCli = 'C:/Program Files/Arduino IDE/resources/app/lib/backend/resources/arduino-cli.exe',
    [string]$ArduinoBLE = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Arduino/libraries/ArduinoBLE')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $ArduinoBLE 'src/utility/HCI.cpp'
$expected = '8A74BC8D33F5B676C05C382CA7E19F7F5549E2E5ECFEBB0B4F52FF8549513A6F'
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $expected) {
    throw 'This workaround requires the original ArduinoBLE 2.1.1 HCI.cpp. Review the patch before using another version.'
}

# Patch a project-local copy; keep the installed Arduino library unchanged.
$library = Join-Path $repo 'build/arduino-libraries/ArduinoBLE'
New-Item -ItemType Directory -Force -Path $library | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $ArduinoBLE -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $library -Recurse -Force
}
$target = Join-Path $library 'src/utility/HCI.cpp'
$text = [IO.File]::ReadAllText($target).Replace("`r`n", "`n")
$signature = "void HCIClass::handleNumCompPkts(uint16_t /*handle*/, uint16_t numPkts)`n{"
$disconnect = 'ATT.removeConnection(disconnComplete->handle, disconnComplete->reason);'
if (!$text.Contains($signature) -or !$text.Contains($disconnect)) {
    throw 'Unexpected ArduinoBLE source; patch was not applied.'
}
# getPeerAddr only reads peer state; connected(handle) would recursively poll HCI.
$text = $text.Replace($signature,
    "void HCIClass::handleNumCompPkts(uint16_t handle, uint16_t numPkts)`n{`n  uint8_t peerAddress[6];`n  if (!ATT.getPeerAddr(handle, peerAddress) || numPkts == 0) return;")
$text = $text.Replace($disconnect, "$disconnect`n    if (!ATT.connected()) _pendingPkt = 0;")
[IO.File]::WriteAllText($target, $text, [Text.UTF8Encoding]::new($false))

$output = Join-Path $repo 'build/arduino-firmware'
& $ArduinoCli compile --fqbn arduino:mbed_nano:nano33ble --library $library --output-dir $output (Join-Path $PSScriptRoot 'MYMS')
if ($LASTEXITCODE -ne 0) { throw 'Arduino compilation failed.' }
if ($Upload) {
    & $ArduinoCli upload --fqbn arduino:mbed_nano:nano33ble --port $Port --input-dir $output
    if ($LASTEXITCODE -ne 0) { throw 'Arduino upload failed.' }
}
