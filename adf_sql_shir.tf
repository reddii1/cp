###
### MySQL stuff
###

### Azure Data factory powerBI integration
resource "azurerm_data_factory" "adf" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
}


#replying self hosted integration runtime for data factory 
 resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf.id
}


# connecting replica mysql database to data factory for etl to azure sql
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count = length(local.cpenvprefix[terraform.workspace])
  name              = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf.id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
} 
# Define a virtual network and subnet for the VM
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name  = azurerm_resource_group.rg_app.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Define a network interface for the VM
resource "azurerm_network_interface" "nic" {
  name                = "nic-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Define a public IP for the VM (optional)
resource "azurerm_public_ip" "public_ip" {
  name                = "public-ip-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  allocation_method   = "Dynamic"
}

# Define the virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-shir-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  size                = "Standard_B2s"

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
    name                 = "${azurerm_linux_virtual_machine.vm.name}-osdisk"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  admin_username          = var.admin_username
  admin_password          = var.admin_password

  # Use SSH keys instead of passwords for better security
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }
}

# Output the public IP address of the VM (optional)
output "vm_public_ip" {
  value       = azurerm_public_ip.public_ip.ip_address
}
# Define SQL Server
resource "azurerm_sql_server" "sql_server" {
  name                         = "sql-server-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name          = azurerm_resource_group.rg_app.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
}

# Define SQL Database
resource "azurerm_sql_database" "sql_db" {
  name                = "sql-db-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name = azurerm_resource_group.rg_app.name
  location            = var.location
  server_name         = azurerm_sql_server.sql_server.name
}

# Define SQL Firewall Rule (optional)
resource "azurerm_sql_firewall_rule" "sql_firewall_rule" {
  name                = "allow-all-azure"
  resource_group_name = azurerm_resource_group.rg_app.name
  server_name         = azurerm_sql_server.sql_server.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Existing VM definition with additional Power BI Gateway setup
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-shir-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_app.name
  size                = "Standard_B2s"

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
    name                 = "${azurerm_linux_virtual_machine.vm.name}-osdisk"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  admin_username          = var.admin_username
  admin_password          = var.admin_password

  # Use SSH keys instead of passwords for better security
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  # Install Power BI Gateway using a custom script (example)
  provisioner "remote-exec" {
    inline = [
      # Update and install necessary packages
      "sudo apt-get update",
      # Command to download and install Power BI Gateway (replace with actual commands)
      # Example: wget <Power BI Gateway URL> && sudo dpkg -i <package-name>
    ]
    
    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.public_ip.ip_address
    }
  }
}


