# Download Self-Hosted Integration Runtime installer
$installerUrl = "https://go.microsoft.com/fwlink/?linkid=854598"
$installerPath = "C:\SHIRInstaller.exe"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

# Install SHIR silently
$installArgs = "/quiet AcceptEula=1"
Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait

# Configure SHIR (Replace with your Data Factory details)
$authKey = "YOUR_AUTH_KEY"  # You can generate this in Azure Data Factory
$shirName = "YourSHIRName"
$shirConfigCmd = "C:\Program Files\Microsoft Integration Runtime\4.0\Shared\PowerShell\Microsoft.DataTransfer.Gateway.EncryptionTool.exe" `
                 -Key "$authKey" -RegisterKey
Invoke-Expression $shirConfigCmd
