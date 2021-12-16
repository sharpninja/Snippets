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

try {
	if (-not $env:GITHUB) {
		$env:GITHUB = (Get-ChildItem -Filter GitHub -Path C:\ -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
	}

	function Set-LocationGitHub {
		param(
			[string]$Repository = '',
			[switch]$V = $false
		)

		Write-Verbose "[$script] `$env:GITHUB:  [$($env:GITHUB)]" -Verbose:$V
		Write-Verbose "[$script] `$Repository:  [$Repository]" -Verbose:$V
		Set-Location (Join-Path $env:GITHUB -Child $Repository)
	}

	Set-Alias -Name hub -Value Set-LocationGitHub

	return "Use ``hub`` to go to the GitHub folder."
}
catch {
	Write-Host $Error    
}
finally {
	Write-Verbose '[github.ps1] Leaving...' -Verbose:$Verbose
	$Verbose = $VerboseSwitch
}
