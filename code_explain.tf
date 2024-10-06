In this extended version of the Terraform project, we will:

	•	Add a Power BI Gateway VM.
	•	Provision an Azure SQL Server and Database for curated data.
	•	Configure a Private Link between Azure Data Factory (ADF) and the Azure SQL Server to secure communication over the Azure backbone.

Below is the complete project structure with explanations, modularized and detailed for a Junior DevOps Engineer.

Extended Project Structure:

terraform-project/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Global variables
├── outputs.tf              # Outputs
├── backend.tf              # Backend config (if required)
├── modules/
│   ├── data_factory/
│   │   ├── main.tf         # Data Factory resources with Private Link to SQL
│   │   ├── variables.tf
│   ├── vm/
│   │   ├── main.tf         # SHIR VM, PowerBI Gateway VM
│   │   ├── variables.tf
│   ├── network/
│   │   ├── main.tf         # VNET, Subnet, NSG
│   │   ├── variables.tf
│   ├── sql/
│   │   ├── main.tf         # Azure SQL Server, Curated Database, Private Link
│   │   ├── variables.tf

1. Root Configuration (main.tf)

This file orchestrates all the modules and creates a common resource group.

provider "azurerm" {
  features {}
}

# Define local environment prefixes for resources
locals {
  cpenvprefix = {
    dev  = ["dev"]
    prod = ["prod"]
  }
  location_prefix = "wus"  # Adjust location prefix accordingly
}

# Resource group for all services
resource "azurerm_resource_group" "rg_app" {
  name     = "rg-${local.location_prefix}-${terraform.workspace}-app"
  location = var.location
}

# Data Factory with Private Link to Azure SQL
module "data_factory" {
  source               = "./modules/data_factory"
  resource_group_name  = azurerm_resource_group.rg_app.name
  location             = var.location
  env_prefix           = local.cpenvprefix[terraform.workspace]
  location_prefix      = local.location_prefix
  pdu                  = var.pdu
  sql_server_id        = module.sql.sql_server_id  # Link ADF to SQL Server via private link
  sql_server_private_link_service_id = module.sql.sql_private_link_service_id
}

# SHIR VM for Data Factory
module "vm_shir" {
  source               = "./modules/vm"
  resource_group_name  = azurerm_resource_group.rg_app.name
  location             = var.location
  ssh_public_key_path  = var.ssh_public_key_path
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  env_prefix           = local.cpenvprefix[terraform.workspace]
  location_prefix      = local.location_prefix
  pdu                  = var.pdu
  data_factory_id      = module.data_factory.adf_id
}

# Power BI Gateway VM
module "vm_powerbi" {
  source               = "./modules/vm"
  resource_group_name  = azurerm_resource_group.rg_app.name
  location             = var.location
  ssh_public_key_path  = var.ssh_public_key_path
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  env_prefix           = local.cpenvprefix[terraform.workspace]
  location_prefix      = local.location_prefix
  pdu                  = var.pdu
  is_powerbi_gateway   = true  # Flag to install Power BI Gateway
}

# Virtual Network and Subnet
module "network" {
  source              = "./modules/network"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  env_prefix          = local.cpenvprefix[terraform.workspace]
  location_prefix     = local.location_prefix
  pdu                 = var.pdu
}

# Azure SQL for curated data with Private Link
module "sql" {
  source              = "./modules/sql"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  sql_admin_username  = var.sql_admin_username
  sql_admin_password  = var.sql_admin_password
  env_prefix          = local.cpenvprefix[terraform.workspace]
  location_prefix     = local.location_prefix
  pdu                 = var.pdu
}

2. Global Variables (variables.tf)

These are the variables used throughout the project.

variable "location" {
  description = "Azure region"
  type        = string
  default     = "West US"
}

variable "pdu" {
  description = "Project Deployment Unit (e.g., app name)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key for VM access"
  type        = string
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
}

variable "admin_password" {
  description = "Admin password for VMs"
  type        = string
}

variable "sql_admin_username" {
  description = "Admin username for SQL Server"
  type        = string
}

variable "sql_admin_password" {
  description = "Admin password for SQL Server"
  type        = string
}

3. Outputs (outputs.tf)

These outputs show the critical details of your deployment.

output "vm_shir_public_ip" {
  value = module.vm_shir.vm_public_ip
}

output "vm_powerbi_public_ip" {
  value = module.vm_powerbi.vm_public_ip
}

output "sql_server_name" {
  value = module.sql.sql_server_name
}

output "data_factory_id" {
  value = module.data_factory.adf_id
}

Module 1: Data Factory with Private Link (modules/data_factory/main.tf)

This module provisions an Azure Data Factory and configures the Private Link to the SQL Server.

resource "azurerm_data_factory" "adf" {
  name                = "adf-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  name            = "shir-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf.id
}

resource "azurerm_private_endpoint" "adf_private_link" {
  name                = "adf-private-link-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "adf-to-sql"
    private_link_service_id        = var.sql_server_private_link_service_id
    is_manual_connection           = false
    private_connection_resource_id = var.sql_server_id
  }
}

output "adf_id" {
  value = azurerm_data_factory.adf.id
}

Variables for Data Factory Module (modules/data_factory/variables.tf)

variable "resource_group_name" {
  description = "Resource group for the Data Factory"
  type        = string
}

variable "location" {
  description = "Location of the Data Factory"
  type        = string
}

variable "env_prefix" {
  description = "Environment-specific prefix (e.g., dev, prod)"
  type        = string
}

variable "location_prefix" {
  description = "Prefix of the location"
  type        = string
}

variable "pdu" {
  description = "Project Deployment Unit"
  type        = string
}

variable "sql_server_id" {
  description = "ID of the Azure SQL Server"
  type        = string
}

variable "sql_server_private_link_service_id" {
  description = "Private Link Service ID for Azure SQL"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Private Link"
  type        = string
}

Module 2: Virtual Network (modules/network/main.tf)

This module provisions a virtual network and subnet for the VMs and the Data Factory Private Link.

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

output "subnet_id" {
  value = azurerm_subnet.subnet.id
}

Variables for Network Module (modules/network/variables.tf)

variable "resource_group_name" {
  description = "Resource group for the VNET"
  type        = string
}

variable "location" {
  description = "Location of the VNET"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix (e.g., dev, prod)"
  type        = string
}

variable "location_prefix" {
  description = "Location prefix"
  type        = string
}

variable "pdu" {
  description = "Project Deployment Unit"
  type        = string
}

Module 3: Virtual Machines for SHIR and Power BI (modules/vm/main.tf)

This module provisions both the Self-hosted Integration Runtime (SHIR) VM and the Power BI Gateway VM.

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_public_ip" "public_ip" {
  name                = "public-ip-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
}

resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.is_powerbi_gateway ? 1 : 0
  name                = "vm-${var.is_powerbi_gateway ? "powerbi-gateway" : "shir"}-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  network_interface_ids = [azurerm_network_interface.nic.id]
  size                = "Standard_B1ms"
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = filebase64("${path.module}/cloud-init-${var.is_powerbi_gateway ? "powerbi" : "shir"}.yaml")

  identity {
    type = "SystemAssigned"
  }
}

output "vm_public_ip" {
  value = azurerm_public_ip.public_ip.address
}

Variables for VM Module (modules/vm/variables.tf)

variable "resource_group_name" {
  description = "Resource group for the VM"
  type        = string
}

variable "location" {
  description = "Location of the VM"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix (e.g., dev, prod)"
  type        = string
}

variable "location_prefix" {
  description = "Location prefix"
  type        = string
}

variable "pdu" {
  description = "Project Deployment Unit"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for VM"
  type        = string
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
}

variable "admin_password" {
  description = "Admin password for the VM"
  type        = string
}

variable "is_powerbi_gateway" {
  description = "Flag to determine if the VM is for Power BI Gateway"
  type        = bool
  default     = false
}

Module 4: Azure SQL Server with Private Link (modules/sql/main.tf)

This module provisions the Azure SQL Server, a curated database, and configures the Private Link for secure communication with ADF.

resource "azurerm_sql_server" "sql_server" {
  name                         = "sql-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
}

resource "azurerm_sql_database" "sql_database" {
  name                = "curated-db-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  resource_group_name = var.resource_group_name
  location            = var.location
  server_name         = azurerm_sql_server.sql_server.name
  sku_name            = "S1"
}

resource "azurerm_private_link_service" "sql_private_link" {
  name                = "sql-private-link-${var.location_prefix}-${var.env_prefix}-${var.pdu}"
  location            = var.location
  resource_group_name = var.resource_group_name
  load_balancer_id    = azurerm_load_balancer.lb.id  # Optional, configure if required

  private_ip_address {
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
    subnet_id                     = var.subnet_id
  }
}

output "sql_server_name" {
  value = azurerm_sql_server.sql_server.name
}

output "sql_private_link_service_id" {
  value = azurerm_private_link_service.sql_private_link.id
}

output "sql_server_id" {
  value = azurerm_sql_server.sql_server.id
}

Variables for SQL Module (modules/sql/variables.tf)

variable "resource_group_name" {
  description = "Resource group for the SQL Server"
  type        = string
}

variable "location" {
  description = "Location of the SQL Server"
  type        = string
}

variable "env_prefix" {
  description = "Environment prefix (e.g., dev, prod)"
  type        = string
}

variable "location_prefix" {
  description = "Location prefix"
  type        = string
}

variable "pdu" {
  description = "Project Deployment Unit"
  type        = string
}

variable "sql_admin_username" {
  description = "Admin username for SQL Server"
  type        = string
}

variable "sql_admin_password" {
  description = "Admin password for SQL Server"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for Private Link"
  type        = string
}

Explanation for the Junior DevOps Engineer:

	1.	Terraform Modules:
	•	Terraform is modular, allowing you to split complex infrastructure into smaller reusable pieces. Each module is responsible for one logical part of the infrastructure (e.g., Data Factory, VM, Network).
	2.	Main Configuration (main.tf):
	•	This is the root file where all the modules are invoked and configured. It orchestrates the provisioning of resources across modules.
	3.	Variables:
	•	Variables help you parameterize your Terraform code. The values for region, resource names, admin credentials, and more are set as variables, making the code flexible across environments (e.g., dev, prod).
	4.	Modules:
	•	The Data Factory module provisions an ADF instance and integrates it with the SQL Server via Private Link for enhanced security.
	•	The VM module handles the provisioning of Self-hosted Integration Runtime (SHIR) VM and Power BI Gateway VM.
	•	The Network module provisions the Virtual Network (VNET) and Subnets required by the VMs and Private Link.
	•	The SQL module provisions the Azure SQL Server, the curated data database, and the Private Link Service.
	5.	Private Link:
	•	Private Link ensures that the Azure Data Factory communicates with the Azure SQL Server over a secure, private Azure network, avoiding exposure to the public internet.
	6.	SSH Keys:
	•	For SSH access to the VMs (for Power BI Gateway and SHIR), the ssh_public_key_path is used to specify the public key for secure login.
	7.	Outputs:
	•	The output section provides critical resource details like the public IP of the VMs, the SQL Server name, and ADF ID for reference after provisioning.

This configuration is designed to help you securely deploy infrastructure with Terraform in Azure, including advanced networking (Private Link), Azure Data Factory, Azure SQL, and virtual machines for Power BI and ADF SHIR.