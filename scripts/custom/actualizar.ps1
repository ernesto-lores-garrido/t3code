<#
.SYNOPSIS
  Compila tu rama custom y la instala, con copia previa de tus datos.
.DESCRIPTION
  1. Compila el instalador de Windows. Lleva la versión de la última release oficial incluida en
     custom, así que la app avisará cuando salga una más nueva.
  2. Cierra T3 Code y copia ~\.t3\userdata (sin logs) en ~\.t3-backups. Conserva las 3 últimas copias.
  3. Ejecuta el instalador, que vuelve a abrir T3 Code.
  Dentro de T3 Code (terminal integrada o agente) solo compila y explica cómo instalar.
.PARAMETER SinCompilar
  Instala lo último compilado, si corresponde al commit actual.
.EXAMPLE
  .\scripts\custom\actualizar.ps1
#>
param([switch]$SinCompilar)

. (Join-Path $PSScriptRoot 'comun.ps1')

Push-Location $Repo
try {
  $rama = git rev-parse --abbrev-ref HEAD
  if ($rama -ne 'custom') { throw "Estás en la rama '$rama'. Cambia a 'custom' antes de instalar." }
  if (git status --porcelain) { throw 'Hay cambios sin commitear. Haz commit antes de instalar.' }
  $commit = git rev-parse --short HEAD
  $tag = git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' HEAD
  if (-not $tag) { throw 'No encuentro ninguna release oficial (tag vX.Y.Z) en custom.' }
  $version = $tag.Substring(1)
  $instalador = Join-Path $Repo "release\T3-Code-$version-x64.exe"
  $compilacion = Join-Path $Repo 'release\compilacion-custom.json'

  $actual = Get-T3Instalado
  if ($actual -and (ConvertTo-Version $version) -lt (ConvertTo-Version $actual.Version)) {
    throw "Tienes instalada la $($actual.Version), más nueva que la $version. Instalar una versión anterior dañaría tus datos."
  }
  $porScript = Get-InstaladoPorScript
  if ($actual -and $actual.Version -eq $version -and $porScript -and $porScript.commit -eq $commit) {
    Write-Host "Ya tienes instalada la $version del commit $commit. No hay nada que hacer."
    return
  }

  if (-not $SinCompilar) {
    if (-not (Get-Command vp -ErrorAction SilentlyContinue)) { throw "No encuentro 'vp'. Abre una terminal nueva." }
    Write-Host "Compilando T3 Code $version (commit $commit). Tarda varios minutos..."
    $env:T3CODE_DESKTOP_UPDATE_REPOSITORY = 'pingdotgg/t3code'
    $env:T3CODE_DESKTOP_VERSION = $version
    try {
      vp i
      if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación de dependencias (vp i).' }
      vp run dist:desktop:win:x64
      if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación.' }
    } finally {
      Remove-Item Env:\T3CODE_DESKTOP_UPDATE_REPOSITORY, Env:\T3CODE_DESKTOP_VERSION -ErrorAction SilentlyContinue
    }
    [ordered]@{ version = $version; commit = $commit } | ConvertTo-Json | Set-Content $compilacion -Encoding UTF8
  }

  $compilado = $null
  if (Test-Path $compilacion) { $compilado = Get-Content $compilacion -Raw | ConvertFrom-Json }
  if (-not $compilado -or $compilado.commit -ne $commit -or $compilado.version -ne $version -or -not (Test-Path $instalador)) {
    throw "No hay instalador compilado para el commit $commit. Ejecuta el script sin -SinCompilar."
  }

  if (Test-DentroDeT3) {
    Write-Host ''
    Write-Host "Instalador listo: $instalador"
    Write-Host 'Para instalarlo hay que cerrar T3 Code, y este script se está ejecutando dentro de él.'
    Write-Host 'Abre una terminal fuera de T3 Code (menú Inicio > Terminal) y ejecuta:'
    Write-Host "  & '$PSCommandPath' -SinCompilar"
    return
  }

  Confirm-Paso "Se cerrará T3 Code (se interrumpirán los agentes en marcha), se copiarán tus datos y se instalará la $version."
  if ($actual) { Close-T3 $actual.Carpeta }
  $copia = New-CopiaT3 $version $commit
  Install-T3 $instalador $version
  Save-Instalado $instalador $version $commit
  Write-Host ''
  Write-Host "Listo: T3 Code $version (commit $commit) instalado."
  if ($copia) { Write-Host "Copia de tus datos anteriores: $copia" }
  Write-Host "Para volver atrás: & '$(Join-Path $PSScriptRoot 'restaurar.ps1')'"
} finally {
  Pop-Location
}
