resource "azurerm_windows_virtual_machine" "vm" {
  name                = "powerbi-gateway-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd1234!"  # Secure this with Azure Key Vault in production

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-powerbi-gateway-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}



-----------------

resource "azurerm_virtual_machine_extension" "powerbi_gateway_install" {
  name                 = "install-powerbi-gateway"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -File install-powerbi-gateway.ps1"
  }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
  {
    "fileUris": ["https://your-storage-account.blob.core.windows.net/scripts/install-powerbi-gateway.ps1"]
  }
  PROTECTED_SETTINGS
}



---------------------

install-powerbi-gateway.ps1



# PowerShell script to install Power BI Gateway on Windows VM

# Define variables
$gatewayInstallerUrl = "https://go.microsoft.com/fwlink/?linkid=820925"  # Power BI Gateway download URL
$installerPath = "C:\temp\PowerBIGatewayInstaller.exe"
$gatewayName = "PowerBIGatewayVM"
$recoveryKey = "<your-recovery-key>"  # Replace this with your actual recovery key if needed
$adminEmail = "<your-admin-email>"    # Replace with your admin email for registering the gateway
$password = "<your-admin-password>"   # Replace with the admin password (use secure storage in production)

# Create temp folder if it doesn't exist
if (!(Test-Path -Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp"
}

# Download Power BI Gateway installer
Invoke-WebRequest -Uri $gatewayInstallerUrl -OutFile $installerPath

# Install the gateway in silent mode
Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait

# Register the gateway using the provided admin credentials
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($adminEmail, $securePassword)

# Register Power BI Gateway
& "C:\Program Files\On-premises data gateway\GatewayConfigurator.exe" -Register -RecoveryKey $recoveryKey -GatewayName $gatewayName -Credential $credential

