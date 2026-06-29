param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $DestroyArgs
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

function Find-GitBash {
  $candidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\usr\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }
  throw "Git Bash was not found. Install Git for Windows or run scripts/destroy.sh from a POSIX shell."
}

function ConvertTo-GitBashPath([string] $Path) {
  $normalized = $Path.Replace('\', '/')
  if ($normalized -match '^/[A-Za-z]/') {
    return $normalized
  }
  if ($normalized -match '^/mnt/[A-Za-z]/') {
    $drive = $normalized.Substring(5, 1).ToLowerInvariant()
    $rest = $normalized.Substring(6)
    return "/$drive$rest"
  }
  $full = [System.IO.Path]::GetFullPath($Path)
  $drive = $full.Substring(0, 1).ToLowerInvariant()
  $rest = $full.Substring(2).Replace('\', '/')
  return "/$drive$rest"
}

function Convert-ArgumentForGitBash([string] $Value) {
  if ($Value -match '^[A-Za-z]:[\\/]') {
    return ConvertTo-GitBashPath $Value
  }
  if ($Value -match '^\.{1,2}[\\/]') {
    return ConvertTo-GitBashPath (Join-Path (Get-Location).ProviderPath $Value)
  }
  return $Value
}

function Quote-BashArg([string] $Value) {
  return "'" + ($Value -replace "'", "'\''") + "'"
}

$bash = Find-GitBash

$windowsDirexioHome = if ($env:DIREXIO_HOME -and ($env:DIREXIO_HOME -notmatch '^/[A-Za-z]/' -and $env:DIREXIO_HOME -notmatch '^/mnt/[A-Za-z]/')) {
  $env:DIREXIO_HOME
} else {
  Join-Path $env:USERPROFILE '.direxio'
}
$env:DIREXIO_WINDOWS_HOME = $windowsDirexioHome
$env:DIREXIO_HOME = ConvertTo-GitBashPath $windowsDirexioHome
$env:DIREXIO_LOCAL_PATH_STYLE = 'windows'

if ($env:P2P_WORKDIR) {
  $env:P2P_WORKDIR_WINDOWS = $env:P2P_WORKDIR
  $env:P2P_WORKDIR = ConvertTo-GitBashPath $env:P2P_WORKDIR
}

$repoRootForBash = ConvertTo-GitBashPath $RepoRoot
$quotedArgs = ($DestroyArgs | ForEach-Object { Quote-BashArg (Convert-ArgumentForGitBash $_) }) -join ' '
$command = "cd $(Quote-BashArg $repoRootForBash) && ./scripts/destroy.sh $quotedArgs"

& $bash -lc $command
exit $LASTEXITCODE
