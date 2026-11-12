<#
.SYNOPSIS
  Vuelve al estado de una copia hecha por actualizar.ps1.
.DESCRIPTION
  Cierra T3 Code, aparta tus datos actuales a ~\.t3\userdata.reemplazado-<fecha> (no se borran),
  pone los de la copia y reinstala la versión a la que pertenecen, si la copia incluye su instalador.
.PARAMETER Copia
  Carpeta de la copia. Por defecto, la más reciente de ~\.t3-backups.
.EXAMPLE
  .\scripts\custom\restaurar.ps1
#>
param([string]$Copia)

. (Join-Path $PSScriptRoot 'comun.ps1')

if (-not $Copia) {
  $Copia = Get-ChildItem $Copias -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_' } |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Copia -or -not (Test-Path (Join-Path $Copia 'copia.json'))) { throw "No encuentro ninguna copia en $Copias." }
$info = Get-Content (Join-Path $Copia 'copia.json') -Raw | ConvertFrom-Json
$instalador = $null
if ($info.instalador) { $instalador = Join-Path $Copia $info.instalador }

if (Test-DentroDeT3) {
  Write-Host 'Para restaurar hay que cerrar T3 Code, y este script se está ejecutando dentro de él.'
  Write-Host "Abre una terminal fuera de T3 Code y ejecuta: & '$PSCommandPath' -Copia '$Copia'"
  return
}

Write-Host "Copia del $($info.fecha): datos de T3 Code $($info.version)."
Confirm-Paso 'Se cerrará T3 Code y tus datos actuales se apartarán (no se borran) para poner los de la copia.'
$actual = Get-T3Instalado
if ($actual) { Close-T3 $actual.Carpeta }
$apartados = Restore-DatosT3 $Copia

if ($instalador) {
  Install-T3 $instalador $info.version
  Save-Instalado $instalador $info.version $info.commit
  Write-Host "Listo: datos restaurados y T3 Code $($info.version) reinstalado."
} elseif ($actual -and $actual.Version -eq $info.version) {
  Start-Process -FilePath $actual.Exe
  Write-Host 'Listo: datos restaurados.'
} else {
  Write-Host "Datos restaurados. Son de la versión oficial $($info.version): instálala ANTES de abrir T3 Code,"
  Write-Host 'porque la versión instalada ahora volvería a migrarlos:'
  Write-Host "  https://github.com/pingdotgg/t3code/releases/tag/v$($info.version)"
}
if ($apartados) { Write-Host "Tus datos anteriores están en $apartados. Bórralos cuando ya no los necesites." }
