param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $DestroyArgs
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'lib\windows-paths.ps1')

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

function Quote-BashArg([string] $Value) {
  return "'" + ($Value -replace "'", "'\''") + "'"
}

$bash = Find-GitBash

$windowsDirexioHome = Resolve-WindowsDirexioHome
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
