## Azure Data factory powerBI integration
resource "azurerm_data_factory" "adf" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
}


# creating self hosted integration runtime for data factory 
 resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}
# Output the Primary Authorization Key
output "primary_authorization_key" {
  value = azurerm_data_factory_integration_runtime_self_hosted.shir[*].primary_authorization_key
  sensitive = true  # This hides the output in the Terraform state files
}

# connecting replica mysql database to data factory for etl to azure sql
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count = length(local.cpenvprefix[terraform.workspace])
  name              = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
} 

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



// setting up a windows vm here for the SHIR to deploy into.
 
resource "azurerm_virtual_machine" "shir_vm" {
  count = length(local.cpenvprefix[terraform.workspace])
  // The prefix "uksucc" is important for internal naming policies
  name                = "uksucc-ukpowerbi"
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  location            = var.location
  
  network_interface_ids = [azurerm_network_interface.shir[0].id,]

  // The size of the VM will probably need to be changed in time
  vm_size               = "Standard_DS1_v2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  // This picks up the image from the GoldImagesDevGallery/GoldImagesGallery depending on the environment
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
    // This should be randomised and stored in kv eventually
    admin_password = "Password1234!"
  }
  os_profile_windows_config {
    provision_vm_agent = true
    enable_automatic_upgrades = true

  }

}
resource "azurerm_virtual_machine_extension" "install_shir" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "install-shir"
  virtual_machine_id   = azurerm_virtual_machine.shir_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # Use the primary authorization key from SHIR resource
  protected_settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"$gatewayKey = '${azurerm_data_factory_integration_runtime_self_hosted.shir[count.index].primary_authorization_key}'; $workingDir = 'C:\\SHIR'; New-Item -ItemType Directory -Force -Path $workingDir; Invoke-WebRequest -Uri https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.20.8260.1.msi -OutFile $workingDir\\IntegrationRuntime.msi; Start-Process msiexec.exe -Wait -ArgumentList '/i $workingDir\\IntegrationRuntime.msi /qn'; Start-Process 'C:\\Program Files\\Microsoft Integration Runtime\\5.0\\Shared\\diahost.exe' -ArgumentList '-k $gatewayKey' -Wait\""
  }
  SETTINGS

  tags = merge(var.tags, local.tags)
}
