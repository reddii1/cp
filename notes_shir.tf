To retrieve the Primary Authorization Key for the Self-Hosted Integration Runtime (SHIR) in Azure Data Factory, you can access it programmatically using the Azure CLI, the Azure Portal, or through Terraform.

Retrieving the Authorization Key via Terraform

In your current Terraform setup, you’re creating a Self-Hosted Integration Runtime (SHIR) using the azurerm_data_factory_integration_runtime_self_hosted resource. Terraform provides access to the Primary Authorization Key through an output attribute.

Example: Accessing the Primary Authorization Key in Terraform

You can access the primary authorization key for the SHIR using the attribute primary_authorization_key from the azurerm_data_factory_integration_runtime_self_hosted resource.

Here’s how to modify your existing code to retrieve and output the key for further use:

Step 1: Define an Output for the Authorization Key

# Creating Self-hosted Integration Runtime for Data Factory 
resource "azurerm_data_factory_integration_runtime_self_hosted" "shir" {
  count = length(local.cpenvprefix[terraform.workspace])
  name            = "shir-adf-${local.location_prefix}-${local.cpenvprefix[terraform.workspace][count.index]}${terraform.workspace}-${var.pdu}"
  data_factory_id = azurerm_data_factory.adf[count.index].id
}

# Output the Primary Authorization Key
output "primary_authorization_key" {
  value = azurerm_data_factory_integration_runtime_self_hosted.shir[*].primary_authorization_key
  sensitive = true  # This hides the output in the Terraform state files
}

	•	The primary_authorization_key attribute is available directly after the SHIR is created, and this output retrieves the keys for all SHIR instances created by Terraform (one per environment, based on your count usage).
	•	The sensitive = true option prevents Terraform from logging the key in plain text during plan and apply operations.

Step 2: Use the Authorization Key in the Custom Script Extension

You can directly reference the primary_authorization_key in your Custom Script Extension like this:

resource "azurerm_virtual_machine_extension" "install_shir" {
  count                = length(local.cpenvprefix[terraform.workspace])
  name                 = "install-shir"
  virtual_machine_id   = azurerm_virtual_machine.shir_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # Use the primary authorization key from SHIR resource
  protected_settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"$gatewayKey = '${azurerm_data_factory_integration_runtime_self_hosted.shir[count.index].primary_authorization_key}'; $workingDir = 'C:\\SHIR'; New-Item -ItemType Directory -Force -Path $workingDir; Invoke-WebRequest -Uri https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.20.8260.1.msi -OutFile $workingDir\\IntegrationRuntime.msi; Start-Process msiexec.exe -Wait -ArgumentList '/i $workingDir\\IntegrationRuntime.msi /qn'; Start-Process 'C:\\Program Files\\Microsoft Integration Runtime\\5.0\\Shared\\diahost.exe' -ArgumentList '-k $gatewayKey' -Wait\""
  }
  SETTINGS

  tags = merge(var.tags, local.tags)
}

Step 3: Retrieving the Key After Deployment

Once you’ve run terraform apply, the primary authorization key will be retrieved, and you can access it as output. If you need to see the value, you can execute:

terraform output primary_authorization_key

This will display the sensitive output if you’re logged in securely, or you can use it programmatically within your custom extensions as shown in the example above.

Other Methods to Get the Key

If you ever need to manually retrieve the authorization key outside of Terraform, you can use:

	•	Azure Portal: Go to your Azure Data Factory -> “Manage” -> “Integration Runtimes” -> Select your SHIR -> “Access keys”.
	•	Azure CLI: Use the following command to retrieve the SHIR key:

az datafactory integration-runtime self-hosted list-auth-key --resource-group <resource-group> --factory-name <data-factory-name> --name <integration-runtime-name>



This approach ensures that the authorization key is securely retrieved and used during the SHIR installation process on your Windows VM.