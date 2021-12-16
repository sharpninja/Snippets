param([switch]$VerboseSwitch = $false)

# $Verbose=$true -or $VerboseSwitch
$Verbose=$VerboseSwitch
# Write-Verbose "[$script] [$env:SnippetsInitialized] -not `$env:SnippetsInitialized: $(-not $env:SnippetsInitialized)" -Verbose:$Verbose
$script = $MyInvocation.MyCommand

if (-not $env:SnippetsInitialized) { 
    $fileInfo = New-Object System.IO.FileInfo (Get-Item $PSScriptRoot).FullName
    $path = $fileInfo.Directory.FullName;
    . $path/Snippets/common.ps1; 
    Initialize-Snippets -Verbose:$Verbose 
}

if ($env:IsWindows -ieq 'true') {
    try {
        $env:ChocolateyInstall = "$env:USERPROFILE\.choco"

        $ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
        
        if (Test-Path($ChocolateyProfile)) {
            Import-Module "$ChocolateyProfile"

            return "Imported the Chocolatey module."
        } else {
            return "The Chocolatey module could not be imported."
        }
    }
    catch {
        Write-Host $Error    
    }
    finally {
        Write-Verbose '[chocolatey.ps1] Leaving...' -Verbose:$Verbose
        $Verbose = $VerboseSwitch
    }
} else {
    $Verbose = $VerboseSwitch
    return "Chocolatey not available on this system."
}
