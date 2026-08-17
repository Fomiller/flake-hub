{
  name = "golden-infra";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    infra = {
      envs = [ "dev" ];
      awsRegion = "us-east-1";
      namespace = "fomiller";
      stateBucket = "";
      terraformVersion = ">=1.11.0";
      awsProviderVersion = ">=5.0.0";
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
  overrides = [ ];
  executable = [ ];
  schema = {
    "infra.envs" = {
      type = "list";
      description = "Which environments get a directory under infra/live/. Only dev, staging and prod exist.";
    };
    "infra.dopplerProject" = {
      type = "string";
      required = true;
      description = "Doppler project the deploy workflow pulls secrets from.";
    };
    "infra.awsRegion" = {
      type = "string";
      description = "Region for the AWS provider and the state backend.";
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
    "infra.stateBucket" = {
      type = "string";
      description = "S3 bucket holding terraform state. Left empty, root.hcl derives <namespace>-<env>-terraform-state. infra/live/variables.hcl overrides either.";
    };
    "infra.terraformVersion" = {
      type = "string";
      description = "Version constraint written to the generated required_version.";
    };
    "infra.awsProviderVersion" = {
      type = "string";
      description = "Version constraint written to the generated aws provider block.";
    };
  };
}
