## Azure Data factory powerBI integration
resource "azurerm_data_factory" "adf" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
}


# creating self hosted integration runtime for data factory 
 resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}


# connecting replica mysql database to data factory for etl to azure sql
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count = length(local.cpenvprefix[terraform.workspace])
  name              = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
} 

resource "azurerm_network_interface" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "nic-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  ip_configuration {
    name                          = "shir"
    subnet_id                     = azurerm_subnet.fe02[0].id
    private_ip_address_allocation = "Dynamic"
  }

  tags = merge(var.tags, local.tags)
}

# resource "random_password" "vm-shir-adf-pass" {
#     length      = 20
#   min_lower   = 1
#   min_upper   = 1
#   min_numeric = 1
#   min_special = 1
#   special     = true
# }


// This should be randomised and stored in kv eventually
variable "admin_password" {
    type = string
    default = "To_be_randomised_later12443!"
}


resource "azurerm_windows_virtual_machine" "shir_vm" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                = "vm-shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  location            = var.location
  admin_username = "admin"
  admin_password = var.admin_password
  size                  = "Standard_D2s_v3"
  # This is from the GoldImagesDevGallery/GoldImagesGallery depending on the environment
  //source_image_id = data.azurerm_shared_image_version.win2019_latestGoldImage.id
  source_image_id = "/subscriptions/67e5f2ee-6e0a-49e3-b533-97f0beec351c/resourceGroups/rg-dwp-dev-ss-shared-images/providers/Microsoft.Compute/galleries/GoldImagesDevGallery/images/WIN2019-CIS2/versions/3.051.21819"
  network_interface_ids = [azurerm_network_interface.shir[0].id,]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

}


# resource "azurerm_storage_container" "dfa-shir" {
#   name                  = "shir-install-script"
#   storage_account_name  = azurerm_storage_account.omilia.name
#   container_access_type = "private"
# }
# locals {
#   script_name = ""
# }

# // to do: Create script to put shir on vm
# //        create az sql db for curated data
