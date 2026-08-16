# GENERATED FILE — managed by flake-hub (golden-infra).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.
#
# Root terragrunt config. Every unit includes this, so a unit's own
# terragrunt.hcl needs only `include "root"` and its inputs.

locals {
  service_vars = read_terragrunt_config(find_in_parent_folders("service.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.account_vars.locals.environment
  region      = local.account_vars.locals.region
}

remote_state {
  backend = "s3"
  config = {
    encrypt               = true
    disable_bucket_update = true
    bucket                = "fomiller-tfstate-all"
    # <repo>/<env>/<unit...>/terraform.tfstate. repo_name is what keeps two
    # repos sharing this bucket from colliding.
    key          = "${local.service_vars.locals.repo_name}/${path_relative_to_include()}/terraform.tfstate"
    region       = local.region
    use_lockfile = true
  }
  generate = {
    path      = "_.backend.gen.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "_.provider.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
    }
  EOT
}

generate "versions" {
  path      = "_.versions.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">=1.11.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = ">=5.0.0"
        }
      }
    }
  EOF
}

generate "variables" {
  path      = "_.variables.gen.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "environment" {
      type    = string
      default = "${local.environment}"
    }
  EOF
}
