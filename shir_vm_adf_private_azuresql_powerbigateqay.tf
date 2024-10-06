Goal:

Reorganize the Terraform code to:

	1.	Set up a Virtual Machine (VM) with a Self-Hosted Integration Runtime (SHIR) to connect MySQL replica with Azure Data Factory (ADF).
	2.	Configure Private Link between ADF and Azure SQL for securely loading curated data from MySQL replica to Azure SQL.
	3.	Set up a VM with Power BI Gateway to connect to Azure SQL.

Overview:

	•	Self-Hosted Integration Runtime (SHIR) VM will be used by ADF to connect to an on-prem or cloud-hosted MySQL database for data extraction.
	•	Azure Private Link will secure the communication between ADF and Azure SQL Database to avoid public exposure.
	•	A separate VM with Power BI Gateway installed will connect to the Azure SQL Database for reporting purposes.

Full Terraform Code

1. Virtual Network Setup

All resources (VMs, Private Endpoints, ADF, SQL Server) will be part of the same Virtual Network (VNet) for secure internal communication.

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

2. SHIR VM Setup (Connects MySQL Replica to ADF)

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

Explanation:

	•	VM is created with the necessary configurations to run the SHIR, which will be used to connect ADF to the MySQL Replica database for extraction.
	•	The VM is assigned a NIC in the SHIR subnet for secure communication.

3. Azure Data Factory and SHIR Integration

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

Explanation:

	•	A Self-Hosted Integration Runtime is deployed in Azure Data Factory to allow ADF to connect to external data sources (MySQL in this case).

4. Private Link between ADF and Azure SQL Database

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

Explanation:

	•	Private Endpoints for both Azure SQL Database and ADF are created, allowing secure communication through Private Link.
	•	Private DNS Zones are configured for both ADF and Azure SQL Database to resolve the private IPs of these services.

5. VM with Power BI Gateway to Connect to Azure SQL

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

Explanation:

	•	A VM is set up with a NIC in the SHIR VM subnet to install the Power BI Gateway. This allows the gateway to connect securely to the Azure SQL Database through the private network.

Final Summary

The reorganized Terraform code achieves the following:

	1.	VNet and Subnets: A VNet is created with two subnets: one for the SHIR VM and one for Private Endpoints.
	2.	SHIR VM: A Windows VM is created to host the Self-Hosted Integration Runtime, which connects to the MySQL Replica.
	3.	Data Factory: ADF is set up to manage the ETL processes, with its own SHIR instance.
	4.	Private Link Configuration: Private Endpoints for both ADF and Azure SQL are created to enable secure, private communication.
	5.	Power BI Gateway VM: Another Windows VM is configured to host the Power BI Gateway, which connects to the Azure SQL Database.

This setup ensures that all components communicate securely without exposing sensitive data to the public internet, adhering to enterprise security best practices.