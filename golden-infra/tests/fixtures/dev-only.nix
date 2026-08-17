{
  name = "infra-dev";
  codeowners = [ "@Fomiller" ];
  infra = {
    # No stateBucket, so this fixture renders the derived name.
    dopplerProject = "infra-dev";
    ownerEmail = "forrestmillerj@gmail.com";
  };
}
