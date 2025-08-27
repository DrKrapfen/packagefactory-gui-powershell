<#
.SYNOPSIS
    Package Factory GUI Application
.DESCRIPTION
    Windows Forms GUI for Aaron Parker's PackageFactory tool with external configuration support
.NOTES
    Requires configuration file: packagefactory-config.json
#>

param(
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "packagefactory-config.json")
)

#Requires -Version 5.1

begin {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Set-ExecutionPolicy Bypass -Scope Process -Force
    
    # Set preferences
    $ProgressPreference = "SilentlyContinue"
    $InformationPreference = "Continue"
    $VerbosePreference = "Continue"
    
    # Constants
    $FORM_WIDTH = 420
    $FORM_HEIGHT = 480
    $CONTROL_WIDTH = 360
    $LABEL_HEIGHT = 20
    $CONTROL_HEIGHT = 20
    $VERTICAL_SPACING = 60
    $LEFT_MARGIN = ($FORM_WIDTH - $CONTROL_WIDTH) / 2
}

process {
    # Helper Functions
    function Write-Msg {
        param([string]$Msg)
        Write-Information -MessageData $Msg -InformationAction Continue
    }
    
    function Get-Configuration {
        param([string]$ConfigPath)
        
        if (-not (Test-Path -Path $ConfigPath)) {
            Write-Msg -Msg "Creating default configuration file: $ConfigPath"
            $defaultConfig = @{
                EntraApp = @{
                    ClientId = ""
                    ClientSecret = ""
                }
                Tenants = @{
                    "Sample Tenant" = "00000000-0000-0000-0000-000000000000"
                }
                Paths = @{
                    PackageFactoryRoot = "..\packagefactory"
                    OutputPath = ""
                    PackagesPath = ""
                }
                DefaultType = "App"
                DefaultImport = $true
            }
            
            $defaultConfig | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8
            Write-Warning "Please edit the configuration file and add your EntraID application details and tenant information."
            return $null
        }
        
        try {
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            
            # Validate required fields
            if (-not $config.EntraApp.ClientId -or -not $config.EntraApp.ClientSecret) {
                Write-Error "EntraID application ClientId and ClientSecret must be configured in $ConfigPath"
                return $null
            }
            
            # Validate required paths
            # Convert relative path to absolute path
            if ($config.Paths.PackageFactoryRoot.StartsWith("..") -or $config.Paths.PackageFactoryRoot.StartsWith(".")) {
                $config.Paths.PackageFactoryRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath $config.Paths.PackageFactoryRoot) -ErrorAction SilentlyContinue
            }
            
            if (-not $config.Paths.PackageFactoryRoot) {
                Write-Error "Unable to resolve PackageFactoryRoot path. Please ensure the packagefactory folder exists in the parent directory."
                return $null
            }
            
            # Validate PackageFactoryRoot exists
            if (-not (Test-Path -Path $config.Paths.PackageFactoryRoot -PathType Container)) {
                Write-Error "PackageFactoryRoot path does not exist: $($config.Paths.PackageFactoryRoot)"
                Write-Information "Expected path: $(Join-Path -Path $(Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'packagefactory')"
                Write-Information "Please ensure the packagefactory folder exists in the parent directory"
                return $null
            }
            
            # Set default paths if not configured
            if (-not $config.Paths.OutputPath) {
                $config.Paths.OutputPath = Join-Path -Path $config.Paths.PackageFactoryRoot -ChildPath "output"
            }
            if (-not $config.Paths.PackagesPath) {
                $config.Paths.PackagesPath = Join-Path -Path $config.Paths.PackageFactoryRoot -ChildPath "packages"
            }
            
            return $config
        }
        catch {
            Write-Error "Failed to load configuration: $_"
            return $null
        }
    }
    
    function Import-PackageFactoryModule {
        param([string]$PackageFactoryRoot)
        
        $moduleFile = Join-Path -Path $PackageFactoryRoot -ChildPath "New-Win32Package.psm1"
        
        if (-not (Test-Path -Path $moduleFile -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::New("Module file not found: '$moduleFile'")
        }
        
        Import-Module -Name $moduleFile -Force -ErrorAction Stop
        Write-Msg -Msg "Successfully imported module: '$moduleFile'"
    }
    
    function Get-ApplicationList {
        param([string]$PackagesPath, [string]$Type)
        
        try {
            $appPath = Join-Path -Path $PackagesPath -ChildPath $Type
            if (-not (Test-Path -Path $appPath)) {
                Write-Warning "Application path does not exist: $appPath"
                return @("No Applications Found")
            }
            
            $applications = Get-ChildItem -Path $appPath -Directory | Select-Object -ExpandProperty Name
            if (-not $applications) {
                Write-Warning "No applications found in: $appPath"
                return @("No Applications Found")
            }
            
            Write-Msg -Msg "Found $($applications.Count) applications in $appPath"
            return $applications
        }
        catch {
            Write-Error "Error fetching application list: $_"
            return @("Error Fetching Applications")
        }
    }
    
    function New-LabelAndControl {
        param(
            [System.Windows.Forms.Form]$Form,
            [string]$LabelText,
            [object]$Items,
            [int]$Top,
            [bool]$IsComboBox = $false,
            [bool]$IsListBox = $false
        )
        
        # Create label
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point($LEFT_MARGIN, $Top)
        $label.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, $LABEL_HEIGHT)
        $label.Text = "$LabelText :"
        $Form.Controls.Add($label)
        
        # Create control
        if ($IsComboBox) {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = New-Object System.Drawing.Point($LEFT_MARGIN, ($Top + $LABEL_HEIGHT))
            $control.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, $CONTROL_HEIGHT)
            $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $control.DropDownHeight = 100
            
            if ($Items -is [hashtable]) {
                $control.Items.AddRange($Items.Keys)
            } elseif ($Items -is [array]) {
                $control.Items.AddRange($Items)
            } elseif ($Items -is [PSCustomObject]) {
                # Handle PSCustomObject from JSON conversion
                $control.Items.AddRange($Items.PSObject.Properties.Name)
            } else {
                # Fallback for other object types
                $control.Items.AddRange(($Items | Get-Member -MemberType NoteProperty).Name)
            }
        } elseif ($IsListBox) {
            $control = New-Object System.Windows.Forms.ListBox
            $control.Location = New-Object System.Drawing.Point($LEFT_MARGIN, ($Top + $LABEL_HEIGHT))
            $control.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, 120)
            $control.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
            $control.ScrollAlwaysVisible = $true
            
            if ($Items -is [array]) {
                $control.Items.AddRange($Items)
            } elseif ($Items -is [hashtable]) {
                $control.Items.AddRange($Items.Keys)
            } elseif ($Items -is [PSCustomObject]) {
                # Handle PSCustomObject from JSON conversion
                $control.Items.AddRange($Items.PSObject.Properties.Name)
            } else {
                # Fallback for other object types
                $control.Items.AddRange(($Items | Get-Member -MemberType NoteProperty).Name)
            }
        } else {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Location = New-Object System.Drawing.Point($LEFT_MARGIN, ($Top + $LABEL_HEIGHT))
            $control.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, $CONTROL_HEIGHT)
            $control.Text = $Items
        }
        
        $Form.Controls.Add($control)
        return $control
    }
    
    function Connect-ToMSIntuneGraph {
        param(
            [string]$TenantId,
            [string]$ClientId,
            [string]$ClientSecret
        )
        
        try {
            $params = @{
                TenantId = $TenantId
                ClientID = $ClientId
                ClientSecret = $ClientSecret
            }
            
            Write-Msg -Msg "Connecting to MS Intune Graph for tenant: $TenantId"
            Connect-MSIntuneGraph @params
            Write-Msg -Msg "Successfully connected to MS Intune Graph"
        }
        catch {
            Write-Error "Failed to connect to MS Intune Graph: $_"
            throw
        }
    }
    
    function Invoke-PackageCreation {
        param(
            [string]$PackageFactoryRoot,
            [string]$PackagesPath,
            [string]$Application,
            [string]$Type,
            [string]$WorkingPath,
            [bool]$Import
        )
        
        try {
            Set-Location -Path $PackageFactoryRoot
            
            $params = @{
                Path        = $PackagesPath
                Application = $Application
                Type        = $Type
                WorkingPath = $WorkingPath
                Import      = $Import
            }
            
            Write-Msg -Msg "Creating package with parameters: $($params | ConvertTo-Json -Compress)"
            & ".\New-Win32Package.ps1" @params
            Write-Msg -Msg "Package creation completed successfully"
        }
        catch {
            Write-Error "Package creation failed: $_"
            throw
        }
    }
    
    function Invoke-GitPull {
        param([string]$PackageFactoryRoot)
        
        try {
            $currentLocation = $(Join-Path -Path $(Get-Location) -ChildPath "packagefactory")
            Write-Msg -Msg $currentLocation
            Set-Location -Path $PackageFactoryRoot
            
            # Check if git is available
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                throw "Git is not installed or not in PATH"
            }
            
            # Check if directory is a git repository
            if (-not (Test-Path -Path ".github" -PathType Container)) {
                throw "Directory is not a git repository"
            }
            
            Write-Msg -Msg "Updating applications via git pull..."
            $result = & git pull origin main 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Git pull failed: $result"
            }
            
            Write-Msg -Msg "Git pull completed successfully: $result"
        }
        catch {
            Write-Error "Git pull failed: $_"
            throw
        }
        finally {
            Set-Location -Path $currentLocation
        }
    }
    
    function Install-Dependencies {
        param([string]$PackageFactoryRoot)
        
        try {
            Write-Msg -Msg "Installing PowerShell dependencies..."
            
            # Required modules for PackageFactory
            $requiredModules = @(
                "Microsoft.Graph.Authentication",
                "Microsoft.Graph.Intune",
                "IntuneWin32App",
                "Evergreen",
                "VcRedist",
                "MSAL.PS"
            )
            
            foreach ($module in $requiredModules) {
                Write-Msg -Msg "Checking module: $module"
                
                $installedModule = Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue
                if (-not $installedModule) {
                    Write-Msg -Msg "Installing module: $module"
                    Install-Module -Name $module -Force -Scope CurrentUser -ErrorAction Stop
                } else {
                    Write-Msg -Msg "Module $module is already installed"
                }
            }
            
            Write-Msg -Msg "All dependencies installed successfully"
        }
        catch {
            Write-Error "Dependency installation failed: $_"
            throw
        }
    }
    
    # Main execution
    try {
        # Load configuration
        $config = Get-Configuration -ConfigPath $ConfigPath
        if (-not $config) {
            return
        }
        
        # Import required module
        Import-PackageFactoryModule -PackageFactoryRoot $config.Paths.PackageFactoryRoot
        
        # Get application list
        $applicationList = Get-ApplicationList -PackagesPath $config.Paths.PackagesPath -Type $config.DefaultType
        
        # Create main form
        Write-Msg -Msg "Creating Package Factory GUI"
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Package Factory - Script Executor'
        $form.Size = New-Object System.Drawing.Size($FORM_WIDTH, $FORM_HEIGHT)
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        
        # Create controls
        # Create navbar with utility buttons
        $buttonWidth = ($CONTROL_WIDTH - 10) / 2
        
        $gitPullButton = New-Object System.Windows.Forms.Button
        $gitPullButton.Location = New-Object System.Drawing.Point($LEFT_MARGIN, 10)
        $gitPullButton.Size = New-Object System.Drawing.Size($buttonWidth, 30)
        $gitPullButton.Text = 'Update Apps (Git Pull)'
        $gitPullButton.UseVisualStyleBackColor = $true
        
        $installDepsButton = New-Object System.Windows.Forms.Button
        $installDepsButton.Location = New-Object System.Drawing.Point(($LEFT_MARGIN + $buttonWidth + 10), 10)
        $installDepsButton.Size = New-Object System.Drawing.Size($buttonWidth, 30)
        $installDepsButton.Text = 'Install Dependencies'
        $installDepsButton.UseVisualStyleBackColor = $true
        
        # Add separator line
        $separator = New-Object System.Windows.Forms.Label
        $separator.Location = New-Object System.Drawing.Point($LEFT_MARGIN, 50)
        $separator.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, 2)
        $separator.BackColor = [System.Drawing.Color]::LightGray
        
        # Main workflow controls
        $tenantComboBox = New-LabelAndControl -Form $form -LabelText 'Customer' -Items $config.Tenants -Top 70 -IsComboBox $true
        $appListBox = New-LabelAndControl -Form $form -LabelText 'Applications (Multi-Select: Ctrl+Click, Shift+Click)' -Items $applicationList -Top 140 -IsListBox $true
        
        # Create Clear All button for applications
        $clearAllButton = New-Object System.Windows.Forms.Button
        $clearAllButton.Location = New-Object System.Drawing.Point($LEFT_MARGIN, 285)
        $clearAllButton.Size = New-Object System.Drawing.Size(100, 25)
        $clearAllButton.Text = 'Clear All'
        $clearAllButton.UseVisualStyleBackColor = $true
        
        # Create main run button
        $runButton = New-Object System.Windows.Forms.Button
        $runButton.Location = New-Object System.Drawing.Point($LEFT_MARGIN, 320)
        $runButton.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, 40)
        $runButton.Text = 'Create Package(s)'
        $runButton.UseVisualStyleBackColor = $true
        
        # Create status label
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Location = New-Object System.Drawing.Point($LEFT_MARGIN, 370)
        $statusLabel.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, 30)
        $statusLabel.Text = "Ready"
        $statusLabel.ForeColor = [System.Drawing.Color]::Green
        $statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $statusLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10, [System.Drawing.FontStyle]::Bold)
        
        # Add Clear All button click handler
        $clearAllButton.Add_Click({
            $appListBox.ClearSelected()
            $statusLabel.Text = "Selection cleared"
            $statusLabel.ForeColor = [System.Drawing.Color]::Blue
        })
        
        # Add button click handler
        $runButton.Add_Click({
            try {
                $statusLabel.Text = "Processing..."
                $statusLabel.ForeColor = [System.Drawing.Color]::Blue
                $form.Refresh()
                
                # Validate selections
                if (-not $tenantComboBox.SelectedItem) {
                    throw "Please select a customer"
                }
                
                if ($appListBox.SelectedItems.Count -eq 0) {
                    throw "Please select at least one application"
                }
                
                $selectedTenant = $tenantComboBox.SelectedItem
                $tenantId = $config.Tenants.$selectedTenant
                
                if (-not $tenantId) {
                    throw "Invalid tenant selection"
                }
                
                # Connect to MS Intune Graph
                Connect-ToMSIntuneGraph -TenantId $tenantId -ClientId $config.EntraApp.ClientId -ClientSecret $config.EntraApp.ClientSecret
                
                # Create packages for each selected application
                $selectedApps = @($appListBox.SelectedItems)
                $totalApps = $selectedApps.Count
                $currentApp = 0
                
                foreach ($selectedApp in $selectedApps) {
                    $currentApp++
                    $statusLabel.Text = "Processing $currentApp of $totalApps`: $selectedApp"
                    $statusLabel.ForeColor = [System.Drawing.Color]::Blue
                    $form.Refresh()
                    
                    try {
                        Invoke-PackageCreation -PackageFactoryRoot $config.Paths.PackageFactoryRoot -PackagesPath $config.Paths.PackagesPath -Application $selectedApp -Type $config.DefaultType -WorkingPath $config.Paths.OutputPath -Import $config.DefaultImport
                        Write-Msg -Msg "Successfully created package for: $selectedApp"
                    }
                    catch {
                        Write-Error "Failed to create package for $selectedApp`: $_"
                        # Continue with next application instead of stopping
                    }
                }
                
                $statusLabel.Text = "All packages processed successfully"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
                
                [System.Windows.Forms.MessageBox]::Show("All $totalApps package(s) processed successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error "Operation failed: $errorMessage"
                $statusLabel.Text = "Error: $errorMessage"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
                
                [System.Windows.Forms.MessageBox]::Show("Operation failed: $errorMessage", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        
        # Add git pull button handler
        $gitPullButton.Add_Click({
            try {
                $statusLabel.Text = "Updating applications..."
                $statusLabel.ForeColor = [System.Drawing.Color]::Blue
                $form.Refresh()
                
                Invoke-GitPull -PackageFactoryRoot $config.Paths.PackageFactoryRoot
                
                # Refresh application list after update
                $applicationList = Get-ApplicationList -PackagesPath $config.Paths.PackagesPath -Type $config.DefaultType
                $appListBox.Items.Clear()
                $appListBox.Items.AddRange($applicationList)
                
                $statusLabel.Text = "Applications updated successfully"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
                
                [System.Windows.Forms.MessageBox]::Show("Applications updated successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error "Git pull failed: $errorMessage"
                $statusLabel.Text = "Error: $errorMessage"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
                
                [System.Windows.Forms.MessageBox]::Show("Git pull failed: $errorMessage", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        
        # Add install dependencies button handler
        $installDepsButton.Add_Click({
            try {
                $statusLabel.Text = "Installing dependencies..."
                $statusLabel.ForeColor = [System.Drawing.Color]::Blue
                $form.Refresh()
                
                Install-Dependencies -PackageFactoryRoot $config.Paths.PackageFactoryRoot
                
                $statusLabel.Text = "Dependencies installed successfully"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
                
                [System.Windows.Forms.MessageBox]::Show("Dependencies installed successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error "Dependency installation failed: $errorMessage"
                $statusLabel.Text = "Error: $errorMessage"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
                
                [System.Windows.Forms.MessageBox]::Show("Dependency installation failed: $errorMessage", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        
        # Add controls to form
        $form.Controls.Add($gitPullButton)
        $form.Controls.Add($installDepsButton)
        $form.Controls.Add($separator)
        $form.Controls.Add($clearAllButton)
        $form.Controls.Add($runButton)
        $form.Controls.Add($statusLabel)
        
        # Show form
        Write-Msg -Msg "Displaying Package Factory GUI"
        $form.ShowDialog() | Out-Null
    }
    catch {
        Write-Error "Failed to initialize application: $_"
        [System.Windows.Forms.MessageBox]::Show("Failed to initialize application: $($_.Exception.Message)", "Initialization Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

end {
    Write-Msg -Msg "Package Factory GUI session ended"
}