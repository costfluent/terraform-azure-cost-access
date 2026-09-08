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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
