locals {
  # Automatically load account-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("environemnts.hcl"))

  # Automatically load region-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load environment-level variables
  app_vars = read_terragrunt_config(find_in_parent_folders("app.hcl"))

  # Extract the variables we need for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region
}