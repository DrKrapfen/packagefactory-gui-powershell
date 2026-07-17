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
| `packagefactory/PSAppDeployToolkit/Toolkit/` | **PSADT v3** toolkit injected into PSADT packages (ships `Deploy-Application.exe` + `AppDeployToolkit\`). |
| `packagefactory/output/` | Working directory: `output/<Name>/Source` (staging) and `output/<Name>/Output` (the `.intunewin`). |
| `packagefactory-gui-powershell/packagefactory.ps1` | The WinForms GUI. Lets you pick apps + tenant and runs `New-Win32Package.ps1`. |
| `packagefactory-gui-powershell/packagefactory-config.json` | Entra app (ClientId/ClientSecret) + tenant IDs + paths. **Gitignored — never commit.** |

## ⚠️ #1 gotcha: this repo uses PSAppDeployToolkit **v3**, not v4

Every PSADT package here is **v3** — the deploy script is `Source/Deploy-Application.ps1`
and the manifest declares `"SetupFile": "Deploy-Application.exe"`. The bundled
`PSAppDeployToolkit/Toolkit/` folder is also a v3 layout. There are **no v4
(`Invoke-AppDeployToolkit.ps1`) packages** in the catalog.

Upstream PSPackageFactory migrated to **PSADT v4**, so its `New-Win32Package.ps1`
detects PSADT by looking only for `Invoke-AppDeployToolkit.ps1`. On this repo that
detection **silently misses every package**, the toolkit (incl. `Deploy-Application.exe`)
never gets copied, and packaging fails with:

```
WARNUNG: Unable to detect specified setup file 'Deploy-Application.exe' in source folder ...
Invoke-PackageCreation : Package creation failed: Intunewin package file not found
```

(The tell-tale earlier line is `Install.json does not exist or PSAppDeployToolkit not used` —
that means detection fell through to the `else` branch.)

**The fix (already applied):** `New-Win32Package.ps1` now also detects v3. Three spots
handle both `Invoke-AppDeployToolkit.ps1` (v4) **and** `Deploy-Application.ps1` (v3):

1. A v3 `elseif` branch that copies `Toolkit\*` (excluding `Deploy-Application.ps1`),
   copies the package's `Deploy-Application.ps1` to the Source root, creates
   `Files`/`SupportFiles` (`-Force`, since the v3 Toolkit already ships them), and
   redirects `$SourcePath` to `...\Source\Files`.
2. The package-`Source\*` copy excludes **both** entry-script names.
3. The setup-file/source-path revert block triggers for v3 or v4: reverts `$SourcePath`
   to the Source root and forces `$IntuneWinSetupFile = "Deploy-Application.exe"`.

> **If you ever `git pull` / sync upstream, re-check these three spots** — an upstream
> update will re-break v3 by reverting to v4-only detection. Either keep the v3 branch or
> convert all packages + the Toolkit folder to v4 (don't half-migrate).

## Package types (how the engine decides what to do)

Detection is by files present in the package's `Source/` (checked in this order):

1. **PSADT v4** — `Source/Invoke-AppDeployToolkit.ps1` exists → inject v4 toolkit. *(none today)*
2. **PSADT v3** — `Source/Deploy-Application.ps1` exists → inject v3 toolkit; `SetupFile` forced to `Deploy-Application.exe`. **(~33 packages)**
3. **Install.json** — `Source/Install.json` exists → copy the template `Install.ps1`. **(~60 packages)**
4. **Raw** — none of the above → package the downloaded/static installer directly (MSI/EXE/PS).

Note: a v3 package may still set `SetupFile` in `App.json` to a *downloaded* installer
(e.g. `AdobeAcrobatReaderDC`), but if `Source/Deploy-Application.ps1` is present it **is**
a PSADT package and the real install command runs `Deploy-Application.exe`. The engine
correctly forces `SetupFile = Deploy-Application.exe` for these.

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
- **`.gitignore` keeps `PSAppDeployToolkit/Toolkit/Deploy-Application.exe`** via an explicit `!`
  exception (all other `*.exe` are ignored). The v3 fix depends on that file being present, so
  don't remove the exception.
