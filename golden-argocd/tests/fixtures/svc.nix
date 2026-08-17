{
  name = "svc-go";
  language = "go";
  github = {
    codeowners = [ "@Fomiller" ];
    roleToAssume = "arn:aws:iam::000000000000:role/github-actions";
  };
  argocd = {
    environments = [ "dev" "prod" ];
    registry = "000000000000.dkr.ecr.us-east-1.amazonaws.com";
  };
}
