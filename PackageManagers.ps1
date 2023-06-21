using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Linq
using namespace System.Management.Automation
using namespace System.Reflection
using namespace System.Text.RegularExpressions
class ResultItem
{
    [string]$Repo;
    [string]$Command;
    [string]$ID;
    [string]$Version;
    [string]$Name;
    [string]$Description;
    [PackageManager]$PackageManager;
    [string]$Line;

    ResultItem(
        [string]$r,
        [string]$i,
        [string]$v,
        [string]$n,
        [string]$ins,
        [string]$d = '',
        [PackageManager]$pm,
        [string]$l
    )
    {
        $this.Repo = $r;
        $this.ID = $i;
        $this.Version = $v;
        $this.Name = $n;
        $this.Command = $ins;
        $this.Description = $d;
        $this.PackageManager = $pm;
        $this.Line = $l;
    }

    [string]ToString()
    {
        return $this.Line; 
    }
}

class PackageManager
{
    [string]$Name;
    [string]$Executable;
    [Object]$Command;
    [bool]$IsScript = $false;
    [bool]$IsPresent = $false;
    [string]$Search = 'search';
    [string]$Install = 'install';
    [string]$Upgrade = 'upgrade';
    [string]$Update = 'update';
    [string]$Uninstall = 'uninstall';
    [string]$Display = 'show';
    [Object[]]$List = 'list';
    [bool]$UseSudo = $false;
    [int]$ExitCode = 0;

    PackageManager(
        [string]$N,
        [string]$Exe,
        [string]$S,
        [string]$I,
        [string]$Upg,
        [string]$Upd,
        [Object[]]$L,
        [string]$Un = 'uninstall',
        [string]$D,
        [bool]$useSudo
    )
    {
        $this.Name = $N;
        $this.Executable = $Exe;
        $this.Search = $S;
        $this.Install = $I;
        $this.Upgrade = $Upg;
        $this.Update = $Upd;
        $this.List = $L;
        $this.Uninstall = $Un;
        $this.Display = $D;
        $this.UseSudo = $useSudo;

        $this.Command = Get-Command $this.Executable -ErrorAction SilentlyContinue;
        if ($this.Command)
        {
            $this.IsPresent = $true;
            $this.IsScript = $this.Command.Source.EndsWith('.ps1');
        }
    }

    [ResultItem]ParseResultItem(
        [string]$Line, 
        [string]$Command,
        [Switch]$Global)
    {
        return [ResultItem]::new($this.Name, $line, '', $line, $Command, $this, $Line);
    }

    [ResultItem]ConvertItem([Object]$item, [Switch]$Global, $Command)
    {
        [string]$json = ConvertTo-Json $item -Depth 3 -EnumsAsStrings -Compress;
        if($item -is [Microsoft.PowerShell.Commands.MemberDefinition]){
            $def=($item.Definition.Replace("System.Management.Automation.PSCustomObject $($item.Name)=@",'').Trim('{}'.ToCharArray()).Split(';'));

            foreach($line in $def){
                if($line.StartsWith('version')){
                    $parts=$line.Split('=');

                    [ResultItem]$resultItem = [ResultItem]::new($this.Name, $item.Name, $parts[1], $item.Name, '', '', $null, '');

                    $json = ConvertTo-Json $resultItem -Depth 3 -EnumsAsStrings -Compress;
                }
            }
        }

        if($json){
            return $this.ParseResultItem($json.ToString(), $Command, $Global);
        }

        return $item.toString();
    }

    [Object]ParseResults(
        [Object[]]$executeResults, 
        [string]$Command,
        [switch]$Install = $false,
        [switch]$AllRepos = $false,
        [switch]$Raw = $false,
        [switch]$Describe = $false,
        [switch]$Global = $false,
        [bool]$Verbose = $false)
    {
        $resultItems = [List[ResultItem]]::new();

        if ($Command -imatch 'search|list' )
        {
            foreach ($line in $executeResults)
            {
                [ResultItem]$item = $null;
  
                if ($line -is [string])
                {
                    $item = $this.ParseResultItem($line, $Command, $Global);
                }
                elseif ($line -is [RemoteException] -or $line -is [ErrorRecord])
                {
                    $item = $null;
                }
                else
                {
                    $item = $this.ConvertItem($line, $Global, $Command);
                }
  
                if ($item)
                {
                    if ($Describe.IsPresent -and $Describe)
                    {
                        $Description = $this.Invoke(
                            'info', 
                            $item.ID, 
                            '', 
                            '', 
                            $false, 
                            $AllRepos, 
                            $Raw, 
                            $false,
                            $Global,
                            $false, 
                            $false,
                            @());

                        if ($Description -is [Object[]])
                        {
                            $Description = $Description | Join-String -Separator ([System.Environment]::NewLine)
                        }

                        if ($Description -is [string])
                        {
                            $item.Description = $Description;
                        }
                    }
                    $resultItems.Add($item);
                }
            }
  
            $type = [ResultItem];
            $firstItem = GetFirstItem -OfType $type -Enum $resultItems

            if ($Install -and $firstItem)
            {
                $arguments = $firstItem.Command.Split(' ')
        
                if ($this.UseSudo)
                {
                    & sudo $this.Install $arguments
                }
                else
                {
                    & $this.Install $arguments
                }
            }

            if (($AllRepos.IsPresent -and -not $AllRepos -and -not $Raw) -or 
            (-not $AllRepos.IsPresent -and -not $Raw))
            {
                if ($Verbose)
                {
                    return $resultItems | Sort-Object -Property ID | Format-Table -AutoSize  
                }

                return $resultItems | Sort-Object -Property ID | Format-Table -AutoSize -Property Repo, Command
            }
            else
            {
                return $resultItems
            }
        }
        else
        {
            return $executeResults;
        }
    }

    [Object]Execute(
        [string]$Command, 
        [Object[]]$params,
        [switch]$Install = $false,
        [switch]$AllRepos = $false,
        [switch]$Raw = $false,
        [switch]$Describe = $false,
        [switch]$Global = $false,
        [bool]$Verbose = $false,
        [bool]$Sudo = $false)
    {
        $toExecute = $this.Command.Source;

        if ($Sudo)
        {
            $params = @($toExecute) + $params;
            $toExecute = 'sudo';
        }

        $executeResults = '';
        if ($this.IsScript)
        {
            Write-Verbose "[$($this.Name)] Invoke-Expression `"& `"$toExecute`" $params`"" -Verbose:$Verbose
            $executeResults = Invoke-Expression "& `"$toExecute`" $params"
        }
        else
        {
            Write-Verbose "[$($this.Name)] & $toExecute $params" -Verbose:$Verbose
            $executeResults = & $toExecute $params 2>&1

            try{
                $fromJson = $executeResults | ConvertFrom-Json -ErrorAction SilentlyContinue
                if($fromJson){
                    if($fromJson.dependencies){
                        $executeResults = @();
                        foreach($dep in $fromJson.dependencies){
                            $members = $dep | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue;
                            if($members){
                                foreach($member in $members){
                                    $executeResults += $member;
                                }
                            }
                        }
                    } else {
                        $executeResults = $fromJson;
                    }
                }
            } catch {}

            $this.ExitCode = $LASTEXITCODE;
        }

        if($this.ExitCode -ne 0){
            if($executeResults -is [string]){
                return $executeResults;
            }

            if($executeResults -is [ResultItem[]]){
                return $executeResults.Line
            }

            if($executeResults -is [ResultItem]){
                return $executeResults.Line
            }

            if($executeResults -is [Object[]]){
                [List[string]]$resultStrings = [List[string]]::new();

                foreach($item in $executeResults){
                    $resultStrings.Add("$item");
                }

                $resultString =  $resultStrings | Join-String -Separator "`n";

                if($resultString -imatch ('no [^\n]*package found')){
                    return $null;
                }

                return $resultString;
            }

            throw "``$toExecute $params`` resulted in error (exit code: $LASTEXITCODE)";
        }

        if ($env:IsWindows -ieq 'true')
        {
            & refreshenv
        }

        return $this.ParseResults(
            $executeResults, $Command, $Install, $AllRepos, $Raw, $Describe, $Global, $Verbose);
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        return $params;
    }

    [Object]Invoke(     
        [string]$Command = 'search',
        [string]$Name = $null,
        [string]$SubCommand = $null,
        [string]$Store = 'winget',
        [switch]$Install = $false,
        [switch]$AllRepos = $false,
        [switch]$Raw = $false,
        [switch]$Describe = $false,
        [bool]$Verbose = $false,
        [bool]$Exact = $false)
    {
        return $this.Invoke($Command, $Name, $SubCommand, `
            $Store, $Install, $AllRepos, $Raw, $Describe, $false, $Verbose, $Exact, `
            @());
    }

    [Object]Invoke(     
        [string]$Command = 'search',
        [string]$Name = $null,
        [string]$SubCommand = $null,
        [string]$Store = 'winget',
        [switch]$Install = $false,
        [switch]$AllRepos = $false,
        [switch]$Raw = $false,
        [switch]$Describe = $false,
        [switch]$Global = $false,
        [bool]$Verbose = $false,
        [bool]$Exact = $false,
        [Object[]]$OtherParameters = @())
    {
        $itemName = $Name;
        $itemCommand = $Command;
      
        if ($Name -eq '' -and -not($Command -imatch 'list|upgrade'))
        {
            $itemName = $Command;
            $itemCommand = 'search';
        }

        if ($Install)
        {
            $itemCommand = 'search'
        }

        $params = @()

        $Sudo = $this.UseSudo;

        Switch -regex ($itemCommand)
        {
        ('^search|find')
            {
                $params += $this.Search;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                $params += $itemName;
                $Sudo = $Sudo -and $False;
            }

        ('^install')
            {
                $params += $this.Install;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                $params += $itemName;
                $Sudo = $Sudo -and $True;
            }

        ('^upgrade')
            {
                $params += this.Upgrade;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                $params += $itemName;
                $Sudo = $Sudo -and $True;
            }

        ('^update')
            {
                $params += this.Update;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                $params += $itemName;
                $Sudo = $Sudo -and $True;
            }

        ('^uninstall|remove')
            {
                $params += $this.Uninstall;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                $params += $itemName;
                $Sudo = $Sudo -and $True;
            }

      ('^show|details|info')
            {
                $params += $this.Display;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                $params += $itemName;
                $Sudo = $Sudo -and $False;
            }
      
      ('^list')
            {
                $params += $this.List;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim() 
                }
                if ($itemName)
                {
                    $params += $itemName; 
                }
                $Sudo = $Sudo -and $False;
            }

            default
            {
                $params += $itemCommand;
                if ($SubCommand.Trim().Length -gt 0)
                {
                    $params += $SubCommand.Trim(); 
                }
                if ($itemName)
                {
                    $params += $itemName; 
                }
            }
        }

        if(-not $params[0]){
            throw "``$Command`` not supported for ``$($this.Repo)``";
        }

        if($OtherParameters){
            $params += $OtherParameters;
        }

        $params = $this.AddParameters($itemCommand, $Global, $params);

        if ($Exact)
        {
            $Raw = $true;
        }

        $results = $this.Execute($itemCommand, $params, $Install, $AllRepos, $Raw, $Describe, $Global, $Verbose, $Sudo)

        if(-not $results){
            return "`n[$($this.Executable)] No results.`n"
        }

        if (-not $Exact)
        {
            return $results
        }

        if (-not $AllRepos)
        {
            if ($Install)
            {
                $params = $this.AddParameters($Command, $Global, @($this.Install, $itemName));
                switch ($this.UseSudo)
                {
          ($true)
                    {
                        $results = & sudo $this.Command.Source $params 2>&1 
                    }
                    default
                    {
                        $results = & $this.Command.Source $params 2>&1 
                    }
                }

                return $results
            }
            else
            {
                if ($Verbose)
                {
                    return ($results | Where-Object ID -EQ $itemName | Format-Table -Property Repo, Command, Line );
                }
                else
                {
                    return ($results | Where-Object ID -EQ $itemName | Format-Table -Property Repo, Command );
                }
            }
        }
        else
        {
            return $results | Where-Object ID -EQ $itemName;
        }
    }
}

class AptManager : PackageManager
{
    AptManager() : base(
        'apt', 'apt', 'search', 'install',
        'upgrade', 'update', @('list', '--installed'), 'remove', 'info', $true
    )
    {
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        if ($Command -imatch 'list|info')
        {
            return $params;
        }
    
        return $params + '-y';
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        # golang-github-sahilm-fuzzy-dev/stable,oldstable,testing 0.1.0-1.1 all
        $regex = [Regex]::new('^([A-Za-z0-9_\-\.+]+)\/[A-Za-z0-9_\-\,]+\s+([A-Za-z0-9\.\-+]+)\s?');

        if ($regex.IsMatch($line))
        {
            $id = $regex.Match($line).Groups[1].Value.Trim();
            $ver = $regex.Match($line).Groups[2].Value.Trim();
            $desc = $null;
            $index = $line.IndexOf($id);
            $nme = $line.Substring(0, $index).Trim();
            $inst = '';
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "install $id=$ver" 
                }
                'list'
                {
                    $inst = "uninstall $id" 
                }
            }
    
            return [ResultItem]::new(
                "sudo $($this.Executable)", $id, $ver, $nme, $inst, $desc, $this, $Line
            );
        }

        return $null;
    }
}

class HomebrewManager : PackageManager
{
    [string]$Store = 'main';

    HomebrewManager() : base(
        'brew', 'brew', 'search', 'install',
        'upgrade', 'update', 'list', 'uninstall', 'info', $false
    )
    {
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        # golang-github-sahilm-fuzzy-dev/stable,oldstable,testing 0.1.0-1.1 all
        $regex = [Regex]::new('^([A-Za-z0-9_\-]+@?(\d*))');

        if ($regex.IsMatch($line))
        {
            $id = $regex.Match($line).Groups[1].Value.Trim();

            $ver = '';
            if ($regex.Match($line).Groups.Count -gt 2)
            {
                $ver = $regex.Match($line).Groups[2].Value.Trim();
            }

            $desc = $null;
            $inst = '';
            switch -regex ($Command)
            {
                'search'
                {
                    if ($ver.Length -eq 0)
                    {
                        $inst = "install $id";
                    }
                    else
                    {
                        $inst = "install $id@$ver";
                    }
                }
                'list'
                {
                    $inst = "uninstall $id";
                }
            }
    
            return [ResultItem]::new(
                $this.Executable, $id, $ver, $id, $inst, $desc, $this, $Line
            );
        }

        return $null;
    }
}

class SnapManager : PackageManager
{

    SnapManager() : base(
        'snap', 'snap', 'find', 'install',
        'upgrade', 'refresh', 'list', 'remove', 'info', $true
    )
    {
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        # golang-github-sahilm-fuzzy-dev/stable,oldstable,testing 0.1.0-1.1 all
        $regex = [Regex]::new('^(?!Name)([\w\d\-]+)\s+([\w\d\.\-+]+)\s+[\d\s]*\s*[^\s]*\s*[^\s]+\s+(.*)');

        if ($regex.IsMatch($line))
        {
            $id = $regex.Match($line).Groups[1].Value.Trim();

            $ver = '';
            if ($regex.Match($line).Groups.Count -gt 2)
            {
                $ver = $regex.Match($line).Groups[2].Value.Trim();
            }

            $desc = $null;
            if ($regex.Match($line).Groups.Count -gt 3)
            {
                $desc = $regex.Match($line).Groups[3].Value.Trim();
            }
            $inst = '';
            switch -regex ($Command)
            {
                'search'
                {
                    if ($ver.Length -eq 0)
                    {
                        $inst = "install $id";
                    }
                    else
                    {
                        $inst = "$($this.Install) $id";
                    }
                }
                'list'
                {
                    $inst = "$($this.Uninstall) $id";
                }
            }
    
            return [ResultItem]::new(
                "sudo $($this.Executable)", $id, $ver, $id, $inst, $desc, $this, $Line
            );
        }

        return $null;
    }
}

class WinGetManager : PackageManager
{
    [string]$Store = 'winget';
    [switch]$InteractiveParameter = $false;

    WinGetManager([string]$S, [switch]$I) : base(
        'winget', 'winget', 'search', 'install',
        'upgrade', 'update', 'list', 'uninstall', 'show', $false
    )
    {
        $this.Store = $s;
        $this.InteractiveParameter = $i;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        $regex = [Regex]::new('^.+\s+([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\s+([\d\.]+)\s?');

        if ($regex.IsMatch($line))
        {
            $id = $regex.Match($line).Groups[1].Value.Trim();
            $ver = $regex.Match($line).Groups[2].Value.Trim();
            $index = $line.IndexOf($id);
            $nme = $line.Substring(0, $index).Trim();
            $inst = '';
            $interactive = '';
            if ($this.InteractiveParameter.IsPresent -and 
                $this.InteractiveParameter.ToBool())
            {
                $interactive = '-i';
            }
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "install $id --version $ver --source $($this.Store) $interactive" 
                }
                'list'
                {
                    $inst = "uninstall $id" 
                }
            }
      
            return [ResultItem]::new(
                $this.Executable, $id, $ver, $nme, $inst, $null, $this, $Line
            );
        }

        return $null;
    }
}

class ScoopManager : PackageManager
{
    [string]$Store = 'main';

    ScoopManager([string]$S) : base(
        'scoop', 'scoop', 'search', 'install',
        'upgrade', 'update', 'list', 'uninstall', 'info', $false
    )
    {
        $this.Store = $s;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        $json = ConvertFrom-Json $Line;
        $ver = $json.version;
        $nme = $json.name;
        $inst = $Command;
        switch -regex ($Command)
        {
            'search'
            { 

                [string]$bucket = '';

                if ($this.Store)
                {
                    $bucket = "-bucket $($this.Store)";
                }

                switch ($line.Source.Length -gt 0)
                {
            ($True)
                    {
                        $bucket = "-bucket $($json.Source)"; 
                    }
                    default
                    { 
                    }
                }

                if ($ver)
                {
                    $inst = "$($this.Install) $($nme)@$($ver) $bucket".Trim();
                }
                else
                {
                    $inst = "$($this.Install) $nme $bucket".Trim();
                }
            }
            'list'
            {
                $inst = "$($this.Uninstall) $nme" 
            }
        }
        return [ResultItem]::new(
            $this.Executable, $nme, $ver, $nme, $inst, $null, $this, $Line
        );
    }
}

class ChocoManager : PackageManager
{

    ChocoManager() : base(
        'choco', 'choco', 'search', 'install',
        'upgrade', 'update', 'list', 'uninstall', 'info', $true
    )
    {
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        if ($Command -imatch 'list')
        {
            $params += '-l';
        }
    
        return $params;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        if($Line.Trim().IndexOf('packages installed.') -gt -1){
            return $null;
        }

        $index =  $line.IndexOf('[Approved]');
        if (($Command -imatch 'search' -and $index -gt -1) -or
            -not($Command -imatch 'search'))
        {
            if($index -gt -1){
                $line = $line.Substring(0, $line.IndexOf('[Approved]')).Trim();
            }
            
            $lastIndex = $line.LastIndexOf(' ');
            $nme = $line.Substring(0, $lastIndex).Trim();
            $ver = $line.Substring($lastIndex).Trim();
            $inst = $Command;
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "install $nme --version $ver -y" 
                }
                'list'
                {
                    $inst = "uninstall $nme" 
                }
            }
            return [ResultItem]::new(
                "sudo $($this.Executable)", $nme, $ver, $nme, $inst, $null, $this, $Line
            );
        }
  
        return $null;
    }
}

class NpmManager : PackageManager
{

    NpmManager() : base(
        'npm', 'npm', 'search', 'install',
        'upgrade', 'update', 'list', 'uninstall', 'view', $false
    )
    {
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        if ($Command -imatch 'search|find|list')
        {
            $params += '--json';
        }

        if($Global){
            $params += '-g'
        }
    
        return $params;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        [Object]$json = $null;

        try
        {
            $json = ConvertFrom-Json $Line -ErrorAction SilentlyContinue
        }
        catch
        {
        }

        if ($json)
        {
            $nme = $json.name
            $ver = $json.version
            $inst = $Command;
            $description = $json.description
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "install $nme@$ver" 
                }
                'list'
                {
                    $inst = "uninstall $nme" 
                }
            }

            if($Global -and $inst) { $inst = "$inst -g"; }

            return [ResultItem]::new(
                $this.Executable, $nme, $ver, $nme, $inst, $description, $this, $Line
            );
        }
  
        return $null;
    }
}

class NugetManager : PackageManager
{

    NugetManager() : base(
        'nuget', 'nuget', 'search', 'install',
        'update', 'update', 'list', 'uninstall', $null, $false
    )
    {
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        if ($Command -imatch 'details|info')
        {
            $params += '-Verbose';
        }
    
        return $params;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        $expression = '^>\s([@\w\d\-\/\.]+)\s\|\s([^\s]+)\s';
        # ^>\s([@\w\d\-\/\.]+)\s\|\s([^\s]+)\s
        if ($line -imatch $expression)
        {
            $regex = [Regex]::new($expression);
            $id = $regex.Match($line).Groups[1].Value.Trim();
            $ver = $regex.Match($line).Groups[2].Value.Trim();
            $nme = $id
            $inst = $Command;
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "install $id -Version $ver -NonInteractive" 
                }
                'list'
                {
                    $inst = "uninstall $id -NonInteractive" 
                }
            }
            return [ResultItem]::new(
                $this.Executable, $nme, $ver, $nme, $inst, $null, $this, $Line
            );
        }
  
        return $null;
    }
}


class DotnetManager : PackageManager
{

    DotnetManager() : base(
        'dotnet', 'dotnet', $null, 'add',
        'update', $null, $null, 'remove', $null, $false
    )
    {
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        $params =  @($params[0], 'package') + $params.Skip(1);
    
        return $params;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        $expression = '^>\s([@\w\d\-\/\.]+)\s\|\s([^\s]+)\s';
        # ^>\s([@\w\d\-\/\.]+)\s\|\s([^\s]+)\s
        if ($line -imatch $expression)
        {
            $regex = [Regex]::new($expression);
            $id = $regex.Match($line).Groups[1].Value.Trim();
            $ver = $regex.Match($line).Groups[2].Value.Trim();
            $nme = $id
            $inst = $Command;
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "install $id -Version $ver -NonInteractive" 
                }
                'list'
                {
                    $inst = "uninstall $id -NonInteractive" 
                }
            }
            return [ResultItem]::new(
                $this.Executable, $nme, $ver, $nme, $inst, $null, $this, $Line
            );
        }
  
        return $null;
    }
}

class DotnetToolManager : PackageManager
{

    DotnetToolManager() : base(
        'dotnet', 'dotnet', 'search', 'install',
        $null, 'update', 'list', 'uninstall', $null, $false
    )
    {
    }

    [Object[]]AddParameters([string]$Command,  [Switch]$Global, [Object[]]$params)
    {
        $params =  @('tool') + $params;

        if($Global -and -not ($Command -imatch 'search|find')){
            $params += '-g';
        }
    
        return $params;
    }

    [ResultItem]ParseResultItem([string]$Line, [string]$Command, [Switch]$Global)
    {
        $expression = '^(?!Package|\-)([@\w\d\-\/\.]+)[\t\s]+([^\s]+)';

        if ($line -imatch $expression)
        {
            $regex = [Regex]::new($expression);
            $id = $regex.Match($line).Groups[1].Value.Trim();
            $ver = $regex.Match($line).Groups[2].Value.Trim();
            $nme = $id
            $inst = $Command;
            switch -regex ($Command)
            {
                'search'
                {
                    $inst = "tool $($this.Install) $id" 
                }
                'list'
                {
                    $inst = "tool $($this.Uninstall) $id"
                }
            }

            if($Global -and $inst) { $inst = "$inst -g"; }

            return [ResultItem]::new(
                $this.Executable, $nme, $ver, $nme, $inst, $null, $this, $Line
            );
        }
  
        return $null;
    }
}