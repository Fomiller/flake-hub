{
  name = "infra-all";
  codeowners = [ "@Fomiller" ];
  infra = {
    dopplerProject = "infra-all";
    stateBucket = "fomiller-tfstate-all";
    ownerEmail = "forrestmillerj@gmail.com";
    envs = [ "dev" "staging" "prod" ];
  };
}
