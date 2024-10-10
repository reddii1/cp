# Custom Script Extension to download and install SHIR on the VM
resource "azurerm_virtual_machine_extension" "install_shir" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "install-shir"
  virtual_machine_id   = azurerm_virtual_machine.shir_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # Script for installing SHIR
  protected_settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"$gatewayKey = '${azurerm_data_factory_integration_runtime_self_hosted.shir[count.index].primary_authorization_key}'; $workingDir = 'C:\\SHIR'; New-Item -ItemType Directory -Force -Path $workingDir; Invoke-WebRequest -Uri https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.20.8260.1.msi -OutFile $workingDir\\IntegrationRuntime.msi; Start-Process msiexec.exe -Wait -ArgumentList '/i $workingDir\\IntegrationRuntime.msi /qn'; Start-Process 'C:\\Program Files\\Microsoft Integration Runtime\\5.0\\Shared\\diahost.exe' -ArgumentList '-k $gatewayKey' -Wait\""
  }
  SETTINGS

  tags = merge(var.tags, local.tags)
}