{
  name = "svc-go";
  language = "go";
  github = {
    codeowners = [ "@Fomiller" ];
    roleToAssume = "arn:aws:iam::000000000000:role/github-actions";
  };
  argocd = {
    environment = "prod";
  };
}
