

begin {
    Add-Type -AssemblyName System.Windows.Forms
    Set-ExecutionPolicy Bypass -Scope Process -Force
    #region Call functions
    $packageFactoryRoot = $(Join-Path -Path $(Split-Path -Path $PSScriptRoot -Parent) -ChildPath "packagefactory")
    $ModuleFile = $(Join-Path -Path $packageFactoryRoot -ChildPath "New-Win32Package.psm1") #".\packagefactory\New-Win32Package.psm1"

    if (Test-Path -Path $ModuleFile -PathType "Leaf" -ErrorAction "Stop") {
        Import-Module -Name $ModuleFile -Force -ErrorAction "Stop"
        Write-Msg -Msg "Importing module: '$ModuleFile'"
    }
    else {
        throw [System.IO.FileNotFoundException]::New("Module file not found: '$ModuleFile'")
    }
    #endregion

    # Set information output
    $ProgressPreference = "SilentlyContinue"
    $InformationPreference = "Continue"
    $VerbosePreference = "Continue"
}

process {
    # Create the main form
    Write-Msg -Msg "Creating new Form"
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Package Script Executor'
    $form.Size = New-Object System.Drawing.Size(400,210)
    $form.StartPosition = 'CenterScreen'

    # Combined function for Label and ComboBox/TextBox creation
    function Add-LabelAndControl ($form, $name, $itemsOrText, $top, $isComboBox) {
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point(10, $top)
        $label.Size = New-Object System.Drawing.Size(280, 20)
        $label.Text = "$name :"
        $form.Controls.Add($label)

        if ($isComboBox) {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.Location = New-Object System.Drawing.Point(10, ($top + 20))
            $control.Size = New-Object System.Drawing.Size(360, 20)
            if ($itemsOrText -is [hashtable]) {
                $control.Items.AddRange($itemsOrText.Keys)
            } else {
                $control.Items.AddRange($itemsOrText)
            }
            $control.DropDownHeight = 100
        } else {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Location = New-Object System.Drawing.Point(10, ($top + 20))
            $control.Size = New-Object System.Drawing.Size(360, 20)
            $control.Text = $itemsOrText
        }

        $form.Controls.Add($control)
        return $control
    }

    $typeTextBox = 'App' #-top 200
    $workingPathTextBox = $(Join-Path -Path $packageFactoryRoot -ChildPath "output") #'C:\projects\packagefactory\output' #-top 260
    $importTextBox = 'True' #-top 320
    $pathTextBox = $(Join-Path -Path $packageFactoryRoot -ChildPath "packages") #'C:\projects\packagefactory\packages'

    # Fetch application list
    try {
        Write-Msg -Msg "Getting all Applications in Directory"
        $itemList = Get-ChildItem -Path "$([System.IO.Path]::Combine($pathTextBox, $typeTextBox))" -Directory | Select-Object -ExpandProperty Name
        if (-not $itemList) {
            Write-Msg -Msg Write-Output "Warning: Application list is empty."
            $itemList = @("No Applications Found")
        }
    } catch {
        Write-Msg -Msg "Error fetching application list: $_"
        $itemList = @("Error Fetching Applications")
    }

    # Define tenant list (name as key, TenantID as value)
    $tenantList = @{
        "EXIT-sozial" = "24017b87-316c-4fe5-ba09-2b0b6ff9deb0"
        "Ventopay" = "16d37b7c-d7f7-47b3-bd16-26886b928d16"
        "TSA" = "635a2f1c-8b0f-48df-a179-ec37f6d35d7e"
        "IT-Pro" = "1f51376a-216b-4208-911d-556a140c2151"
        "Geofelt" = "5cb0be83-e322-4fb2-b37a-f758fa476502"
        "Hammerschmid" = "4930d1b1-f5b3-4f58-94cf-14131dc156eb"
        "Runpotec" = "6c9fb4ea-78a0-4e5f-be7a-c74b489f281c"
        "Saatbau" = "2466c859-ef93-4e40-ae5a-5f608b5f5c6b"
    }
    if (-not $tenantList.Keys) {
        Write-Msg -Msg "Warning: Tenant list is empty."
        $tenantList = @{ "No Tenants Available" = "" }
    }
    else {
        Write-Msg -Msg "Tenant List: '$tenantList'"
    }

    # Add dropdown for tenant selection
    $tenantIdComboBox = Add-LabelAndControl -form $form -name 'Kunde' -itemsOrText $tenantList -top 20 -isComboBox $true
    $appTextBox = Add-LabelAndControl -form $form -name 'Application' -itemsOrText $itemList -top 70 -isComboBox $true

    # Add a button for script execution
    $button = New-Object System.Windows.Forms.Button
    $button.Location = New-Object System.Drawing.Point(10,($form.Size.Height-10-80))
    $button.Size = New-Object System.Drawing.Size(360,40)
    $button.Text = 'Run Script'
    $button.Add_Click({
        $selectedTenant = $tenantIdComboBox.SelectedItem
        if (-not $selectedTenant) {
            Write-Msg -Msg "No Tenant Selected"
            return
        }

        $tenantId = $tenantList[$selectedTenant]

        $params = @{
            TenantId = $tenantId
            ClientID = "33ba7c53-5cfb-4255-859e-e36565fc5a4b"
            ClientSecret = "ymL8Q~~uqHqrprN14WTX0GonF6BAGSacpyHnZaXO" #old: "T4B8Q~JmuEL6UBPQofiPt~S32TfA_HZk3ukOib98"
        }

        try {
            Write-Msg -Msg "Connecting to MSIntuneGraph"
            Connect-MSIntuneGraph @params
        } catch {
            Write-Msg -Msg "Failed to connect to MS Intune Graph."
            return
        }

        Set-Location -Path $packageFactoryRoot
        $params = @{
            Path        = $pathTextBox
            Application = $appTextBox.SelectedItem
            Type        = $typeTextBox
            WorkingPath = $workingPathTextBox
            Import      = [System.Convert]::ToBoolean($importTextBox)
        }

        .\New-Win32Package.ps1 @params
        Write-Msg -Msg "Finished Creating Package"
    })
    $form.Controls.Add($button)

    # Show the form
    $form.ShowDialog()
}
end {
}
