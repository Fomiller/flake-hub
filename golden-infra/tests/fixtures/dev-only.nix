{
  name = "infra-dev";
  codeowners = [ "@Fomiller" ];
  # Nothing per environment, so dev renders on the pack defaults alone and the
  # bucket falls through to the derived name.
  infra = {
    dopplerProject = "infra-dev";
    ownerEmail = "forrestmillerj@gmail.com";
  };
}
