{
  name = "svc-go";
  codeowners = [ "@Fomiller" ];
  language = "go";
  argocd = {
    envs = [ "dev" "prod" ];
    registry = "000000000000.dkr.ecr.us-east-1.amazonaws.com";
    roleToAssume = "arn:aws:iam::000000000000:role/github-actions";
  };
}
