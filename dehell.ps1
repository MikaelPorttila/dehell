<#
    Author: Mikael Porttila
#>

function Is-Repo
{
    param($path)
    return (-not (git -C $path rev-parse))
}

$path = $args[0]
$useConfig = $false

if($path -like "*.json")
{
    $useConfig = $true
}
else
{
    if([string]::IsNullOrEmpty($path))
    {
        $path = Get-Location
    }
    
    $configPath = Join-Path $path 'dehell.json';

    if(Test-Path $configPath)
    {
        $useConfig = $true
        $path = $configPath
    }
}

$repositories = @()
$dir
if($useConfig) 
{
    # Load config
    $path = Resolve-Path $path
    $dir = Split-Path -Path $path
    $repositories = (Resolve-Path $path | Get-Content | ConvertFrom-Json).repositories;
}
else 
{
    # Scan for git repositories
    $dir = Resolve-Path $path;
    Get-ChildItem -Directory -Path $dir | Select-Object -property name | ForEach-Object {
        if(Is-Repo($_.name)) 
        {
            $repositories += $_.name;
        }
    } 
}

$repositories | where {Is-Repo($_)} | ForEach-Object -Parallel {
    $repoName = $_;
    $repoPath = Join-Path $using:dir $repoName | Resolve-Path;

    Write-Host "[$repoName] Sync" -ForegroundColor DarkGreen

    # Stash work in progress if needed
    $skipStash = -not (git -C $repoPath status --short --untracked-files=no);
    if(!$skipStash) 
    {
        Write-Host "[$repoName] Stashing" -ForegroundColor DarkGreen
        git -C $repoPath stash -q;
    }

    # Fetch and Pull
    git -C $repoPath fetch -q;
    git -C $repoPath pull -q;

    # Pop stash if needed
    if(!$skipStash) 
    {
        git -C $repoPath stash pop -q;
        Write-Host "[$repoName] Stash popped" -ForegroundColor DarkGreen
    }
    
    Write-Host "[$repoName] Done ✔" -ForegroundColor DarkGreen
    
} -ThrottleLimit 3;
