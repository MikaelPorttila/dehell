<#
    Author: Mikael Porttila
#>

function Is-Repo {
    param (
        [Parameter(Mandatory=$true)] [String]$path
    )
    return (-not (git -C $path rev-parse))
}

# Credit: https://stackoverflow.com/users/602585/deadlydog
function Get-DevEnvExecutableFilePath
{
    [bool] $vsSetupExists = $null -ne (Get-Command Get-VSSetupInstance -ErrorAction SilentlyContinue)
    if (!$vsSetupExists)
    {
        Write-Verbose "Installing the VSSetup module..."
        Install-Module VSSetup -Scope CurrentUser -Force
    }
    [string] $visualStudioInstallationPath = (Get-VSSetupInstance | Select-VSSetupInstance -Latest -Require Microsoft.Component.MSBuild).InstallationPath

    $devEnvExecutableFilePath = (Get-ChildItem $visualStudioInstallationPath -Recurse -Filter "DevEnv.exe" | Select-Object -First 1).FullName
    return $devEnvExecutableFilePath
}

function Refresh-And-Run {
    param (
        [Parameter(Mandatory=$false)] [String]$path,
        [Parameter(Mandatory=$false)] [bool]$runDebug = $false
    )

    if ($path -like "*.json") {
        $useConfig = $true
    } else {
        if ([string]::IsNullOrEmpty($path)) {
            $path = Get-Location
        }
        
        $configPath = Join-Path $path 'dehell.json';

        if (Test-Path $configPath) {
            $useConfig = $true
            $path = $configPath
        }
    }

    $repos = @()
    if ($useConfig) {
        $path = Resolve-Path $path
        $dir = Split-Path -Path $path
        $repos = (Resolve-Path $path | Get-Content | ConvertFrom-Json).repositories;
    }
    else {
        $dir = Resolve-Path $path;
        Get-ChildItem -Directory -Path $dir | Select-Object -property name | ForEach-Object {
            if (Is-Repo($_.name)) {
                $repos += $_.name;
            }
        } 
    }

    $repos | where {Is-Repo($_)} | ForEach-Object -Parallel {
        $repoName = $_;
        $repoPath = Join-Path $using:dir $repoName | Resolve-Path;

        Write-Host "[$repoName] Sync" -ForegroundColor DarkGreen

        # Stash work in progress if needed
        $skipStash = -not (git -C $repoPath status --short --untracked-files=no);
        if (!$skipStash) {
            Write-Host "[$repoName] Stashing" -ForegroundColor DarkGreen
            git -C $repoPath stash -q;
        }

        # Fetch and Pull
        git -C $repoPath fetch -q;
        git -C $repoPath pull -q;

        # Pop stash if needed
        if (!$skipStash) {
            git -C $repoPath stash pop -q;
            Write-Host "[$repoName] Stash popped" -ForegroundColor DarkGreen
        }
        
        Write-Host "[$repoName] Done ✔" -ForegroundColor DarkGreen
    } -ThrottleLimit 3;

    if($runDebug) {
        $repos | ForEach-Object {
            $repo = $_
            $repoPath = Join-Path $dir $repo | Resolve-Path
            $files = Get-ChildItem -Path $repoPath -File #-Include "*.sln", "*.csproj", "*package.json" , "*denon.json"

            $processArgs = @()
            $process
            $found = $false
            $notSupported = $false;

            $files | where { ($_ -like '*.sln')} | Select-Object -First 1 | ForEach-Object {
                $found = $true;
                $process = Get-DevEnvExecutableFilePath
                if($process) {
                    # https://docs.microsoft.com/en-us/visualstudio/ide/reference/devenv-command-line-switches?view=vs-2019
                    $processArgs += "'/R'"
                }
                else {
                    $notSupported = $true;
                }
            }

            if(!$found) {
                $files | where { $_ -like '*.csproj'} | Select-Object -First 1 | ForEach-Object {
                    $found = $true;
                    $process = Get-DevEnvExecutableFilePath
                    if($process) {
                        # https://docs.microsoft.com/en-us/visualstudio/ide/reference/devenv-command-line-switches?view=vs-2019
                        $processArgs += "'/R'"
                    } else {
                        $notSupported = $true;
                    }
                }
            }
            
            if(!$found) {
                $files | where { $_ -like '*package.json'} | Select-Object -First 1 | ForEach-Object {
                    #TODO (MIKAEL) Parse package.json and look for start, dev or debug (and/or what garbage like Angular uses...)
                    $found = $true;
                    $packageJson = $_ | Get-Content | ConvertFrom-Json;
                    $process = "npm"
                    $processArgs += "'start'"
                }
            }

            if(!$found) {
                $files | where { $_ -like '*denon.json'}  | Select-Object -First 1 | ForEach-Object {     
                    $found = $true;    
                    $denon = $_ | Get-Content | ConvertFrom-Json;
                    $process = "denon"
                    $processArgs += "'start'"
                }
            }

            if($found) {
                if(!$notSupported) {
                    write-Host "[$repo] Debugging" -ForegroundColor DarkBlue
                    Start-Process -FilePath $process -ArgumentList $processArgs -WorkingDirectory $repoPath
                } else {
                    write-Host "[$repo] Runtime is not supported on this machine" -ForegroundColor DarkRed
                }
            }
        }
    }
} 

$runDebug = $false;
if($args.count -gt 1) {
    $runDebug = $args[1]
}

Refresh-And-Run $args[0] $runDebug
