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
  }
}

# azurerm no longer falls back to the CLI's default subscription; it must be named.
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azuread" {}
