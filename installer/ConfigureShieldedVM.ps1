[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ApplianceUrl,

    [Parameter(Mandatory=$true)]
    [string]$VmName,

    [Parameter()]
    [string]$ShieldingDataPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString('s')
    Write-Host "[$timestamp][ShieldedVMInstaller] $Message"
}

try {
    Write-Log 'Importing Hyper-V module.'
    Import-Module Hyper-V -ErrorAction Stop

    $rebootRequired = $false

    Write-Log 'Ensuring Hyper-V role is enabled.'
    $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
    if ($hyperVFeature.State -ne 'Enabled') {
        Write-Log 'Hyper-V feature is disabled. Enabling...'
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
        $rebootRequired = $true
    } else {
        Write-Log 'Hyper-V feature already enabled.'
    }

    Write-Log 'Validating virtualization support for generation 2 VMs.'
    $platformData = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    if (-not $platformData.SecondLevelAddressTranslationExtensions) {
        throw 'SLAT support is required for Generation 2 virtual machines.'
    }
    if (-not $platformData.VirtualizationFirmwareEnabled) {
        throw 'Virtualization support is disabled in firmware. Enable Intel VT-x or AMD-V in BIOS/UEFI and retry.'
    }

    Write-Log 'Discovering internet-facing network adapter (HTTPS:443).' 
    $testUri = [Uri]'https://www.msftconnecttest.com/connecttest.txt'
    $candidateAdapters = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up'
    $internetAdapter = $null
    foreach ($adapter in $candidateAdapters) {
        $testResult = Test-NetConnection -InterfaceAlias $adapter.Name -ComputerName $testUri.Host -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($testResult.TcpTestSucceeded) {
            $internetAdapter = $adapter
            break
        }
    }

    if (-not $internetAdapter) {
        throw 'Unable to find an active network adapter with HTTPS connectivity.'
    }

    Write-Log "Internet-enabled adapter '$($internetAdapter.Name)' selected."

    $registryPath = 'HKLM:\SOFTWARE\ShieldedVMInstaller'
    if (-not (Test-Path $registryPath)) {
        Write-Log 'Creating installer registry hive.'
        New-Item -Path $registryPath -Force | Out-Null
    }

    New-ItemProperty -Path $registryPath -Name 'InternetAdapter' -PropertyType String -Value $internetAdapter.Name -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name 'InternetAdapterDescription' -PropertyType String -Value $internetAdapter.InterfaceDescription -Force | Out-Null

    Write-Log 'Provisioning or reusing an external Hyper-V virtual switch bound to the selected adapter.'
    $existingSwitch = Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue | Where-Object {
        $_.NetAdapterInterfaceDescription -eq $internetAdapter.InterfaceDescription -or $_.NetAdapterName -eq $internetAdapter.Name
    } | Select-Object -First 1

    if (-not $existingSwitch) {
        $switchName = "ShieldedVM-$($internetAdapter.Name)"
        Write-Log "Creating external virtual switch '$switchName'."
        $existingSwitch = New-VMSwitch -Name $switchName -NetAdapterName $internetAdapter.Name -AllowManagementOS $true -Notes 'Created by Shielded VM MSI installer.'
    } else {
        $switchName = $existingSwitch.Name
        Write-Log "Reusing existing virtual switch '$switchName'."
    }

    New-ItemProperty -Path $registryPath -Name 'VMSwitch' -PropertyType String -Value $switchName -Force | Out-Null

    Write-Log 'Staging VM appliance image.'
    $stagingRoot = Join-Path $env:ProgramData 'ShieldedVMInstaller'
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    $applianceFileName = [System.IO.Path]::GetFileName((New-Object System.Uri($ApplianceUrl)).AbsolutePath)
    if ([string]::IsNullOrEmpty($applianceFileName) -or $applianceFileName -eq '/') {
        $applianceFileName = 'appliance.vhdx'
    }
    $appliancePath = Join-Path $stagingRoot $applianceFileName

    if (-not (Test-Path $appliancePath)) {
        Write-Log "Downloading appliance image from $ApplianceUrl to $appliancePath."
        Invoke-WebRequest -Uri $ApplianceUrl -OutFile $appliancePath -UseBasicParsing
    } else {
        Write-Log "Appliance image already present at $appliancePath."
    }

    Write-Log 'Creating or updating the virtual machine definition.'
    $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
    if ($null -eq $vm) {
        Write-Log "Creating new Generation 2 virtual machine '$VmName'."
        $vm = New-VM -Name $VmName -Generation 2 -VHDPath $appliancePath -SwitchName $switchName -MemoryStartupBytes 4GB
    } else {
        if ($vm.Generation -ne 2) {
            throw "Existing VM '$VmName' is not Generation 2. Cannot continue."
        }
        Write-Log 'VM already exists. Ensuring configuration is up to date.'
        $currentDisk = (Get-VMHardDiskDrive -VMName $VmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -ErrorAction SilentlyContinue)
        if ($currentDisk -and ($currentDisk.Path -ne $appliancePath)) {
            Set-VMHardDiskDrive -VMName $VmName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $appliancePath
        }
        Connect-VMNetworkAdapter -VMName $VmName -SwitchName $switchName
    }

    Write-Log 'Enabling virtualization extensions for nested workloads.'
    Set-VMProcessor -VMName $VmName -ExposeVirtualizationExtensions $true -ErrorAction Stop

    Write-Log 'Applying secure boot and vTPM configuration.'
    Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows' -ErrorAction Stop
    if (-not (Get-VMKeyProtector -VMName $VmName -ErrorAction SilentlyContinue)) {
        Write-Log 'Creating local key protector.'
        Set-VMKeyProtector -VMName $VmName -NewLocalKeyProtector -ErrorAction Stop
    }
    Enable-VMTPM -VMName $VmName -ErrorAction Stop | Out-Null

    Write-Log 'Enforcing shielding policies.'
    Set-VMSecurity -VMName $VmName -ShieldingRequired $true -SecureBoot On -TpmEnabled $true -EncryptStateAndVmMigrationTraffic $true -ErrorAction Stop
    if ($ShieldingDataPath) {
        if (-not (Test-Path $ShieldingDataPath)) {
            throw "Shielding data file '$ShieldingDataPath' was not found."
        }
        Write-Log "Importing shielding data from $ShieldingDataPath."
        Import-VMShieldingData -ShieldingDataFilePath $ShieldingDataPath -VmName $VmName -ErrorAction Stop
        Set-VMSecurity -VMName $VmName -Shielding On -ErrorAction Stop
    } else {
        Write-Log 'No shielding data provided. Enabling shielding with locally generated key protector.'
        Set-VMSecurity -VMName $VmName -Shielding On -ErrorAction Stop
    }

    Write-Log 'Disabling automatic checkpoints for deterministic state.'
    Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false -ErrorAction Stop

    Write-Log 'Booting the shielded virtual machine.'
    if ((Get-VM -Name $VmName).State -ne 'Running') {
        Start-VM -Name $VmName -ErrorAction Stop | Out-Null
    }

    if ($rebootRequired) {
        Write-Log 'A system reboot is required to finalize Hyper-V role activation.'
        exit 3010
    }

    exit 0
}
catch {
    $errorMessage = $_.Exception.Message
    if ($_.Exception.InnerException) {
        $errorMessage = "$errorMessage`n$($_.Exception.InnerException.Message)"
    }
    Write-Error $errorMessage
    exit 1
}
