{
  name = "infra-no-ecr";
  github.codeowners = [ "@Fomiller" ];
  # A repo that manages infrastructure but publishes no image or chart, so it
  # has nothing for the ECR unit to create.
  infra = {
    ecr = false;
    dopplerProject = "infra-no-ecr";
    ownerEmail = "forrestmillerj@gmail.com";
  };
}
