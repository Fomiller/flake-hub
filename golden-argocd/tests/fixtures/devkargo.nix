{
  name = "svc-dev";
  language = "go";
  github.codeowners = [ "@Fomiller" ];
  argocd = {
    environment = "dev";
    kargo = true;
  };
}
