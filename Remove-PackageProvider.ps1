<#
.SYNOPSIS
    The function removes package providers
.DESCRIPTION
    Long description
.EXAMPLE
    Remove-PackageProvider -Name $providername -AllVersions
.EXAMPLE
    Remove-PackageProvider -InputObject $inputobject
.EXAMPLE
    Remove-PackageProvider -Name $providername -MinimumVersion 0.0.0.3
.EXAMPLE
    Remove-PackageProvider -Name $providername -MaximumVersion 0.0.0.2
.EXAMPLE
    Remove-PackageProvider -Name $providername -Undo
.INPUTS
    [String]
.OUTPUTS
    Output from this cmdlet (if any)
.NOTES
    ...
.COMPONENT
    ...
.ROLE
    ...
.FUNCTIONALITY
    (re)moves the directory with module
#>

class PackProv {
    # Name of PackageProvider
    [string] $Name

    # Version of PackageProvider
    [string] $Version

    # Path where all versions placed
    [string] $SourcePathByName

    # Path where current version placed
    [string] $SourcePathByVersion

    # Path to backup all versions
    [string] $BackupPathByName

    # Path to backup current version
    [string] $BackupPathByVersion

    # Method: Gets name from [Microsoft.PackageManagement.Implementation.PackageProvider]
    [void] GetNameFromObject($InputObject) {
        $this.Name = $InputObject.ProviderName
    }

    # Method: Gets version from [Microsoft.PackageManagement.Implementation.PackageProvider] as a string
    [void] GetVersionFromObject($InputObject) {
        if ($InputObject.Version) {
            $this.Version = $InputObject.Version.ToString()
        } else {
            $this.Version = "0.0.0.0"
        }
    }

    # Method: Gets source path with version from [Microsoft.PackageManagement.Implementation.PackageProvider]
    [void] GetSourcePathByVersion($InputObject) {
        $this.SourcePathByVersion = Split-Path -Path $InputObject.ProviderPath -Parent
    }

    # Method: Gets source path by name from [Microsoft.PackageManagement.Implementation.PackageProvider]
    [void] GetSourcePathByName($InputObject) {
        if (!$this.SourcePathByVersion) {
            $this.GetSourcePathByVersion($InputObject)
        }
        $this.SourcePathByName = Split-Path -Path $this.SourcePathByVersion -Parent
    }

    # Method: Sets backup path by name (appends name of PackageProvider to root backup directory)
    [void] SetBackupPathByName([string]$BackupRoot) {
        $this.BackupPathByName = Join-Path -Path $BackupRoot -ChildPath $this.Name
    }

    # Method: Sets backup path by version (appends version of PackageProvider to backup directory)
    [void] SetBackupPathByVersion([string]$BackupRoot) {
        if (!$this.BackupPathByName) {
            $this.SetBackupPathByName()
        }
        $this.BackupPathByVersion = Join-Path -Path $this.BackupPathByName -ChildPath $this.Version
    }

    # Constructor: creates an empty object
    PackProv(){}

    # Constructor: creates an object from PSCustomObject
    PackProv([PSCustomObject] $CustomObject) {
        $this.Name = $CustomObject.Name
        $this.Version = $CustomObject.Version
        $this.SourcePathByName = $CustomObject.SourcePathByName
        $this.SourcePathByVersion = $CustomObject.SourcePathByVersion
        $this.BackupPathByName = $CustomObject.BackupPathByName
        $this.BackupPathByVersion = $CustomObject.BackupPathByVersion
    }
    
    # Constructor: Creates a new PackProv object from input object [Microsoft.PackageManagement.Implementation.PackageProvider]
    PackProv([Microsoft.PackageManagement.Implementation.PackageProvider] $InputObject) {
        $this.GetNameFromObject($InputObject)
        $this.GetVersionFromObject($InputObject)
        $this.GetSourcePathByName($InputObject)
        $this.GetSourcePathByVersion($InputObject)
    }
}

function Get-ProvidersInstalled {
    param (
        # Name for search
        [Parameter()]
        [string]
        $NameS,
        
        # Version for search - exact
        [Parameter()]
        [string]
        $VersionExact,

        # Version for search - keep
        [Parameter()]
        [string]
        $VersionKeep,

        # Version for search - min
        [Parameter()]
        [string]
        $VersionMin,
        
        # Version for search - max
        [Parameter()]
        [string]
        $VersionMax
    )
    
    [array]$ProvidersInstalledAll = Get-PackageProvider -Name $NameS -ListAvailable
    [array]$VersionsAll = $ProvidersInstalledAll.ForEach({$_.Version.ToString()})

    if ($VersionExact) {
        [array]$VersionsToRemove = $VersionsAll.Where({$_ -eq $VersionExact})
    } elseif ($VersionKeep) {
        [array]$VersionsToRemove = $VersionsAll.Where({$_ -ne $VersionKeep})
    } elseif ($VersionMin) {
        [array]$VersionsToRemove = $VersionsAll.Where({$_ -lt $VersionMin})
    } elseif ($VersionMax) {
        [array]$VersionsToRemove = $VersionsAll.Where({$_ -gt $VersionMax})
    } elseif ($VersionMin -and $VersionMax) {
        [array]$VersionsToRemove = $VersionsAll.Where({($_ -lt $VersionMin) -and ($_ -gt $VersionMax)})
    } else {
        [array]$VersionsToRemove = $VersionsAll
    }

    [array]$ProvidersToRemove = $ProvidersInstalledAll.Where({$_.Version -in $VersionsToRemove})

    return $ProvidersToRemove
}

function Convert-PackProvider {
    param (
        # Input object of type [Microsoft.PackageManagement.Implementation.PackageProvider]
        [Parameter()]
        [Microsoft.PackageManagement.Implementation.PackageProvider]
        $inputObject,

        # Path to root backup directory
        [Parameter()]
        [string]
        $backupRoot
    )
    
    $PackProvider = [PackProv]::new($inputObject)
    $PackProvider.SetBackupPathByName($backupRoot)
    $PackProvider.SetBackupPathByVersion($backupRoot)

    return $PackProvider
}

function Create-BackupDirs {
    param (
        # PackageProvider
        [Parameter()]
        [PackProv]
        $PckProv,

        # Invert
        [Parameter()]
        [switch]
        $Invert
    )

    if ($Invert) {
        [string]$pVer = $PckProv.SourcePathByVersion
        [string]$pName = $PckProv.SourcePathByName
    } else {
        [string]$pVer = $PckProv.BackupPathByVersion
        [string]$pName = $PckProv.BackupPathByName
    }
    
    if (!(Test-Path -Path $pVer)) {
        if (!(Test-Path -Path $pName)) {
            [System.IO.Directory]::CreateDirectory($pName)
            [System.IO.Directory]::CreateDirectory($pVer)
        } else {
            [System.IO.Directory]::CreateDirectory($pVer)
        }
    }
}

function Move-Providers {
    param (
        # Source path
        [Parameter()]
        [string]
        $pathSrc,

        # Destination path
        [Parameter()]
        [string]
        $pathDest
    )
    if (Test-Path -Path $pathSrc) {
        Get-ChildItem -Path $pathSrc -Recurse -Force | Move-Item -Destination $pathDest -Force
    } else {
        Write-Error "Nothing found at path: $pathSrc !"
    }
}

function Remove-PackageProvider {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        # PackageProvider from input object. Removes certain provider of certain version.
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true,
        ParameterSetName="PackageByInputObject")]
        [Microsoft.PackageManagement.Implementation.PackageProvider]
        $InputObject,

        # PackageProvider name by search
        [Parameter(Mandatory=$true,
        ParameterSetName="PackageBySearch")]
        [string]
        $Name,

        # PackageProvider - remove ALL VERSIONS!
        [Parameter(ParameterSetName="PackageBySearch")]
        [switch]
        $AllVersions,

        # PackageProvider version by search - exact match. Provider with specified version will be removed!
        [Parameter(ParameterSetName="PackageBySearch")]
        [string]
        $RemoveCertainVersion,

        # PackageProvider version by search - exact match
        [Parameter(ParameterSetName="PackageBySearch")]
        [string]
        $RequiredVersion,

        # PackageProvider version by search - minimum version. All providers with version number less than this - will be removed!
        [Parameter(ParameterSetName="PackageBySearch")]
        [string]
        $MinimumVersion,

        # PackageProvider version by search - maximum version. All providers with version number greater than this - will be removed!
        [Parameter(ParameterSetName="PackageBySearch")]
        [string]
        $MaximumVersion,

        # Move or remove
        [Parameter()]
        [ValidateSet("Move","Remove","Undo")]
        [string]
        $AreYouSure,

        # Backup path
        [Parameter()]
        [string]
        $Backup,

        # Logfile
        [Parameter()]
        [string]
        $LogName
    )
    
    begin {
        if ($InputObject) {
            $Name = $InputObject.ProviderName
            $RemoveCertainVersion = $InputObject.Version.ToString()
        }

        if (!$AreYouSure) {
            $AreYouSure = "Move"
        }

        if (!$Backup) {
            $Backup = Join-Path -Path (Resolve-Path -Path $env:HOMEPATH).Path -ChildPath "PackageProvidersBackup"
            if (!(Test-Path -Path $Backup)) {
                [System.IO.Directory]::CreateDirectory($Backup)
            }
        }

        if (!$LogName) {
            $LogName = "BackupLog.txt"
        }

        [string]$LogPath = Join-Path -Path $Backup -ChildPath $LogName

        if ($AllVersions) {
            $RemoveCertainVersion = $null
            $RequiredVersion = $null
            $MinimumVersion = $null
            $MaximumVersion = $null
        } elseif ($RemoveCertainVersion -or $RequiredVersion) {
            $MinimumVersion = $null
            $MaximumVersion = $null
            if ($RemoveCertainVersion) {
                $RequiredVersion = $null
            } else {
                $RemoveCertainVersion = $null
            }
        } elseif ($MinimumVersion -or $MaximumVersion -or ($MinimumVersion -and $MaximumVersion)) {
            $RemoveCertainVersion = $null
            $RequiredVersion = $null
        } elseif ($AreYouSure -ne "Undo") {
            Write-Error "No versions specified!"
            break
        }
    }
    
    process {
        [array]$prToRemove = Get-ProvidersInstalled -NameS $Name -VersionExact $RemoveCertainVersion -VersionKeep $RequiredVersion -VersionMin $MinimumVersion -VersionMax $MaximumVersion -Verbose
        [array]$convertedProviders = $prToRemove.ForEach({Convert-PackProvider -inputObject $_ -backupRoot $Backup})

        switch ($AreYouSure) {
            "Move" {
                $csvContent = @()
                foreach ($provider in $convertedProviders) {
                    Create-BackupDirs -PckProv $provider
                    $csvRow = ConvertTo-Csv -InputObject $provider -Delimiter ";" -NoTypeInformation
                    $csvContent += $csvRow
                    Move-Providers -pathSrc $provider.SourcePathByVersion -pathDest $provider.BackupPathByVersion
                    if (!(Get-ChildItem -Path $provider.SourcePathByVersion)) {
                        Remove-Item -Path $provider.SourcePathByVersion -Recurse -Force -Confirm:$false
                    }
                    if (!(Get-ChildItem -Path $provider.SourcePathByName)) {
                        Remove-Item -Path $provider.SourcePathByName -Recurse -Force -Confirm:$false
                    }
                }
                $csvContent | Select-Object -Unique | Out-File -FilePath $LogPath -Encoding utf8
            }
            "Remove" {
                foreach ($provider in $convertedProviders) {
                    Remove-Item -Path $provider.SourcePathByVersion -Recurse -Force -Confirm:$false
                    if (!(Get-ChildItem -Path $provider.SourcePathByName)) {
                        Remove-Item -Path $provider.SourcePathByName -Recurse -Force -Confirm:$false
                    }
                }
            }
            "Undo" {
                $csvFile = Get-Content -Path $LogPath
                $deletedProviders = ConvertFrom-Csv -InputObject $csvFile -Delimiter ";"
                foreach ($provider in $deletedProviders) {
                    $obj = [PackProv]::new($provider)
                    Create-BackupDirs -PckProv $obj -Invert
                    Move-Providers -pathSrc $obj.BackupPathByVersion -pathDest $obj.SourcePathByVersion
                }
            }
        }
    }
    
    end {}
}
