# Package Factory GUI

A Windows Forms GUI application for Aaron Parker's PackageFactory tool with secure configuration management.

## Features

- Clean, user-friendly Windows Forms interface
- External configuration file for sensitive data
- Robust error handling and validation
- Support for multiple tenants/customers
- Automatic module loading and path management

## Setup

1. **Configuration File**: On first run, the script will create a `packagefactory-config.json` file with default values.

2. **Edit Configuration**: Open the configuration file and update the following:
   - `EntraApp.ClientId`: Your EntraID application Client ID
   - `EntraApp.ClientSecret`: Your EntraID application Client Secret
   - `Paths.PackageFactoryRoot`: Path to PackageFactory (defaults to `..\\packagefactory`)
   - `Tenants`: Add/modify your customer tenant information

3. **Run the Script**: Execute the PowerShell script to launch the GUI

## Configuration File Structure

```json
{
  "EntraApp": {
    "ClientId": "your-client-id-here",
    "ClientSecret": "your-client-secret-here"
  },
  "Tenants": {
    "Customer Name": "tenant-id-guid"
  },
  "Paths": {
    "PackageFactoryRoot": "..\\packagefactory",
    "OutputPath": "optional-custom-output-path",
    "PackagesPath": "optional-custom-packages-path"
  },
  "DefaultType": "App",
  "DefaultImport": true
}
```

## Directory Structure

The script expects the following directory structure:
```
Intune Package Factory/
├── WindowsForms-GUI-powershell/
│   ├── packagefactory.ps1
│   └── packagefactory-config.json
└── packagefactory/
    ├── New-Win32Package.ps1
    ├── New-Win32Package.psm1
    ├── packages/
    └── output/
```

## Security Notes

- Keep the configuration file secure and do not commit it to version control
- The script runs in user context and stores configuration locally
- Secrets are read from the configuration file at runtime, not hardcoded

## Usage

1. Select a customer from the dropdown
2. Select an application from the dropdown
3. Click "Create Package" to execute the packaging process
4. Monitor the status label for progress updates

## Requirements

- PowerShell 5.1 or higher
- Windows Forms support
- Aaron Parker's PackageFactory module
- Valid EntraID application with appropriate permissions