{
  name = "infra-off";
  github.codeowners = [ "@Fomiller" ];
  infra = {
    enabled = false;
    dopplerProject = "unused";
    ownerEmail = "forrestmillerj@gmail.com";
  };
}
