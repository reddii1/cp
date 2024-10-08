# PowerShell script to install Self-Hosted Integration Runtime (SHIR)

# Download SHIR
$shirDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=853070"
$shirInstallerPath = "C:\Temp\IntegrationRuntimeSetup.exe"
Invoke-WebRequest -Uri $shirDownloadUrl -OutFile $shirInstallerPath

# Install SHIR silently
Start-Process -FilePath $shirInstallerPath -ArgumentList "/quiet" -Wait

# Additional steps can be added here to register SHIR to Azure Data Factory if required.
