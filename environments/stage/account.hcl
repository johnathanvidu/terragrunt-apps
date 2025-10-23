# Set common variables for the environment. This is automatically pulled in in the root terragrunt.hcl configuration to
# feed forward to the child modules.
locals {
  environment    = "stage"
  aws_region     = "eu-west-1"
  account_name   = "stage"
  aws_account_id = "046086677675" # same as prod for testing purposes
}