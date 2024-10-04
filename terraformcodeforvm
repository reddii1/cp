provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "cp-resource-group"
  location = "East US"
}

# Virtual Network for the VM
resource "azurerm_virtual_network" "vnet" {
  name                = "shir-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

# Subnet for VM
resource "azurerm_subnet" "subnet" {
  name                 = "shir-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "shir-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Public IP for VM
resource "azurerm_public_ip" "pip" {
  name                = "shir-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Virtual Machine for SHIR
resource "azurerm_virtual_machine" "vm" {
  name                  = "shir-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_DS2_v2"

  storage_os_disk {
    name              = "vm-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  os_profile {
    computer_name  = "shir-vm"
    admin_username = "adminuser"
    admin_password = "Password1234!"
  }

  os_profile_windows_config {
    enable_automatic_upgrades = true
  }

  boot_diagnostics {
    enabled = true
    storage_account_uri = azurerm_storage_account.sa.primary_blob_endpoint
  }
}

# Storage Account for boot diagnostics
resource "azurerm_storage_account" "sa" {
  name                     = "shirstorageacct"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


# Azure SQL Server
resource "azurerm_sql_server" "sql_server" {
  name                         = "cp-sql-server"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "SqlPassword1234!"
}

# Azure SQL Database for Curated Data
resource "azurerm_sql_database" "sql_database" {
  name                = "curated-data-db"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  server_name         = azurerm_sql_server.sql_server.name
  sku_name            = "S1"
}

# Azure SQL Firewall Rule for allowing the VM to access SQL
resource "azurerm_sql_firewall_rule" "fw_rule" {
  name                = "allow-vm"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.sql_server.name
  start_ip_address    = "10.0.1.0"
  end_ip_address      = "10.0.1.255"
}

# Data Factory Instance
resource "azurerm_data_factory" "adf" {
  name                = "cp-data-factory"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Private Link Service for SQL
resource "azurerm_private_link_service" "pls_sql" {
  name                = "pls-sql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  visibility {
    subscriptions = [azurerm_data_factory.adf.id]
  }

  nat_ip_configuration {
    name      = "default"
    subnet_id = azurerm_subnet.subnet.id
  }

  backend_ip_configuration {
    name                          = "backend"
    private_ip_address_allocation = "Dynamic"
  }
}

# Private Endpoint for ADF to access SQL securely
resource "azurerm_private_endpoint" "pe_adf_sql" {
  name                = "pe-adf-sql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "adf-to-sql"
    private_connection_resource_id = azurerm_sql_server.sql_server.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }
}

# Private DNS Zone for Azure SQL
resource "azurerm_private_dns_zone" "sql_zone" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

# Link the Private DNS Zone to the Virtual Network
resource "azurerm_private_dns_zone_virtual_network_link" "sql_vnet_link" {
  name                  = "sql-vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.sql_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}




# Output for the ADF URL
output "adf_url" {
  value = azurerm_data_factory.adf.id
}

# Output for SQL connection info
output "sql_server_name" {
  value = azurerm_sql_server.sql_server.name
}

output "sql_database_name" {
  value = azurerm_sql_database.sql_database.name
}

# Output the VM public IP for SHIR
output "vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}
