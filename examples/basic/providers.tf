terraform {
  required_version = ">= 1.13"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.9"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }
}

# azurerm no longer falls back to the CLI's default subscription; it must be named.
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azuread" {}
