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
      ecr = true;
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
    # The names and the infraDir variable are not ours to pick: the generated
    # deploy-infra.yml calls Fomiller/gh-actions, which runs
    # `just infraDir=<dir> plan-all`. A variable has to be declared before just
    # will accept an override for it, hence the entry below.
    just.variables = [
      { name = "infraDir"; value = "infra/live/dev"; }
    ];
    # doppler run is what turns Doppler values into TF_VAR_*. It stays even for
    # a repo holding no secrets, since the shared workflow requires a Doppler
    # project either way and an empty config injects nothing.
    #
    # {{infraDir}} is just syntax, and it survives as-is: the base template
    # emits these strings with {{ recipe }}, and Jinja does not re-render data.
    just.recipes = [
      "plan-all:\n    doppler run --name-transformer tf-var -- \\\n    terragrunt stack run --tf-path terraform --working-dir {{infraDir}} plan"
      # --non-interactive on apply only. Without it terragrunt asks to confirm
      # and CI answers with EOF. plan has nothing to confirm.
      "apply-all:\n    doppler run --name-transformer tf-var -- \\\n    terragrunt --non-interactive stack run --tf-path terraform --working-dir {{infraDir}} apply"
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
    # So is what the shared stack holds after the first write: the ECR unit is
    # where a repo adds a lifecycle rule or a second repository.
    scaffold = [
      "infra/live/*/README.md"
      "infra/live/*/terragrunt.stack.hcl"
      "infra/stacks/aws/common/terragrunt.stack.hcl"
      "infra/units/aws/common/ecr/*"
    ];
    retired = [ ];
  };
  # The rest of infra/units and infra/stacks is hand-written, so turning the
  # pack off has to take them too — otherwise the repo keeps terragrunt code
  # with no frame.
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
    "infra.ecr" = {
      type = "bool";
      description = "Whether to write the shared stack and its ECR unit, which creates the image and chart repositories the publish workflows push to.";
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
