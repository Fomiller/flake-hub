{
  name = "infra-all";
  github.codeowners = [ "@Fomiller" ];
  infra = {
    dopplerProject = "infra-all";
    ownerEmail = "forrestmillerj@gmail.com";
    environments = {
      dev = {
        enabled = true;
        account = "111122223333";
        profile = "fomiller-dev";
      };
      staging = {
        enabled = true;
        region = "us-west-2";
        stateBucket = "fomiller-tfstate-staging";
      };
      prod = {
        enabled = true;
        account = "444455556666";
        rolePrefix = "fomiller-prod";
      };
    };
  };
}
