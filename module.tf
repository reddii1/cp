# File structure:
# /
# ├── main.tf
# ├── variables.tf
# ├── outputs.tf
# └── modules/
#     ├── networking/
#     │   ├── main.tf
#     │   ├── variables.tf
#     │   └── outputs.tf
#     ├── data_factory/
#     │   ├── main.tf
#     │   ├── variables.tf
#     │   └── outputs.tf
#     ├── sql_server/
#     │   ├── main.tf
#     │   ├── variables.tf
#     │   └── outputs.tf
#     └── vm/
#         ├── main.tf
#         ├── variables.tf
#         └── outputs.tf

# main.tf

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

resource "azurerm_resource_group" "rg_analytics" {
  name     = "rg-analytics-${local.location_prefix}-${terraform.workspace}-${var.pdu}"
  location = var.location
  tags     = merge(var.tags, local.tags)
}

module "networking" {
  source              = "./modules/networking"
  resource_group_name = azurerm_resource_group.rg_analytics.name
  location            = var.location
  vnet_address_space  = ["10.0.0.0/16"]
  subnet_prefixes     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  subnet_names        = ["default", "fe02", "private-endpoints"]
  tags                = merge(var.tags, local.tags)
}

module "data_factory" {
  source              = "./modules/data_factory"
  count               = length(local.cpenvprefix[terraform.workspace])
  resource_group_name = azurerm_resource_group.rg_analytics.name
  location            = var.location
  name_prefix         = "${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}"
  pdu                 = var.pdu
  subnet_id           = module.networking.subnet_ids["private-endpoints"]
  tags                = merge(var.tags, local.tags)
}

module "sql_server" {
  source              = "./modules/sql_server"
  resource_group_name = azurerm_resource_group.rg_analytics.name
  location            = var.location
  name_prefix         = "${local.location_prefix}-${terraform.workspace}"
  pdu                 = var.pdu
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  subnet_id           = module.networking.subnet_ids["private-endpoints"]
  tags                = merge(var.tags, local.tags)
}

module "vm" {
  source              = "./modules/vm"
  count               = length(local.cpenvprefix[terraform.workspace])
  resource_group_name = azurerm_resource_group.rg_analytics.name
  location            = var.location
  name_prefix         = "${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}"
  pdu                 = var.pdu
  subnet_id           = module.networking.subnet_ids["fe02"]
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = merge(var.tags, local.tags)
}

# variables.tf

variable "location" {
  default = "eastus"
}

variable "pdu" {
  default = "myproject"
}

variable "admin_username" {
  default = "adminuser"
}

variable "admin_password" {
  type = string
}

# outputs.tf

output "data_factory_ids" {
  value = module.data_factory[*].data_factory_id
}

output "sql_server_fqdn" {
  value = module.sql_server.sql_server_fqdn
}

output "vm_private_ip_addresses" {
  value = module.vm[*].private_ip_address
}

# modules/networking/main.tf

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.name_prefix}-${var.pdu}"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "subnet" {
  count                = length(var.subnet_names)
  name                 = var.subnet_names[count.index]
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_prefixes[count.index]]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.name_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name

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

  tags = var.tags
}

# modules/networking/variables.tf

variable "resource_group_name" {}
variable "location" {}
variable "vnet_address_space" {}
variable "subnet_prefixes" {}
variable "subnet_names" {}
variable "name_prefix" {}
variable "pdu" {}
variable "tags" {}

# modules/networking/outputs.tf

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "subnet_ids" {
  value = { for subnet in azurerm_subnet.subnet : subnet.name => subnet.id }
}

output "nsg_id" {
  value = azurerm_network_security_group.nsg.id
}

# modules/data_factory/main.tf

resource "azurerm_data_factory" "adf" {
  name                = "adf-${var.name_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  name            = "shir-adf-${var.name_prefix}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf.id
}

resource "azurerm_private_endpoint" "adf_pe" {
  name                = "pe-adf-${var.name_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-adf-${var.name_prefix}-${var.pdu}"
    private_connection_resource_id = azurerm_data_factory.adf.id
    is_manual_connection           = false
    subresource_names              = ["dataFactory"]
  }

  tags = var.tags
}

# modules/data_factory/variables.tf

variable "resource_group_name" {}
variable "location" {}
variable "name_prefix" {}
variable "pdu" {}
variable "subnet_id" {}
variable "tags" {}

# modules/data_factory/outputs.tf

output "data_factory_id" {
  value = azurerm_data_factory.adf.id
}

# modules/sql_server/main.tf

resource "azurerm_mssql_server" "sqlserver" {
  name                         = "sqlserver-${var.name_prefix}-${var.pdu}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
  tags                         = var.tags
}

resource "azurerm_mssql_database" "sqldb" {
  name      = "sqldb-curated-${var.name_prefix}-${var.pdu}"
  server_id = azurerm_mssql_server.sqlserver.id
  sku_name  = "S0"
  tags      = var.tags
}

resource "azurerm_private_endpoint" "sqlserver_pe" {
  name                = "pe-sqlserver-${var.name_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-sqlserver-${var.name_prefix}-${var.pdu}"
    private_connection_resource_id = azurerm_mssql_server.sqlserver.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  tags = var.tags
}

# modules/sql_server/variables.tf

variable "resource_group_name" {}
variable "location" {}
variable "name_prefix" {}
variable "pdu" {}
variable "admin_username" {}
variable "admin_password" {}
variable "subnet_id" {}
variable "tags" {}

# modules/sql_server/outputs.tf

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sqlserver.fully_qualified_domain_name
}

# modules/vm/main.tf

resource "azurerm_network_interface" "nic" {
  name                = "nic-vm-${var.name_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = "vm-${var.name_prefix}-${var.pdu}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.nic.id,
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

  tags = var.tags
}

resource "azurerm_virtual_machine_extension" "install_pbi_gateway" {
  name                 = "install-pbi-gateway"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"Invoke-WebRequest -Uri https://download.microsoft.com/download/D/A/1/DA1FDDB8-6DA8-4F50-B4D0-18019591E182/GatewayInstall.exe -OutFile GatewayInstall.exe; ./GatewayInstall.exe -era=1\""
  }
  SETTINGS

  tags = var.tags
}

# modules/vm/variables.tf

variable "resource_group_name" {}
variable "location" {}
variable "name_prefix" {}
variable "pdu" {}
variable "subnet_id" {}
variable "admin_username" {}
variable "admin_password" {}
variable "tags" {}

# modules/vm/outputs.tf

output "private_ip_address" {
  value = azurerm_network_interface.nic.private_ip_address
}