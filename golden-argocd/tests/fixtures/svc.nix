{
  name = "svc-go";
  language = "go";
  github = {
    codeowners = [ "@Fomiller" ];
  };
  argocd = {
    environment = "prod";
  };
}
