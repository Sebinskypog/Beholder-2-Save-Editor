# Beholder 2 Save Editor
# - Lists .data saves in the current folder
# - Lets you pick a segment with variables
# - Displays variables and lets you edit one (int/float/bool/string)
# - Writes 'content' as UTF-8 without BOM
# - Updates .bin CRC32 (last 8-hex token) BYTE-SAFELY (no binary corruption)

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
$ErrorActionPreference = 'Stop'

function Read-ContentText([string]$ZipPath) {
  $zip=[IO.Compression.ZipFile]::Open($ZipPath,'Read')
  try {
    $e=$zip.GetEntry('content'); if(-not $e){throw "Archive $ZipPath has no 'content' entry."}
    # BOM-aware reader for safety when reading
    $sr=[IO.StreamReader]::new($e.Open(),[Text.Encoding]::UTF8,$true)
    try{$sr.ReadToEnd()}finally{$sr.Dispose()}
  } finally { $zip.Dispose() }
}

function Write-ContentText([string]$ZipPath,[string]$Text){
  $zip=[IO.Compression.ZipFile]::Open($ZipPath,'Update')
  try{
    $old=$zip.GetEntry('content'); if($old){$old.Delete()}
    $entry=$zip.CreateEntry('content',[IO.Compression.CompressionLevel]::Optimal)
    # UTF-8 *without BOM*
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sw=[IO.StreamWriter]::new($entry.Open(), $utf8NoBom)
    try{$sw.Write($Text)}finally{$sw.Dispose()}
  }finally{$zip.Dispose()}
}

# ---------- CRC32 via C# ----------
if (-not ("Crc32" -as [type])) {
Add-Type -Language CSharp -TypeDefinition @"
using System;

public static class Crc32
{
    static readonly uint[] Table = new uint[256];
    static Crc32()
    {
        const uint poly = 0xEDB88320u;
        for (uint i = 0; i < Table.Length; i++)
        {
            uint crc = i;
            for (int j = 0; j < 8; j++)
                crc = (crc & 1) != 0 ? (poly ^ (crc >> 1)) : (crc >> 1);
            Table[i] = crc;
        }
    }

    public static uint Compute(byte[] bytes)
    {
        uint crc = 0xFFFFFFFFu;
        for (int i = 0; i < bytes.Length; i++)
        {
            byte b = bytes[i];
            crc = Table[(crc ^ b) & 0xFF] ^ (crc >> 8);
        }
        return crc ^ 0xFFFFFFFFu;
    }
}
"@
}

function Get-CRC32([byte[]]$Bytes){
  $u=[Crc32]::Compute($Bytes)
  # lowercase 8-hex
  '{0:x8}' -f [uint32]$u
}

# ---------- BYTE-SAFE .bin CRC update ----------
function Update-BinCRC([string]$BinPath,[string]$Hex8){
  # Only overwrite the last standalone 8-hex token in-place
  $bytes = [IO.File]::ReadAllBytes($BinPath)
  $ascii = [Text.Encoding]::ASCII

  # 1:1 mapping (ASCII maps non-ASCII bytes to '?', but preserves length)
  $txt = $ascii.GetString($bytes)
  $rx  = [Regex]::new('(?i)(?<![0-9A-F])[0-9A-F]{8}(?![0-9A-F])')
  $m   = $rx.Matches($txt)
  if ($m.Count -lt 1) { throw "No 8-hex tokens found in $BinPath" }
  $idx = $m[$m.Count-1].Index
  $newBytes = $ascii.GetBytes($Hex8)
  for ($i=0; $i -lt 8; $i++) { $bytes[$idx+$i] = $newBytes[$i] }
  [IO.File]::WriteAllBytes($BinPath, $bytes)
}

function Escape-JsonString([string]$Raw){ ($Raw -replace '\\','\\\\') -replace '"','\"' }
function Unescape-JsonString([string]$Esc){ [Regex]::Unescape($Esc) }
function Clamp-Int32([long]$v){ if($v -gt 2147483647){2147483647}elseif($v -lt -2147483648){-2147483648}else{$v} }

# Enumerate all "$content":"..." segments that parse to JSON and contain _variables
function Get-VariableSegments([string]$Content){
  $prefix='"$content":"'
  $cands=@(); $i=0
  while(($i=$Content.IndexOf($prefix,$i)) -ge 0){
    $j=$i+$prefix.Length; $esc=$false; $end=$null
    for($k=$j;$k -lt $Content.Length;$k++){
      $ch=$Content[$k]
      if(-not $esc -and $ch -eq '\'){ $esc=$true; continue }
      if(-not $esc -and $ch -eq '"'){ $end=$k; break }
      $esc=$false
    }
    if(-not $end){break}
    $segEsc=$Content.Substring($j,$end-$j)
    $segUn =Unescape-JsonString $segEsc
    try{
      $obj=$segUn | ConvertFrom-Json -ErrorAction Stop
      if($obj -and $obj.PSObject.Properties.Name -contains '_variables' -and $obj._variables){
        $keys=$obj._variables.PSObject.Properties.Name
        if($keys){ $cands+=@(@{Start=$j;End=$end;Esc=$segEsc;Un=$segUn;Keys=$keys}) }
      }
    }catch{}
    $i=$end+1
  }
  $cands
}

Write-Host ""
Write-Host "Beholder 2 Save Editor (v2)" -ForegroundColor Cyan
Write-Host ("Folder: {0}" -f (Get-Location).Path) -ForegroundColor DarkGray
Write-Host ""

# 1) choose .data
$dataFiles=Get-ChildItem -File -Filter *.data | Sort-Object Name
if(-not $dataFiles){Write-Host "No .data files here." -ForegroundColor Yellow; Read-Host "Press Enter to exit"; exit}
Write-Host "Available .data saves:"
for($i=0;$i -lt $dataFiles.Count;$i++){ "{0,3}: {1}" -f $i,$dataFiles[$i].Name | Write-Host }
$idx=-1
while($true){
  $in=Read-Host "Select index of .data to edit"
  $parsed = 0
  $ok = [int]::TryParse($in, [ref]$parsed)
  if($ok){ $idx = $parsed }
  if($ok -and $idx -ge 0 -and $idx -lt $dataFiles.Count){ break }
  Write-Host "Invalid index." -ForegroundColor Yellow
}
$dataPath=$dataFiles[$idx].FullName
$base=[IO.Path]::GetFileNameWithoutExtension($dataPath)
$binPath=Join-Path (Split-Path $dataPath -Parent) ($base+'.bin')
if(-not (Test-Path $binPath)){Write-Host ("Missing .bin: {0}" -f $binPath) -ForegroundColor Red; Read-Host "Press Enter to exit"; exit}

# 2) load and enumerate variable segments
$content=Read-ContentText $dataPath
$cands=Get-VariableSegments $content
if($cands.Count -eq 0){ Write-Host "No embedded JSON segments with _variables found." -ForegroundColor Yellow; Read-Host "Press Enter to exit"; exit }

Write-Host ""
Write-Host "Segments that contain variables:" -ForegroundColor DarkGray
for($i=0;$i -lt $cands.Count;$i++){
  $keys=$cands[$i].Keys -join ', '
  "{0,3}: keys = [{1}]" -f $i,$keys | Write-Host
}
$pick=-1
while($true){
  $in=Read-Host "Pick segment index"
  $parsed = 0
  $ok = [int]::TryParse($in, [ref]$parsed)
  if($ok){ $pick = $parsed }
  if($ok -and $pick -ge 0 -and $pick -lt $cands.Count){ break }
  Write-Host "Invalid index." -ForegroundColor Yellow
}
$seg=$cands[$pick]
$un=$seg.Un

# 4) parse and list all variables
try{
  $obj=$un | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Host "Failed to parse selected segment as JSON." -ForegroundColor Red
  Read-Host "Press Enter to exit"; exit
}
$vars = $obj._variables
$keys = $vars.PSObject.Properties.Name

Write-Host ""
Write-Host "Variables in this segment (index : name = value):" -ForegroundColor DarkGray
$indexMap=@{}
for($i=0;$i -lt $keys.Count;$i++){
  $k = $keys[$i]
  $v = $vars.$k
  $val = if($v.PSObject.Properties.Name -contains '_value'){ $v._value } else { '(no _value)' }
  "{0,3}: {1} = {2}" -f $i, $k, $val | Write-Host
  $indexMap[$i]=$k
}

# 5) choose variable
$targetKey=$null
while($true){
  $sel=Read-Host "Enter variable index or name"
  if(($sel -as [int]) -ne $null -and $indexMap.ContainsKey([int]$sel)){ $targetKey=$indexMap[[int]$sel]; break }
  if($keys -contains $sel){ $targetKey=$sel; break }
  Write-Host "Not found." -ForegroundColor Yellow
}

# 6) current value and new value
$curVal = $vars.$targetKey._value
Write-Host ("Current {0} = {1}" -f $targetKey, $curVal) -ForegroundColor DarkGray
$newRaw = Read-Host ("New value for {0}" -f $targetKey)

# 7) patch selected variable (supports int, float, bool, string)
$patchedUn = $un
$patched = $false

# integer
if (-not $patched -and ($newRaw -match '^-?\d+$')) {
  $newVal=[int64]$newRaw; $newVal=Clamp-Int32 $newVal
  $rx=[Regex]::new('("'+[Regex]::Escape($targetKey)+'"\s*:\s*{\s*"_value"\s*:\s*)(-?\d+)', 'IgnoreCase')
  if ($rx.IsMatch($patchedUn)) {
    # use MatchEvaluator to avoid any "$1" literal mishaps
    $patchedUn=$rx.Replace($patchedUn, { param($mm) $mm.Groups[1].Value + ([string]$newVal) }, 1)
    $patched=$true
  }
}

# float (1.23, -0.5, 10., .75, with optional exponent)
if (-not $patched -and ($newRaw -match '^-?(?:\d+\.\d*|\.\d+|\d+\.)(?:[eE][+-]?\d+)?$')) {
  $rx=[Regex]::new('("'+[Regex]::Escape($targetKey)+'"\s*:\s*{\s*"_value"\s*:\s*)(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)', 'IgnoreCase')
  if ($rx.IsMatch($patchedUn)) {
    $patchedUn=$rx.Replace($patchedUn, { param($mm) $mm.Groups[1].Value + $newRaw }, 1)
    $patched=$true
  }
}

# boolean
if (-not $patched -and ($newRaw -match '^(?i:true|false)$')) {
  $rx=[Regex]::new('("'+[Regex]::Escape($targetKey)+'"\s*:\s*{\s*"_value"\s*:\s*)(true|false)', 'IgnoreCase')
  if ($rx.IsMatch($patchedUn)) {
    $patchedUn=$rx.Replace($patchedUn, { param($mm) $mm.Groups[1].Value + $newRaw.ToLower() }, 1)
    $patched=$true
  }
}

# string fallback
if (-not $patched) {
  $escapedNew=($newRaw -replace '\\','\\\\') -replace '"','\"'
  $rx=[Regex]::new('("'+[Regex]::Escape($targetKey)+'"\s*:\s*{\s*"_value"\s*:\s*)"(.*?)"', 'IgnoreCase')
  if ($rx.IsMatch($patchedUn)) {
    $patchedUn=$rx.Replace($patchedUn, { param($mm) $mm.Groups[1].Value + '"' + $escapedNew + '"' }, 1)
    $patched=$true
  } else {
    throw "Could not find a compatible _value pattern for $targetKey (int/float/bool/string)."
  }
}

# 8) write back and update CRC
$patchedEsc = Escape-JsonString $patchedUn
$newContent = $content.Substring(0,[int]$seg.Start) + $patchedEsc + $content.Substring([int]$seg.End)

Write-Host ""
Write-Host "Writing content..." -ForegroundColor DarkCyan
Write-ContentText $dataPath $newContent

Write-Host "Updating .bin CRC..." -ForegroundColor DarkCyan
$crc8 = Get-CRC32 ([IO.File]::ReadAllBytes($dataPath))
Update-BinCRC $binPath $crc8

Write-Host ""
Write-Host ("Done - Edited {0} : {1} set to {2}. CRC synced in {3}." -f `
    ([IO.Path]::GetFileName($dataPath)), $targetKey, $newRaw, ([IO.Path]::GetFileName($binPath))) `
    -ForegroundColor Green

Read-Host "Press Enter to exit"

