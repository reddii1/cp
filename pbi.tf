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
# source db
resource "azurerm_data_factory_linked_service_mysql" "mysql-adf-link" {
  count = length(local.cpenvprefix[terraform.workspace])
  name              = "mysql-adf-link-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mysql_flexible_server.replica[count.index].id};port=3306;username=${azurerm_mysql_flexible_server.replica[count.index].administrator_login};password=${azurerm_mysql_flexible_server.replica[count.index].administrator_password}"
} 

# sink db (curated)
resource "azurerm_data_factory_linked_service_azure_sql_database" "curated-adf-link" {
  count = length(local.cpenvprefix[terraform.workspace])
  name              = "curated-db-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id   = azurerm_data_factory.adf[count.index].id
  connection_string = "Server=${azurerm_mssql_server.curated_server[count.index].id};port=3306;username=${azurerm_mssql_server.curated_server[count.index].administrator_login};password=${azurerm_mssql_server.curated_server[count.index].administrator_login_password}"
  // connection_string = "data source=serverhostname;initial catalog=master;user id=testUser;Password=test;integrated security=False;encrypt=True;connection timeout=30"

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


# a new storage account, this could be changed to a pre-existing one

resource "azurerm_storage_account" "shir_storage" {
  name                     = "struksdevtdccnvtshir"
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 200
    }
  }
}

# new storage container 
resource "azurerm_storage_container" "shir" {
  name                 = "powerbi-shir"
  storage_account_name = azurerm_storage_account.shir_storage.name
}

# blob for the powershell file to go. This is for the VM to pull from 
resource "azurerm_storage_blob" "shir_script" {
  name                   = "adf-shir.ps1"
  storage_account_name   = azurerm_storage_account.shir_storage.name
  storage_container_name = azurerm_storage_container.shir.name
  type                   = "Block"
  access_tier            = "Cool"
  source                 = "../scripts/shir_download_install.ps1"
}




resource "random_string" "random" {
    length = 8
    special = false
}

resource "random_password" "shir_admin_password" {
  count = length(local.cpenvprefix[terraform.workspace])

  length           = 32
  special          = false
}

resource "azurerm_key_vault_secret" "shir_admin_password" {
  count = length(local.cpenvprefix[terraform.workspace])

  name         = "shir-${local.cpenvprefix[terraform.workspace][count.index]}password"
  value        = random_password.shir_admin_password[count.index].result
  key_vault_id = azurerm_key_vault.app.id
}

// this vm has to be windows since SHIR only supports it
resource "azurerm_virtual_machine" "shir_vm" {
  count = length(local.cpenvprefix[terraform.workspace])
  // The prefix "uksucc" is important for internal naming policies
  name                = "uksuccshir-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}-${random_string.random.result}"
  resource_group_name = azurerm_resource_group.rg_analytics[0].name
  location            = var.location
  
  network_interface_ids = [azurerm_network_interface.shir[count.index].id,]

  // The size of the VM will probably need to be changed in time
  vm_size               = "Standard_DS1_v2"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  // This picks up the image from the GoldImagesDevGallery/GoldImagesGallery depending on the environment
  storage_image_reference {
    id = data.azurerm_shared_image_version.win2019_latestGoldImage.id
  }

// if the virtual machine OS options are changed, for example, provision_vm_agent, then terraform may get stuck on deployment with an error similar to below:
// Message="Changing property 'windowsConfiguration.provisionVMAgent' is not allowed."
// to fix this error just delete stuff manually. Apparently this is fixed in 2.0 but we're outdated. 
  storage_os_disk {
    name              = "osDiskShir-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}-${random_string.random.result}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    // This MUST be randomised and stored in kv eventually
    admin_password = random_password.shir_admin_password[count.index].result
  }

  os_profile_windows_config {
    provision_vm_agent = true
    enable_automatic_upgrades = false

  }

}

resource "time_sleep" "wait_120_seconds" {
  depends_on = [ azurerm_virtual_machine.shir_vm]
  create_duration = "120s"
}

#VM Custom Script Extension to download and install the powershell script to activate SHIR to connect to ADF
resource "azurerm_virtual_machine_extension" "vmextension" {
  count = length(local.cpenvprefix[terraform.workspace])
  name                       = "shir-installation"
  virtual_machine_id         = azurerm_virtual_machine.shir_vm[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on = [ time_sleep.wait_120_seconds ]

  protected_settings = <<PROTECTED_SETTINGS
      {
          "fileUris": ["${format("https://%s.blob.core.windows.net/%s/%s", azurerm_storage_account.shir_storage.name, azurerm_storage_container.shir.name, azurerm_storage_blob.shir_script.name)}"],
          "commandToExecute": "${join(" ", ["powershell.exe -ExecutionPolicy Unrestricted -File",azurerm_storage_blob.shir_script.name,"-gatewayKey ${azurerm_data_factory_integration_runtime_self_hosted.shir[count.index].primary_authorization_key}"])}",
          "storageAccountName": "${azurerm_storage_account.shir_storage.name}",
          "storageAccountKey": "${azurerm_storage_account.shir_storage.primary_access_key}"
      }
  PROTECTED_SETTINGS

  

}
