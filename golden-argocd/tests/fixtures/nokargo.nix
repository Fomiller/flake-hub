{
  name = "svc-plain";
  language = "go";
  github.codeowners = [ "@Fomiller" ];
  argocd = {
    environment = "dev";
    kargo = false;
  };
}
