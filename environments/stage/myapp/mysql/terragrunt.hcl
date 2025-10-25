# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# This is the configuration for Terragrunt, a thin wrapper for Terraform and OpenTofu that helps keep your code DRY and
# maintainable: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration. The root configuration contains settings that are common across all
# components and environments, such as how to configure remote state.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Extract out common variables for reuse
  env = local.account_vars.locals.environment
}

# Configure the version of the module to use in this environment. This allows you to promote new versions one
# environment at a time (e.g., qa -> stage -> prod).
terraform {
  source = "github.com/gruntwork-io/terragrunt-infrastructure-modules-example//modules/mysql?ref=v0.8.0"
}

inputs = {
  name              = "mysql_${local.env}"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "standard"
  master_username   = "admin"

  # TODO: To avoid storing your DB password in the code, set it as the environment variable TF_VAR_master_password
}