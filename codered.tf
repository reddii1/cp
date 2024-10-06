# Virtual Network (VNet) Setup
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  address_space       = ["10.0.0.0/16"]

  tags = var.tags
}

# Subnet for SHIR VM
resource "azurerm_subnet" "shir_vm_subnet" {
  name                 = "snet-shir-vm"
  resource_group_name  = azurerm_resource_group.rg_app.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subnet for Private Endpoints (for ADF and SQL)
resource "azurerm_subnet" "private_link_subnet" {
  name                 = "snet-private-link"
  resource_group_name  = azurerm_resource_group.rg_app.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegations {
    name = "delegation-private-endpoint"
    service_delegation {
      name    = "Microsoft.Sql/servers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Random Password for SHIR VM
resource "random_password" "shir_vm_pass" {
  count = 1
  length           = 36
  override_special = "-"
}

# Network Interface for SHIR VM
resource "azurerm_network_interface" "shir_vm_nic" {
  name                = "nic-shir-vm-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.shir_vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Virtual Machine for SHIR
resource "azurerm_windows_virtual_machine" "shir_vm" {
  name                = "vm-shir-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  size                = "Standard_D2as_v4"
  admin_username      = "adminuser"
  admin_password      = random_password.shir_vm_pass[0].result
  network_interface_ids = [
    azurerm_network_interface.shir_vm_nic.id,
  ]
  os_disk {
    name                 = "osdisk-shir-vm"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

# Azure Data Factory
resource "azurerm_data_factory" "adf" {
  name                = "adf-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
}

# Self-Hosted Integration Runtime (SHIR)
resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  name            = "adf-shir-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf.id
}

# Private Endpoint for Azure SQL Database
resource "azurerm_private_endpoint" "sql_private_endpoint" {
  name                = "sql-private-endpoint-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  subnet_id           = azurerm_subnet.private_link_subnet.id

  private_service_connection {
    name                           = "sql-to-adf"
    private_connection_resource_id = azurerm_sql_server.sql_server.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }
}

# Private DNS Zone for SQL Private Link
resource "azurerm_private_dns_zone" "sql_dns_zone" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg_app.name
}

# DNS Zone Link to VNet for SQL
resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_zone_vnet_link" {
  name                  = "sql-dns-zone-vnet-link"
  resource_group_name   = azurerm_resource_group.rg_app.name
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# Private Endpoint for ADF
resource "azurerm_private_endpoint" "adf_private_endpoint" {
  name                = "adf-private-endpoint-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  subnet_id           = azurerm_subnet.private_link_subnet.id

  private_service_connection {
    name                           = "adf-to-sql"
    private_connection_resource_id = azurerm_data_factory.adf.id
    subresource_names              = ["datafactory"]
    is_manual_connection           = false
  }
}

# Private DNS Zone for ADF Private Link
resource "azurerm_private_dns_zone" "adf_dns_zone" {
  name                = "privatelink.datafactory.azure.net"
  resource_group_name = azurerm_resource_group.rg_app.name
}

# DNS Zone Link to VNet for ADF
resource "azurerm_private_dns_zone_virtual_network_link" "adf_dns_zone_vnet_link" {
  name                  = "adf-dns-zone-vnet-link"
  resource_group_name   = azurerm_resource_group.rg_app.name
  private_dns_zone_name = azurerm_private_dns_zone.adf_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# Random Password for Power BI Gateway VM
resource "random_password" "powerbi_vm_pass" {
  count = 1
  length           = 36
  override_special = "-"
}

# Network Interface for Power BI VM
resource "azurerm_network_interface" "powerbi_vm_nic" {
  name                = "nic-powerbi-vm-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.shir_vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Virtual Machine for Power BI Gateway
resource "azurerm_windows_virtual_machine" "powerbi_vm" {
  name                = "vm-powerbi-${local.cpenvprefix[terraform.workspace]}-${var.pdu}"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  size                = "Standard_D2as_v4"
  admin_username      = "adminuser"
  admin_password      = random_password.powerbi_vm_pass[0].result
  network_interface_ids = [
    azurerm_network_interface.powerbi_vm_nic.id,
  ]
  os_disk {
    name                 = "osdisk-powerbi-vm"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}