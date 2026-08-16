{
  name = "golden-infra";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    infra = {
      envs = [ "dev" ];
      awsRegion = "us-east-1";
      namespace = "fomiller";
      tailscale = true;
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
    "infra.envs" = { type = "list"; };
    "infra.dopplerProject" = { type = "string"; required = true; };
    "infra.awsRegion" = { type = "string"; };
    "infra.namespace" = { type = "string"; };
    "infra.ownerEmail" = { type = "string"; required = true; };
    "infra.tailscale" = { type = "bool"; };
    "infra.stateBucket" = { type = "string"; required = true; };
    "infra.terraformVersion" = { type = "string"; };
    "infra.awsProviderVersion" = { type = "string"; };
  };
}
