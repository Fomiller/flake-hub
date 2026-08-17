let
  # Every environment carries every field, so a template can read one without
  # guessing whether the repo set it. Empty means "not set".
  env = enabled: {
    inherit enabled;
    account = "";
    region = "us-east-1";
    rolePrefix = "";
    profile = "";
    stateBucket = "";
  };
in
{
  name = "golden-infra";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    infra = {
      enabled = true;
      namespace = "fomiller";
      terraformVersion = ">=1.11.0";
      awsProviderVersion = ">=5.0.0";
      environments = {
        dev = env true;
        staging = env false;
        prod = env false;
      };
    };
    # Everything under infra/live/<env>/ other than the three committed files
    # is written by `terragrunt stack run`.
    gitignore = [
      ".terragrunt-cache/"
      ".terragrunt-stack/"
      ".terragrunt-stack-manifest"
      "terragrunt.values.hcl"
      "**/_.*.gen.tf"
      "**/.terraform.lock.hcl"
      "infra/live/*/*/"
    ];
    # {{env}} is just syntax, and it survives as-is: the base template emits
    # these strings with {{ recipe }}, and Jinja does not re-render data.
    just.recipes = [
      "plan env=\"dev\":\n    cd infra/live/{{env}} && terragrunt stack run plan"
      "apply env=\"dev\":\n    cd infra/live/{{env}} && terragrunt stack run apply"
    ];
  };
  registry = { };
  ownership = {
    managed = [
      "infra/live/root.hcl"
      "infra/live/service.hcl"
      "infra/live/tags.hcl"
      "infra/live/version.hcl"
      "infra/live/*/account.hcl"
      ".github/workflows/deploy-infra.yml"
    ];
    # Which stacks an environment gets is the repo's business, not the pack's.
    scaffold = [
      "infra/live/*/README.md"
      "infra/live/*/terragrunt.stack.hcl"
    ];
    retired = [ ];
  };
  # infra/units and infra/stacks are hand-written, so turning the pack off has
  # to take them too — otherwise the repo keeps terragrunt code with no frame.
  retireTrees = [
    { unless = "infra.enabled"; trees = [ "infra" ]; }
  ];
  overrides = [ ];
  executable = [ ];
  schema = {
    "infra.enabled" = {
      type = "bool";
      description = "Whether this repo manages infrastructure. False deletes infra/ and the deploy workflow.";
    };
    "infra.dopplerProject" = {
      type = "string";
      required = true;
      description = "Doppler project the deploy workflow pulls secrets from.";
    };
    "infra.namespace" = {
      type = "string";
      description = "Prefix on resource names, so two repos in one account do not collide.";
    };
    "infra.ownerEmail" = {
      type = "string";
      required = true;
      description = "Goes on every resource as an owner tag. infra/live/variables.hcl can override it per tree.";
    };
    "infra.terraformVersion" = {
      type = "string";
      description = "Version constraint written to the generated required_version.";
    };
    "infra.awsProviderVersion" = {
      type = "string";
      description = "Version constraint written to the generated aws provider block.";
    };
    "infra.environments" = {
      type = "attrsOf";
      keys = [ "dev" "staging" "prod" ];
      description = "Per-environment settings. An environment exists under infra/live/ only while its enabled is true.";
      fields = {
        enabled = {
          type = "bool";
          description = "Whether this environment gets a directory under infra/live/.";
        };
        account = {
          type = "string";
          description = "AWS account ID, written to account.hcl for the units to read.";
        };
        region = {
          type = "string";
          description = "Region for the AWS provider, the state backend and the deploy job.";
        };
        rolePrefix = {
          type = "string";
          description = "Role-name base the units build their OIDC ARNs from.";
        };
        profile = {
          type = "string";
          description = "Local AWS profile name, for running terragrunt by hand.";
        };
        stateBucket = {
          type = "string";
          description = "Overrides the derived <namespace>-<env>-terraform-state. infra/live/variables.hcl still wins.";
        };
      };
    };
  };
}
