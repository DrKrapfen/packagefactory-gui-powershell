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
    $FORM_HEIGHT = 280
    $CONTROL_WIDTH = 360
    $LABEL_HEIGHT = 20
    $CONTROL_HEIGHT = 20
    $VERTICAL_SPACING = 50
    $MARGIN = 10
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
            [bool]$IsComboBox = $false
        )
        
        # Create label
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point($MARGIN, $Top)
        $label.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, $LABEL_HEIGHT)
        $label.Text = "$LabelText :"
        $Form.Controls.Add($label)
        
        # Create control
        if ($IsComboBox) {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = New-Object System.Drawing.Point($MARGIN, ($Top + $LABEL_HEIGHT))
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
        } else {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Location = New-Object System.Drawing.Point($MARGIN, ($Top + $LABEL_HEIGHT))
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
        $tenantComboBox = New-LabelAndControl -Form $form -LabelText 'Customer' -Items $config.Tenants -Top 20 -IsComboBox $true
        $appComboBox = New-LabelAndControl -Form $form -LabelText 'Application' -Items $applicationList -Top 70 -IsComboBox $true
        
        # Create run button
        $runButton = New-Object System.Windows.Forms.Button
        $runButton.Location = New-Object System.Drawing.Point($MARGIN, ($FORM_HEIGHT - 120))
        $runButton.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, 40)
        $runButton.Text = 'Create Package'
        $runButton.UseVisualStyleBackColor = $true
        
        # Create status label
        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Location = New-Object System.Drawing.Point($MARGIN, ($FORM_HEIGHT - 75))
        $statusLabel.Size = New-Object System.Drawing.Size($CONTROL_WIDTH, 20)
        $statusLabel.Text = "Ready"
        $statusLabel.ForeColor = [System.Drawing.Color]::Green
        
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
                
                if (-not $appComboBox.SelectedItem) {
                    throw "Please select an application"
                }
                
                $selectedTenant = $tenantComboBox.SelectedItem
                $tenantId = $config.Tenants.$selectedTenant
                
                if (-not $tenantId) {
                    throw "Invalid tenant selection"
                }
                
                # Connect to MS Intune Graph
                Connect-ToMSIntuneGraph -TenantId $tenantId -ClientId $config.EntraApp.ClientId -ClientSecret $config.EntraApp.ClientSecret
                
                # Create package
                Invoke-PackageCreation -PackageFactoryRoot $config.Paths.PackageFactoryRoot -PackagesPath $config.Paths.PackagesPath -Application $appComboBox.SelectedItem -Type $config.DefaultType -WorkingPath $config.Paths.OutputPath -Import $config.DefaultImport
                
                $statusLabel.Text = "Package created successfully"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
                
                [System.Windows.Forms.MessageBox]::Show("Package created successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error "Operation failed: $errorMessage"
                $statusLabel.Text = "Error: $errorMessage"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
                
                [System.Windows.Forms.MessageBox]::Show("Operation failed: $errorMessage", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })
        
        # Add controls to form
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