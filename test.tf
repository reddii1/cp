# Data Factory
resource "azurerm_data_factory" "adf" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
}

# Self-hosted Integration Runtime for Data Factory
resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count           = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}

# Connecting MySQL Replica to Data Factory
resource "azurerm_data_factory_linked_service_mysql" "mysql_adf_link" {
  count            = length(local.cpenvprefix[terraform.workspace])
  name             = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id  = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].fqdn};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
}

# Network Interface for SHIR VM
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

# Random Password for SHIR VM
resource "random_password" "vm_shir_adf_pass" {
  count             = length(local.cpenvprefix[terraform.workspace])
  length            = 36
  override_special  = "-"
}

# SHIR Windows Virtual Machine
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

# Storage Container for SHIR Install Script
resource "azurerm_storage_container" "dfa_shir" {
  name                  = "shir-install-script"
  storage_account_name  = azurerm_storage_account.omilia.name
  container_access_type = "private"
}

# Private Endpoint for Data Factory
resource "azurerm_private_endpoint" "adf_private_endpoint" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "pe-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  subnet_id           = azurerm_subnet.mysqlfs[count.index].id

  private_service_connection {
    name                           = "adf-connection"
    private_connection_resource_id = azurerm_data_factory.adf[count.index].id
    subresource_names              = ["dataFactory"]
    is_manual_connection           = false
  }

  tags = merge(var.tags, local.tags)
}

# Power BI Gateway VM
resource "azurerm_windows_virtual_machine" "pbi_gateway_vm" {
  count               = length(local.cpenvprefix[terraform.workspace])
  name                = "vm-pbi-gateway-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  computer_name       = "vm-pbi-gateway"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  admin_username      = "admin"
  admin_password      = random_password.vm_shir_adf_pass[count.index].result
  size                = "Standard_D4as_v4"
  patch_assessment_mode = "AutomaticByPlatform"
  network_interface_ids = [
    azurerm_network_interface.shir[count.index].id,
  ]
  os_disk {
    name                 = "osd-pbi-gateway"
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

  # Custom Script to Install Power BI Gateway
  provisioner "remote-exec" {
    inline = [
      "Invoke-WebRequest -Uri 'https://download.microsoft.com/download/powerbigatewayinstaller.exe' -OutFile 'C:\\powerbigatewayinstaller.exe'",
      "Start-Process 'C:\\powerbigatewayinstaller.exe' -ArgumentList '/quiet' -Wait",
      "Write-Host 'Power BI Gateway installed successfully.'"
    ]
  }

  tags = merge(var.tags, local.tags)
}

# Ensure Connectivity between Power BI VM and ADF, SQL, etc.
resource "azurerm_network_interface_security_group_association" "pbi_gateway_nsg_association" {
  count                 = length(local.cpenvprefix[terraform.workspace])
  network_interface_id  = azurerm_network_interface.shir[count.index].id
  network_security_group_id = azurerm_network_security_group.pbi_gateway_nsg.id
}

# NSG for Power BI Gateway VM
resource "azurerm_network_security_group" "pbi_gateway_nsg" {
  name                = "pbi-gateway-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowPowerBIGateway"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8050"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

locals {
  script_name = "install-shir.ps1"
}