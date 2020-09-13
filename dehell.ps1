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
        [Parameter(Mandatory=$false)] $path,
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
            $repoPath = Join-Path $dir $repo | Resolve-Path;
            $files = Get-ChildItem -Path $repoPath -File;

            $dotnetSolutions = $files | where { $_ -like '*.sln'}
            if(($dotnetSolutions).count -gt 0) {
                $devEnv = Get-DevEnvExecutableFilePath
                if($devEnv) {
                    # https://docs.microsoft.com/en-us/visualstudio/ide/reference/devenv-command-line-switches?view=vs-2019
                    write-Host "[$repo] devenv /R" -ForegroundColor DarkBlue
                }
                else {
                    write-Host "[$repo] Missing devenv" -ForegroundColor DarkRed
                }
            }

            $dotnetProjects = $files | where { $_ -like '*.csproj'}
            if(($dotnetProjects).count -gt 0) {
                $devEnv = Get-DevEnvExecutableFilePath
                if($devEnv) {
                    # https://docs.microsoft.com/en-us/visualstudio/ide/reference/devenv-command-line-switches?view=vs-2019
                    write-Host "[$repo] devenv /R" -ForegroundColor DarkBlue
                    Start-Process -FilePath $devEnv /R -WorkingDirectory $repoPath -NoNewWindow false &
                }
                else {
                    write-Host "[$repo] Missing devenv" -ForegroundColor DarkRed
                }
                return;
            }

            $nodeProjects = $files | where { $_ -like '*package.json'}
            if(($nodeProjects).count -gt 0) {
                #TODO (MIKAEL) Parse package.json and look for start, dev or debug (and/or what garbage like Angular uses...)
                write-Host "[$repo] npm start" -ForegroundColor DarkBlue
                Start-Process -FilePath npm start -WorkingDirectory $repoPath -NoNewWindow false &
                return;
            }

            $denoProjects = $files | where { $_ -like '*denon.json'}
            if(($denoProjects).count -gt 0) {
                #TODO (MIKAEL) Parse denon file and search for start, dev, debug
                write-Host "[$repo] denon start" -ForegroundColor DarkBlue
                Start-Process -FilePath denon start -WorkingDirectory $repoPath -NoNewWindow false &
                return;
            }

            
        }
    }
} 

$runDebug = $false;
if($args.count -gt 1) {
    $runDebug = $args[1]
}

Refresh-And-Run $args[0] $runDebug
