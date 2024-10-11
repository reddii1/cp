To integrate the Self-Hosted Integration Runtime (SHIR) installation on the Windows Virtual Machine (VM) and run it using the Custom Script Extension with a PowerShell script, we need to merge the code provided, ensuring that:

	1.	The VM has the required Custom Script Extension to run the PowerShell script for SHIR installation.
	2.	A Storage Account is created for boot diagnostics, which is referenced in the Custom Script Extension.

Below is the merged Terraform code, followed by the PowerShell script to install SHIR on the Windows VM.

Merged Terraform Code

# Data Factory and Self-Hosted Integration Runtime (SHIR)
resource "azurerm_data_factory" "adf" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
}

resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}

# Connecting MySQL database to Data Factory for ETL
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count = length(local.cpenvprefix[terraform.workspace])
  name              = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
}

# Creating network interface for SHIR VM
resource "azurerm_network_interface" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "nic-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  ip_configuration {
    name                          = "shir"
    subnet_id                     = azurerm_subnet.fe02[0].id
    private_ip_address_allocation = "Dynamic"
  }
  tags = merge(var.tags, local.tags)
}

# Setting up Windows VM for SHIR
resource "azurerm_virtual_machine" "shir_vm" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "uksucc-ukpowerbi"
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  location            = var.location
  network_interface_ids = [azurerm_network_interface.shir[0].id]
  vm_size               = "Standard_DS1_v2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    id = data.azurerm_shared_image_version.win2019_latestGoldImage.id
  }

  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"  # Replace with secret from key vault or random value
  }

  os_profile_windows_config {
    provision_vm_agent         = true
    enable_automatic_upgrades  = true
  }
}

# Storage Account for Boot Diagnostics
resource "azurerm_storage_account" "bootdiag" {
  name                     = "bootdiagstorage"
  resource_group_name       = azurerm_resource_group.rg_analytics[0].name
  location                  = azurerm_resource_group.rg_analytics[0].location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_blob_encryption    = true
  enable_https_traffic_only = true
}

# Custom Script Extension to run PowerShell script to install SHIR
resource "azurerm_virtual_machine_extension" "shir_install" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "InstallSHIR"
  virtual_machine_id   = azurerm_virtual_machine.shir_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
  {
    "commandToExecute": "powershell -ExecutionPolicy Unrestricted -File install-shir.ps1"
  }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
  {
    "storageAccountName": "${azurerm_storage_account.bootdiag.name}",
    "storageAccountKey": "${azurerm_storage_account.bootdiag.primary_access_key}"
  }
  PROTECTED_SETTINGS

  tags = merge(var.tags, local.tags)
}

PowerShell Script (install-shir.ps1)

Create the PowerShell script install-shir.ps1, which installs the SHIR on the Windows VM:

# PowerShell script to install Self-hosted Integration Runtime

$gatewayKey = "<SHIR_AUTHORIZATION_KEY>" # Replace this with the SHIR authorization key dynamically if possible
$workingDir = "C:\\SHIR"

# Create working directory
New-Item -ItemType Directory -Force -Path $workingDir

# Download the SHIR installer
Invoke-WebRequest -Uri "https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.20.8260.1.msi" -OutFile "$workingDir\\IntegrationRuntime.msi"

# Install SHIR silently
Start-Process msiexec.exe -Wait -ArgumentList "/i $workingDir\\IntegrationRuntime.msi /qn"

# Register SHIR with the authorization key
$process = Start-Process -FilePath "C:\\Program Files\\Microsoft Integration Runtime\\5.0\\Shared\\diahost.exe" -ArgumentList "-k $gatewayKey" -Wait

Key Changes and Details:

	1.	Boot Diagnostics:
	•	A Storage Account is created to store logs and diagnostics related to the VM boot process. The azurerm_storage_account resource is used, and the necessary properties for secure communication are set (HTTPS only, encryption, etc.).
	2.	Custom Script Extension:
	•	The Custom Script Extension executes the PowerShell script (install-shir.ps1) on the Windows VM to install the Self-Hosted Integration Runtime (SHIR). The script downloads the SHIR installer, runs it, and registers the runtime using the authorization key.
	3.	PowerShell Script:
	•	The PowerShell script first creates a working directory (C:\SHIR) on the VM, downloads the SHIR installer from Microsoft’s servers, and runs it in silent mode. After installation, it registers the SHIR using the provided authorization key.
	•	You will need to replace the <SHIR_AUTHORIZATION_KEY> in the script with the actual key generated by the Data Factory’s Self-Hosted Integration Runtime.

Important Notes:

	•	Dynamic SHIR Authorization Key: You should dynamically inject the primary authorization key for the SHIR into the PowerShell script. One way is to use the key from the azurerm_data_factory_integration_runtime_self_hosted.shir resource in Terraform and pass it to the script.
Example:

commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"$gatewayKey='${azurerm_data_factory_integration_runtime_self_hosted.shir.primary_authorization_key}'; .\\install-shir.ps1\""


	•	Secure Secrets: Store secrets such as the admin password, SHIR authorization key, and storage account key securely using Azure Key Vault or Terraform variables with sensitive = true. Avoid hardcoding secrets in the scripts or configurations.

By integrating the PowerShell script with the Terraform configuration, this setup will successfully install and register the SHIR on the Windows VM in Azure.