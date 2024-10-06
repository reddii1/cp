provider "azurerm" {
  features {}
}

# Define variables
variable "location" {
  description = "The Azure location where resources will be created."
  type        = string
}

variable "cpenvprefix" {
  description = "List of environment prefixes."
  type        = list(string)
}

variable "pdu" {
  description = "Project Deployment Unit."
  type        = string
}

variable "sql_admin_username" {
  description = "SQL Server admin username."
  type        = string
}

variable "sql_admin_password" {
  description = "SQL Server admin password."
  type        = string
}

variable "admin_username" {
  description = "VM admin username."
  type        = string
}

variable "admin_password" {
  description = "VM admin password."
  type        = string
}

variable "tags" {
  description = "Tags for resources."
  type        = map(string)
}

# Define resource group
resource "azurerm_resource_group" "rg_app" {
  name     = "rg-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location = var.location
}

# Define Azure Data Factory
resource "azurerm_data_factory" "adf" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
}

# Self-hosted integration runtime for Data Factory
resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count            = length(local.cpenvprefix[terraform.workspace])
  name             = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id  = azurerm_data_factory.adf[count.index].id
}

# Linked service to MySQL database for ETL
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count              = length(local.cpenvprefix[terraform.workspace])
  name               = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id    = azurerm_data_factory.adf[count.index].id
  connection_string   = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
}

# Network Interface for SHIR VM
resource "azurerm_network_interface" "shir" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "nic-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.rg_app.name

  ip_configuration {
    name                          = "shir"
    subnet_id                     = azurerm_subnet.mysqlfs[count.index].id
    private_ip_address_allocation = "Dynamic"
  }
}

# Random password for SHIR VM
resource "random_password" "vm-shir-adf-pass" {
  count               = length(local.cpenvprefix[terraform.workspace])
  length              = 36
  override_special    = "-"
}

# Windows Virtual Machine for SHIR
resource "azurerm_windows_virtual_machine" "shir_vm" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "vm-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  computer_name        = "vm-shir-adf"
  resource_group_name  = azurerm_resource_group.rg_app.name
  location             = var.location
  admin_username       = var.admin_username
  admin_password       = random_password.vm-shir-adf-pass[count.index].result
  size                 = "Standard_D2as_v4"
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

# Define Azure SQL Server
resource "azurerm_sql_server" "sql_server" {
  name                         = "sql-server-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name          = azurerm_resource_group.rg_app.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
}

# Define Azure SQL Database
resource "azurerm_sql_database" "sql_db" {
  name                = "sql-db-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  server_name         = azurerm_sql_server.sql_server.name
  requested_service_objective_name = "S0"  # Change as needed for performance
}

# Private link for SQL Database
resource "azurerm_private_endpoint" "sql_private_endpoint" {
  name                = "sql-private-endpoint-${local.cpenvprefix[terraform.workspace][count.index]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name

  subnet_id = azurerm_subnet.mysqlfs[count.index].id

  private_service_connection {
    name                           = "sql-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_sql_database.sql_db.id
    subresource_names              = ["sqlServer"]
  }
}

# Network Interface for Power BI Gateway
resource "azurerm_network_interface" "powerbi_nic" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "nic-powerbi-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.rg_app.name

  ip_configuration {
    name                          = "powerbi-config"
    subnet_id                     = azurerm_subnet.mysqlfs[count.index].id
    private_ip_address_allocation = "Dynamic"
  }
}

# Windows Virtual Machine for Power BI Gateway
resource "azurerm_windows_virtual_machine" "powerbi_vm" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "vm-powerbi-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  computer_name        = "vm-powerbi"
  resource_group_name  = azurerm_resource_group.rg_app.name
  location             = var.location
  admin_username       = var.admin_username
  admin_password       = random_password.vm-shir-adf-pass[count.index].result
  size                 = "Standard_D2as_v4"

  network_interface_ids = [
    azurerm_network_interface.powerbi_nic[count.index].id,
  ]

  os_disk {
    name                 = "osd-powerbi"
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

  # Optional: Use provisioners to install Power BI Gateway
  provisioner "remote-exec" {
    inline = [
      "Start-Process msiexec.exe -ArgumentList '/i https://download.microsoft.com/download/3/2/6/326bff87-98a4-4e0b-bdb8-c93b29e93b19/PowerBIGateway.msi /quiet'",
      "Start-Sleep -s 30", # Wait for the installer to finish
    ]

    connection {
      type        = "winrm"
      host        = azurerm_network_interface.powerbi_nic[count.index].private_ip_address
      user        = var.admin_username
      password    = random_password.vm-shir-adf-pass[count.index].result
      https       = true
      insecure    = true
    }
  }
}

# Define a storage container for installation scripts (if needed)
resource "azurerm_storage_container" "dfa-shir" {
  name                  = "shir-install-script"
  storage_account_name  = azurerm_storage_account.omilia.name
  container_access_type = "private"
}

# Local variable to define script name
locals {
  script_name = "install-shir.ps1" # Name of the installation script for SHIR
}

# Upload the installation script to the storage container (if needed)
resource "azurerm_storage_blob" "shir_install_script" {
  name                   = local.script_name
  storage_account_name   = azurerm_storage_account.omilia.name
  storage_container_name = azurerm_storage_container.dfa-shir.name
  type                   = "Block"
  source                 = "path/to/local/install-shir.ps1" # Update with the path to your local script
}