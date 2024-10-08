resource "azurerm_data_factory" "adf" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
}

# Creating Self-hosted Integration Runtime for Data Factory 
resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count           = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}

# Connecting Replica MySQL Database to Data Factory for ETL to Azure SQL
resource "azurerm_data_factory_linked_service_mysql" "mysql_adf_link" {
  count            = length(local.cpenvprefix[terraform.workspace])
  name             = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id  = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].fqdn};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
}

# Network Interface for Self-hosted IR VM
resource "azurerm_network_interface" "shir" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "nic-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  ip_configuration {
    name                          = "shir"
    subnet_id                     = azurerm_subnet.mysqlfs[count.index].id
    private_ip_address_allocation  = "Dynamic"
  }
  tags = merge(var.tags, local.tags)
}

# Generating a Random Password for Self-hosted IR VM
resource "random_password" "vm_shir_adf_pass" {
  count             = length(local.cpenvprefix[terraform.workspace])
  length            = 36
  override_special  = "-"
}

# Windows Virtual Machine for Self-hosted IR
resource "azurerm_windows_virtual_machine" "shir_vm" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "vm-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  computer_name       = "vm-shir-adf"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  admin_username      = "admin"
  admin_password      = random_password.vm_shir_adf_pass[count.index].result
  size                = "Standard_D2as_v4"
  patch_assessment_mode = "AutomaticByPlatform"
  network_interface_ids = [
    azurerm_network_interface.shir[count.index].id,
  ]
  os_disk {
    name                 = "osd-shir-adf"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  identity {
    type = "SystemAssigned"
  }
}

# Storage Container for SHIR Installation Script
resource "azurerm_storage_container" "dfa_shir" {
  name                  = "shir-install-script"
  storage_account_name  = azurerm_storage_account.omilia.name
  container_access_type = "private"
}

locals {
  script_name = "install-shir.ps1"
}