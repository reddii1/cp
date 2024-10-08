resource "random_password" "admin_password" {
  count       = var.admin_password == null ? 1 : 0
  length      = 20
  special     = true
  min_numeric = 2
  min_upper   = 2
  min_lower   = 2
  min_special = 2
}

locals {
  admin_password = try(random_password.admin_password[0].result, var.admin_password)
}


# tfsec:ignore:azure-database-enable-audit tfsec:ignore:azure-database-enable-audit tfsec:ignore:azure-database-no-public-access
resource "azurerm_mssql_server" "sqlserver" {
  name                         = sqlname
  resource_group_name          = var.resource_group_name
  location                     = var.location
  administrator_login          = var.admin_username
  administrator_login_password = local.admin_password
  version                      = "12.0"
  minimum_tls_version          = "1.2"
  # public_network_access_enabled = true


  tags = {
    name = "gargash-dashboard-server"
  }

  outbound_network_restriction_enabled = false
}

resource "azurerm_mssql_firewall_rule" "sqlfirewall" {
  name             = sqlfirewallname
  server_id        = azurerm_mssql_server.sqlserver.id
  start_ip_address = "10.0.3.1"
  end_ip_address   = "10.0.3.252"
}

resource "azurerm_mssql_database" "sqldb" {
  name                        = sqldb-dev
  server_id                   = azurerm_mssql_server.sqlserver.id
  zone_redundant              = true
  sku_name                    = "GP_S_Gen5_1"
  auto_pause_delay_in_minutes = 60
  min_capacity                = 0.5

  tags = {
    name = "gargash-dashboard-db"
  }
}

resource "azurerm_private_endpoint" "sqlserver_private_endpoint" {
  name                = sqlserver-private-endpoint
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_endpoint_id

  private_service_connection {
    name                           = "${var.client_name}-privateserviceconnection"
    private_connection_resource_id = azurerm_mssql_server.databricks.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }
}

resource "azurerm_private_dns_zone" "db_private_zone" {
  name                = "privatelink.database.windows.net"
  resource_group_name = module.databricks.databricks_rg
}

resource "azurerm_private_dns_zone_virtual_network_link" "virtual_network_link" {
  name                  = "${var.client_name}-private-endpoint-private-dns-zone-link"
  resource_group_name   = module.databricks.databricks_rg
  private_dns_zone_name = azurerm_private_dns_zone.db_private_zone.name
  virtual_network_id    = var.vnet_id
}


