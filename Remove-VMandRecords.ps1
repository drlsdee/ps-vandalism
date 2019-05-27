<#
.SYNOPSIS
    This function removes virtual machines and related records in AD domain, DNS zone, DHCP scopes
.DESCRIPTION
    This function removes virtual machines and related records in AD domain, DNS zone, DHCP scopes
.EXAMPLE
    Remove-VMandRecords -SearchMask "computer" -DNSServer "dns00.domain.com"
    Removes VM "computer"
.EXAMPLE
    Remove-VMandRecords -SearchMask "computer" -DNSServer "dns00.domain.com" -Mask
    Removes all VM which names are matches the mask
#>

function Remove-VMandRecords {
    [CmdletBinding()]
    param (
        # Name of VM(s) to remove.
        [Parameter(Mandatory=$true)]
        [string]
        $SearchMask,

        # Name of DNS server
        [Parameter(Mandatory=$true)]
        [string]
        $DNSServer,

        # If set, searches any VMs which names are match.
        [Parameter()]
        [switch]
        $Mask
    )
    
    begin {
        $DHCPinDC = Get-DhcpServerInDC -Verbose
        if ($Mask) {
            $VMToKill = (Get-SCVirtualMachine | Where-Object {$_.Name -match $SearchMask})
        } else {
            $VMToKill = (Get-SCVirtualMachine | Where-Object {$_.Name -eq $SearchMask})
        }
    
        if ($VMToKill -eq $null) {
            Write-Host "There are no VM with name" $SearchMask
        }

        class RecordsToKill {
            [string]$DNSName
            [string]$DistinguishedName
            [array]$v4Subnets
            [array]$MACAddresses
    
            RecordsToKill([Microsoft.SystemCenter.VirtualMachineManager.VMBase]$VM){
                $tmp = Get-ADComputer -Identity $VM.Name
                if ($VM.ComputerName) {
                    $this.DNSName = $VM.ComputerName
                } else {
                    $this.DNSName = $tmp.DNSHostName
                }
                $this.DistinguishedName = $tmp.DistinguishedName
                $this.MACAddresses = $VM.VirtualNetworkAdapters.MACAddress.Replace(':','-')
                $this.v4Subnets = $VM.VirtualNetworkAdapters.IPv4Subnets
            }
        }

        function Remove-Records {
            [CmdletBinding(SupportsShouldProcess=$true)]
            param (
                [Parameter(ValueFromPipeline=$true,
                ValueFromPipelineByPropertyName=$true)]
                [RecordsToKill]$object
            )
    
            $nameSplit = $object.DNSName.Split('.')
            $zoneName = $nameSplit[1..($namesplit.Length - 1)] -join '.'
            $hostDNSName = $nameSplit[0]
            Remove-SCVirtualMachine -VM $hostDNSName -Force -Confirm:$false -WhatIf
            if (Get-DnsServerResourceRecord -ComputerName $DNSServer -ZoneName $zoneName -Name $hostDNSName) {
                Remove-DnsServerResourceRecord -ComputerName $DNSServer -ZoneName $zoneName -Name $hostDNSName -Force -RRType A -Confirm:$false -WhatIf
            } else {
                Write-Host "There are no records for" $object.DNSName
            }
            if ($object.DistinguishedName) {
                Remove-ADComputer -Identity $object.DistinguishedName -Confirm:$false -WhatIf
            } else {
                Write-Host "There is no DName for" $object.DNSName
            }
            if ($object.v4Subnets) {
                foreach ($net in $object.v4Subnets) {
                    [string]$netToString = $net.NetworkAddress.ToString()
                    $object.MACAddresses.ForEach({
                        if (Get-DhcpServerv4Lease -ComputerName $DHCPinDC.DnsName -ScopeId $netToString -ClientId $_) {
                            Remove-DhcpServerv4Lease -ComputerName $DHCPinDC.DnsName -ScopeId $netToString -ClientId $_ -Confirm:$false -WhatIf
                        } else {
                            Write-Host "There are no known leases for" $object.DNSName "with MAC address" $_
                        }
                    })
                }
            } else {
                Write-Host "There are no known subnets for" $object.DNSName
            }
            
        }
    }
    
    process {
        $ObjectToKill = $VMToKill.ForEach({
            [RecordsToKill]::new($_)
            Write-Host "New object created"
        })
    }
    
    end {
        $ObjectToKill.ForEach({Remove-Records $_ -WhatIf})
    }
}