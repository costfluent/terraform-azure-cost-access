terraform {
  required_version = ">= 1.9"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.7.0, < 4.0.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.1, < 1.0.0"
    }
  }
}
