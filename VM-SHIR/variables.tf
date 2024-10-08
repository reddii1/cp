variable "location" {
  description = "Azure region where resources will be created"
  default     = "UK South"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  default     = "rg-uks-debt-dc-cnv-app"
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  default     = "ynet-uks-devt-dc-chv"

}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  default     = "10.0.0.0/16"
}

variable "subnet_name" {
  description = "Name of the Subnet"
  default     = "mysgifs-app-devt"
}

/* variable "subnet_address_prefix" {
  description = "Subnet address prefix"
  default     = "10.0.1.0/24"
} */

variable "public_ip_name" {
  description = "Name of the Public IP"
  default     = "SHIR-PIP"
}

variable "nic_name" {
  description = "Name of the Network Interface"
  default     = "SHIR-nic"
}

variable "vm_name" {
  description = "Name of the Virtual Machine"
  default     = "SHIR-vm"
}

variable "vm_size" {
  description = "Size of the Virtual Machine"
  default     = "Standard_DS1_v2"
}

variable "admin_username" {
  description = "Admin username for the Virtual Machine"
  default     = "adminuser"
}

variable "admin_password" {
  description = "Admin password for the Virtual Machine"
  type        = string
  sensitive   = true
}
