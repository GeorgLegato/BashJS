# BashJS

BashJS is an experimental alternative to running JavaScript on NodeJS. Instead of depending on the Node runtime, the goal is to build a lightweight ecosystem that leverages the existing Bash interpreter.

## Tools

- **BPM (BashJS Package Manager)** – a `npm` replacement for managing BashJS packages
- **Declarative Imports** – specify dependencies that BPM can fetch and install
- **Transpiler** – ability to convert JavaScript modules or npm packages to Bash/BPM format

## Design Approach

The project aims to replicate useful parts of the NodeJS ecosystem using Bash tools:

1. **Package Management** – packages are installed and resolved through BPM, which mirrors `npm` functionality.
2. **Standard Modules** – Bash scripts providing equivalents of Node's `fs`, `path`, etc.
3. **CLI Interpreter** – run BashJS projects directly through the existing Bash shell.
4. **Asynchronous Utilities** – features like background jobs to emulate Node's async model.
5. **Tooling** – scripts to transpile JavaScript to Bash and to run tests.

## Planned Features / TODOs

- `bpm init`, `bpm install` and other commands inspired by `npm`
- Import syntax in Bash to load BPM packages
- Conversion of JavaScript packages to BPM-compatible scripts
- Testing framework for BashJS modules
- Cross-platform support (GNU/Linux, macOS, etc.)
- Documentation and examples

BashJS is a work in progress. Contributions and ideas are welcome.

## Shielded VM MSI Installer Prototype

This repository now includes a WiX Toolset installer definition that provisions a shielded Hyper-V generation 2 virtual machine. The workflow is split across two files in the `installer/` directory:

- `ShieldedVMInstaller.wxs` – WiX authoring that copies the provisioning script and executes it from a deferred custom action.
- `ConfigureShieldedVM.ps1` – PowerShell automation that enables Hyper-V, discovers the HTTPS-capable network adapter, creates an external switch, downloads the appliance VHDX, and enforces vTPM, Secure Boot, and shielding before starting the VM.

### Building the MSI

1. Install the WiX Toolset (v3.14 or newer) and ensure `candle.exe` and `light.exe` are available.
2. Provide the location of `WixCA.dll` when compiling and pass the repository root through the `ProjectDir` binder variable so the provisioning script can be resolved:

   ```powershell
   $wixPath = "C:\Program Files (x86)\WiX Toolset v3.14\bin"
   $projectRoot = Get-Location
   candle.exe -dProjectDir="${projectRoot}\" -dWixCATarget="$wixPath\WixCA.dll" installer\ShieldedVMInstaller.wxs
   light.exe -dProjectDir="${projectRoot}\" -dWixCATarget="$wixPath\WixCA.dll" ShieldedVMInstaller.wixobj -o ShieldedVMInstaller.msi
   ```

3. Override public properties as needed at install time:

   ```powershell
   msiexec /i ShieldedVMInstaller.msi APPLIANCEURL="https://example.com/secure-appliance.vhdx" VMNAME="SecureAppliance" SHIELDINGDATAFILE="C:\Secrets\ApplianceShielding.pdk"
   ```

> **Note:** The provisioning script requires administrative privileges and will return exit code `3010` if a reboot is required to complete Hyper-V activation.
