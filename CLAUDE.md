# CLAUDE.md — PackageFactory GUI (PowerShell)

Guidance for working in this repo. This is a fork/combination of **stealthpuppy's
PSPackageFactory** plus a home-grown **WinForms GUI** that builds Intune Win32
(`.intunewin`) packages from manifests and imports them into Microsoft Intune.

## Layout

| Path | What it is |
|------|------------|
| `packagefactory/` | The packaging engine (fork of PSPackageFactory). |
| `packagefactory/New-Win32Package.ps1` | **The engine.** Reads a package's `App.json`, downloads/stages the payload, builds the `.intunewin`, and (with `-Import`) calls the import script. Most packaging bugs live here. |
| `packagefactory/New-Win32Package.psm1` | Helper functions: `Test-IntuneWin32App`, `Get-MsiProductCode`, `Set-ScriptSignature`. |
| `packagefactory/scripts/Create-Win32App.ps1` | Imports a built `.intunewin` into Intune using the `App.json` (detection rules, assignments, install/uninstall commands). |
| `packagefactory/packages/App/<Name>/App.json` | Per-app manifest (metadata, `PackageInformation`, detection rules, install command). |
| `packagefactory/packages/App/<Name>/Source/` | Per-app source: the deploy script and any static payload. |
| `packagefactory/PSAppDeployToolkit/Toolkit/` | The PSADT toolkit injected into PSADT packages. **Must be a PSADT v4 release** (ships `Invoke-AppDeployToolkit.exe` + the `PSAppDeployToolkit\` module + `Config`/`Assets`/`Strings`). Binaries are downloaded fresh, not committed. |
| `packagefactory/output/` | Working directory: `output/<Name>/Source` (staging) and `output/<Name>/Output` (the `.intunewin`). |
| `packagefactory-gui-powershell/packagefactory.ps1` | The WinForms GUI. Lets you pick apps + tenant and runs `New-Win32Package.ps1`. |
| `packagefactory-gui-powershell/packagefactory-config.json` | Entra app (ClientId/ClientSecret) + tenant IDs + paths. **Gitignored — never commit.** |

## PSAppDeployToolkit: this repo is **v4** (migrated from v3)

All PSADT packages here are **v4** — the deploy script is `Source/Invoke-AppDeployToolkit.ps1`
(module-based: `Open-ADTSession` + `Install/Uninstall/Repair-ADTDeployment` functions) and the
manifest declares `"SetupFile": "Invoke-AppDeployToolkit.exe"` with install commands like
`Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`.

The 33 packages were migrated from PSADT **v3** (`Deploy-Application.ps1`) to **v4** — the 31
`TSADrucker*` printer packages, `AdobeAcrobatReaderDC`, and `UninstallHPTrash`. The 31 printers
were regenerated from `TSADruckerTemplate/Source/Invoke-AppDeployToolkit.ps1` by substituting two
per-package tokens: the **server share** (e.g. `tsaPR-B`, used in `\\tsaps1\…` printer operations)
and the **uppercase id** (e.g. `TSAPR-B`, used in `$adtSession.AppName` and the
`TSAPrinter<id>.ps1.tag` detection marker). To touch all printers, edit the template and regenerate.

> **⚠️ The Toolkit folder must be v4.** `New-Win32Package.ps1` copies `PSAppDeployToolkit/Toolkit/*`
> into each package at build time. It **must** contain a PSADT **v4** release (with
> `Invoke-AppDeployToolkit.exe` and the `PSAppDeployToolkit/` module folder). If it still holds the
> old v3 layout (`Deploy-Application.exe`), packaging fails with *"Unable to detect specified setup
> file 'Invoke-AppDeployToolkit.exe'"*. Binaries are downloaded fresh (not committed), so after a
> clone you must drop a v4 toolkit into `Toolkit/`.

The engine still contains a **dormant v3 branch** (detects `Source/Deploy-Application.ps1`) as a
safety fallback. It is unused now that every package is v4, but don't remove it — an upstream sync
that reverts detection would otherwise silently re-break any v3 package.

## Package types (how the engine decides what to do)

Detection is by files present in the package's `Source/` (checked in this order):

1. **PSADT v4** — `Source/Invoke-AppDeployToolkit.ps1` exists → inject the v4 toolkit; `SetupFile` forced to `Invoke-AppDeployToolkit.exe`. **(33 packages)**
2. **PSADT v3** — `Source/Deploy-Application.ps1` exists → inject a v3 toolkit; `SetupFile` forced to `Deploy-Application.exe`. **(dormant fallback — 0 packages)**
3. **Install.json** — `Source/Install.json` exists → copy the template `Install.ps1`. **(~60 packages)**
4. **Raw** — none of the above → package the downloaded/static installer directly (MSI/EXE/PS).

Note: `AdobeAcrobatReaderDC` sets `SetupFile` in `App.json` to `Invoke-AppDeployToolkit.exe` for the
package build, but its *runtime* install reads the actual downloaded installer name from
`Files\Install.json` and launches it via `Start-ADTProcess`. If Adobe fails, check that the
Evergreen download and its `Install.json` land in the package's `Files\` folder.

## Packaging flow (per app)

`App.json` → `Test-IntuneWin32App` (skip if already in Intune unless `-Force`) → stage
`output/<Name>/Source` (inject toolkit if PSADT) → run `Application.Filter`
(Evergreen / VcRedist download, or empty ` ` = payload already in Source) → build
`.intunewin` into `output/<Name>/Output` → if `-Import`, refresh token and call
`Create-Win32App.ps1`.

## How to run / debug

- **GUI:** run `packagefactory-gui-powershell/packagefactory.ps1` (Windows PowerShell 5.1;
  needs the `Evergreen`, `VcRedist`, `IntuneWin32App` modules). It `Set-Location`s to
  `packagefactory/` and calls `.\New-Win32Package.ps1` — so the default
  `-PSAppDeployToolkit` path (`$PSScriptRoot\PSAppDeployToolkit\Toolkit`) resolves correctly
  even though the GUI lives in a sibling folder.
- **Single package, CLI:** `cd packagefactory; .\New-Win32Package.ps1 -Application <Name> -Type App -Path .\packages -WorkingPath .\output` (add `-Import` to push, `-Force` to rebuild an existing version).
- **This is a Windows-only pipeline** (`IntuneWin32AppUtil.exe`, PSADT, Windows PowerShell). Do not expect it to run under WSL/Linux.

## Other known gotchas

- **Stale `output\<Name>\Source`:** the GUI does not clean the working Source folder between
  runs, so a failed run leaves files behind → `WARNUNG: '...Source' is not empty. Package may
  included extra files`. Usually harmless (copies use `-Force`), but if a build looks wrong,
  delete `output/<Name>/` and retry.
- **`Evergreen app functions are out of date. Please run 'Update-Evergreen'`** — benign; it just
  means the local Evergreen manifest cache is older than the released version.
- **Locale/token bug (already fixed in code):** on non-US locales (de-DE) the IntuneWin32App
  1.5.0 blob upload misparsed the token expiry and fell back to an interactive `ClientID:` prompt.
  `New-Win32Package.ps1` pins `InvariantCulture` and re-connects with a fresh token before import.
  Don't remove those blocks (see the comments near the `begin{}` block and the import region).
- **Credentials:** `packagefactory-config.json` holds a live Entra client secret. It is gitignored
  and has never been committed — keep it that way. Client-secret values are redacted in the GUI log.
- **Toolkit binaries are not committed** — `*.exe` (and other binaries) are gitignored, so the
  PSADT toolkit under `PSAppDeployToolkit/Toolkit/` is downloaded fresh rather than versioned. After
  a clone, drop a current **PSADT v4** release into `Toolkit/` before building. (A leftover v3-era
  `!…/Deploy-Application.exe` un-ignore rule in `.gitignore` is now moot and can be removed.)
