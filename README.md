# packagefactory-gui-powershell

A PowerShell **WinForms GUI** wrapped around a fork of Aaron Parker's
[PackageFactory](https://github.com/aaronparker/packagefactory), for building Microsoft
Intune Win32 (`.intunewin`) packages from manifests and importing them into a tenant.

- **GUI** — `packagefactory-gui-powershell/` — pick a tenant + app and build/import. See its [README](packagefactory-gui-powershell/README.md).
- **Engine + package catalog** — `packagefactory/` (git submodule): `New-Win32Package.ps1`, the `packages/` manifests, and the PSADT toolkit.

## Application packaging uses PSAppDeployToolkit **v4**

All PSADT packages (the `TSADrucker*` printers, Adobe Reader, HP debloat) use
`Invoke-AppDeployToolkit.ps1`. Toolkit binaries are **not** committed — after cloning, drop a
current **PSADT v4** release into `packagefactory/PSAppDeployToolkit/Toolkit/` (it must contain
`Invoke-AppDeployToolkit.exe` and the `PSAppDeployToolkit/` module) before building.

See **[`CLAUDE.md`](CLAUDE.md)** for the architecture, packaging flow, package types, and gotchas.

## Requirements

Windows-only: Windows PowerShell 5.1, and the `Evergreen`, `VcRedist`, and `IntuneWin32App` modules.
