# Provider configuration
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "location" {
  default = "eastus"
}

variable "pdu" {
  default = "myproject"
}

variable "admin_password" {
  type    = string
  default = "To_be_randomised_later12443!"
}

# Local variables
locals {
  location_prefix = "use"
  cpenvprefix = {
    dev  = ["dev"]
    test = ["test"]
    prod = ["prod1", "prod2"]
  }
  tags = {
    Environment = terraform.workspace
    Project     = var.pdu
  }
}

# Resource Group
resource "azurerm_resource_group" "rg_analytics" {
  name     = "rg-analytics-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  location = var.location
  tags     = merge(var.tags, local.tags)
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
}

# Subnets
resource "azurerm_subnet" "fe02" {
  name                 = "fe02-subnet"
  resource_group_name  = azurerm_resource_group.rg_analytics[0].name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.rg_analytics[0].name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]

  private_endpoint_network_policies_enabled = true
}

# Azure Data Factory
resource "azurerm_data_factory" "adf" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
}

# Self-hosted Integration Runtime
resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count           = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}

# MySQL Linked Service
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count             = length(local.cpenvprefix[terraform.workspace])
  name              = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
}

# Network Interface for SHIR VM
resource "azurerm_network_interface" "shir" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "nic-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  
  ip_configuration {
    name                          = "shir"
    subnet_id                     = azurerm_subnet.fe02.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(var.tags, local.tags)
}

# Windows Virtual Machine for SHIR
resource "azurerm_windows_virtual_machine" "shir_vm" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "vm-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  location            = var.location
  admin_username      = "admin"
  admin_password      = var.admin_password
  size                = "Standard_D2s_v3"
  source_image_id     = "/subscriptions/67e5f2ee-6e0a-49e3-b533-97f0beec351c/resourceGroups/rg-dwp-dev-ss-shared-images/providers/Microsoft.Compute/galleries/GoldImagesDevGallery/images/WIN2019-CIS2/versions/3.051.21819"
  network_interface_ids = [azurerm_network_interface.shir[count.index].id]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

# Azure SQL Server
resource "azurerm_mssql_server" "sqlserver" {
  name                         = "sqlserver-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  resource_group_name          = azurerm_resource_group.rg_analytics[0].name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = var.admin_password

  tags = merge(var.tags, local.tags)
}

# Azure SQL Database
resource "azurerm_mssql_database" "sqldb" {
  name      = "sqldb-curated-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  server_id = azurerm_mssql_server.sqlserver.id
  sku_name  = "S0"

  tags = merge(var.tags, local.tags)
}

# Private Endpoint for Azure SQL
resource "azurerm_private_endpoint" "sqlserver_pe" {
  name                = "pe-sqlserver-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-sqlserver-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
    private_connection_resource_id = azurerm_mssql_server.sqlserver.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  tags = merge(var.tags, local.tags)
}

# Private Endpoint for Azure Data Factory
resource "azurerm_private_endpoint" "adf_pe" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "pe-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
    private_connection_resource_id = azurerm_data_factory.adf[count.index].id
    is_manual_connection           = false
    subresource_names              = ["dataFactory"]
  }

  tags = merge(var.tags, local.tags)
}

# Power BI Gateway installation script
resource "azurerm_virtual_machine_extension" "install_pbi_gateway" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "install-pbi-gateway"
  virtual_machine_id   = azurerm_windows_virtual_machine.shir_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"Invoke-WebRequest -Uri https://download.microsoft.com/download/D/A/1/DA1FDDB8-6DA8-4F50-B4D0-18019591E182/GatewayInstall.exe -OutFile GatewayInstall.exe; ./GatewayInstall.exe -era=1\""
  }
  SETTINGS

  tags = merge(var.tags, local.tags)
}

# Network Security Group for VM
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-vm-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name

  security_rule {
    name                       = "AllowCIAEgress"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = merge(var.tags, local.tags)
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "vm_nsg_association" {
  count                     = length(local.cpenvprefix[terraform.workspace])
  network_interface_id      = azurerm_network_interface.shir[count.index].id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Outputs
output "data_factory_ids" {
  value = azurerm_data_factory.adf[*].id
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sqlserver.fully_qualified_domain_name
}

output "shir_vm_private_ip_addresses" {
  value = azurerm_network_interface.shir[*].private_ip_address
}