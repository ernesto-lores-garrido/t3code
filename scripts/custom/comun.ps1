# Funciones compartidas por actualizar.ps1 y restaurar.ps1.

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Copias = Join-Path $HOME '.t3-backups'
$UserData = Join-Path $HOME '.t3\userdata'
$CopiasConservadas = 3

function ConvertTo-Version([string]$Texto) {
  [version](($Texto -split '-')[0])
}

function Get-T3Instalado {
  $entrada = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like 'T3 Code*' } |
    Select-Object -First 1
  if (-not $entrada) { return $null }
  $carpeta = Split-Path ($entrada.UninstallString -replace '^"([^"]+)".*$', '$1')
  $exe = Get-ChildItem $carpeta -Filter 'T3 Code*.exe' |
    Where-Object { $_.Name -notlike 'Uninstall*' } |
    Select-Object -First 1 -ExpandProperty FullName
  [pscustomobject]@{ Version = $entrada.DisplayVersion; Carpeta = $carpeta; Exe = $exe }
}

function Get-InstaladoPorScript {
  $info = Join-Path $Copias 'instalado\instalado.json'
  if (Test-Path $info) { Get-Content $info -Raw | ConvertFrom-Json }
}

function Get-ProcesosT3([string]$Carpeta) {
  $prefijo = $Carpeta.TrimEnd('\') + '\'
  Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefijo, [StringComparison]::OrdinalIgnoreCase)
  }
}

# Cerrar T3 Code cerraría también este script si se lanzó desde él (terminal integrada o agente).
function Test-DentroDeT3 {
  $procesos = @{}
  Get-CimInstance Win32_Process | ForEach-Object { $procesos[[int]$_.ProcessId] = $_ }
  $id = $PID
  for ($i = 0; $i -lt 30; $i++) {
    $proceso = $procesos[[int]$id]
    if (-not $proceso) { return $false }
    if ($proceso.Name -like 'T3 Code*') { return $true }
    $id = $proceso.ParentProcessId
  }
  return $false
}

function Confirm-Paso([string]$Mensaje) {
  $respuesta = Read-Host "$Mensaje ¿Continuar? (s/N)"
  if ($respuesta -notmatch '^\s*s[ií]?\s*$') {
    Write-Host 'Cancelado. No se ha cambiado nada.'
    exit 1
  }
}

function Close-T3([string]$Carpeta) {
  $limite = (Get-Date).AddSeconds(90)
  while (@(Get-ProcesosT3 $Carpeta).Count -gt 0) {
    if ((Get-Date) -gt $limite) {
      throw 'T3 Code no se ha cerrado en 90 segundos. Ciérralo a mano y vuelve a ejecutar el script.'
    }
    Get-ProcesosT3 $Carpeta |
      ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      ForEach-Object { [void]$_.CloseMainWindow() }
    Start-Sleep -Seconds 2
  }
}

function New-CopiaT3([string]$VersionNueva, [string]$CommitNuevo) {
  if (-not (Test-Path $UserData)) { return $null }
  $actual = Get-T3Instalado
  $versionDatos = 'desconocida'
  if ($actual) { $versionDatos = $actual.Version }
  $porScript = Get-InstaladoPorScript
  $commitDatos = $null
  $instaladorDatos = $null
  if ($porScript -and $porScript.version -eq $versionDatos) {
    $commitDatos = $porScript.commit
    $instaladorDatos = $porScript.instalador
  }

  $carpeta = Join-Path $Copias ('{0:yyyy-MM-dd_HH-mm-ss}_{1}' -f (Get-Date), $versionDatos)
  New-Item -ItemType Directory -Path $carpeta -Force -ErrorAction Stop | Out-Null
  robocopy $UserData (Join-Path $carpeta 'userdata') /E /XD logs /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "Falló la copia de tus datos (robocopy $LASTEXITCODE)." }
  if ($instaladorDatos) {
    Copy-Item (Join-Path $Copias "instalado\$instaladorDatos") $carpeta -ErrorAction Stop
  }
  [ordered]@{
    fecha      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    version    = $versionDatos
    commit     = $commitDatos
    instalador = $instaladorDatos
    despues    = "$VersionNueva (commit $CommitNuevo)"
  } | ConvertTo-Json | Set-Content (Join-Path $carpeta 'copia.json') -Encoding UTF8

  Get-ChildItem $Copias -Directory |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_' } |
    Sort-Object Name -Descending |
    Select-Object -Skip $CopiasConservadas |
    Remove-Item -Recurse -Force
  return $carpeta
}

function Restore-DatosT3([string]$Copia) {
  $apartados = $null
  if (Test-Path $UserData) {
    $apartados = '{0}.reemplazado-{1:yyyy-MM-dd_HH-mm-ss}' -f $UserData, (Get-Date)
    Move-Item $UserData $apartados -ErrorAction Stop
  }
  robocopy (Join-Path $Copia 'userdata') $UserData /E /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) {
    throw "Falló la restauración (robocopy $LASTEXITCODE). Tus datos anteriores están en $apartados."
  }
  return $apartados
}

function Install-T3([string]$Instalador, [string]$Version) {
  Write-Host "Instalando $(Split-Path $Instalador -Leaf)..."
  # Sin -Wait, que esperaría también a la app que el instalador abre al terminar.
  # Windows PowerShell solo conserva ExitCode si se lee Handle antes de que el proceso acabe.
  $proceso = Start-Process -FilePath $Instalador -PassThru
  $null = $proceso.Handle
  $proceso.WaitForExit()
  if ($proceso.ExitCode -ne 0) { throw "El instalador terminó con el código $($proceso.ExitCode)." }
  $instalado = Get-T3Instalado
  if (-not $instalado -or $instalado.Version -ne $Version) {
    throw "Tras instalar, Windows indica la versión '$($instalado.Version)' en lugar de $Version."
  }
  for ($i = 0; $i -lt 15 -and @(Get-ProcesosT3 $instalado.Carpeta).Count -eq 0; $i++) { Start-Sleep -Seconds 1 }
  if (@(Get-ProcesosT3 $instalado.Carpeta).Count -eq 0) { Start-Process -FilePath $instalado.Exe }
}

function Save-Instalado([string]$Instalador, [string]$Version, [string]$Commit) {
  $carpeta = Join-Path $Copias 'instalado'
  if (Test-Path $carpeta) { Remove-Item $carpeta -Recurse -Force -ErrorAction Stop }
  New-Item -ItemType Directory -Path $carpeta -Force -ErrorAction Stop | Out-Null
  Copy-Item $Instalador $carpeta -ErrorAction Stop
  [ordered]@{
    version    = $Version
    commit     = $Commit
    instalador = Split-Path $Instalador -Leaf
    fecha      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  } | ConvertTo-Json | Set-Content (Join-Path $carpeta 'instalado.json') -Encoding UTF8
}
