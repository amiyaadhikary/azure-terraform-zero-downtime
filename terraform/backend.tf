# Backend infrastructure is bootstrapped outside this state by
# ../scripts/bootstrap-terraform-state.sh. Use a distinct key per environment.
terraform {
  backend "azurerm" {}
}
