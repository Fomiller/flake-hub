{
  name = "golden-infra";
  templates = ./templates;
  partials = ./partials;
  defaults = {
    infra = {
      envs = [ "dev" ];
      awsRegion = "us-east-1";
      tailscale = true;
      terraformVersion = ">=1.11.0";
      awsProviderVersion = ">=5.0.0";
    };
    # {{env}} is just syntax, and it survives as-is: the base template emits
    # these strings with {{ recipe }}, and Jinja does not re-render data.
    just.recipes = [
      "plan env=\"dev\":\n    cd infra/live/{{env}} && terragrunt run-all plan"
      "apply env=\"dev\":\n    cd infra/live/{{env}} && terragrunt run-all apply"
    ];
  };
  registry = { };
  ownership = {
    managed = [
      "infra/live/root.hcl"
      "infra/live/service.hcl"
      "infra/live/*/account.hcl"
      ".github/workflows/deploy-infra.yml"
    ];
    scaffold = [ "infra/live/*/README.md" ];
    retired = [ ];
  };
  overrides = [ ];
  executable = [ ];
  schema = {
    "infra.envs" = { type = "list"; };
    "infra.dopplerProject" = { type = "string"; required = true; };
    "infra.awsRegion" = { type = "string"; };
    "infra.tailscale" = { type = "bool"; };
    "infra.stateBucket" = { type = "string"; required = true; };
    "infra.terraformVersion" = { type = "string"; };
    "infra.awsProviderVersion" = { type = "string"; };
  };
}
