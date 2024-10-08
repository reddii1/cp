#Adf Creation with mannaged_private_endpoint

data "azurerm_client_config" "current" {}

resource "azurerm_data_factory" "ADF" {
  name                            = "ADFNAME"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  managed_virtual_network_enabled = true
}

resource "azurerm_storage_account" "StoreageAccount" {
  name                     = "ADF_storeageAccount"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "BlobStorage"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_data_factory_managed_private_endpoint" "ADFprivendpoint" {
  name               = "ADF_private_endpoint"
  data_factory_id    = azurerm_data_factory.ADF.id
  target_resource_id = azurerm_storage_account.StoreageAccount.id
  subresource_name   = "blob"
}