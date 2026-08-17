{
  name = "svc-off";
  language = "go";
  github.codeowners = [ "@Fomiller" ];
  argocd = {
    enabled = false;
    registry = "000000000000.dkr.ecr.us-east-1.amazonaws.com";
  };
}
