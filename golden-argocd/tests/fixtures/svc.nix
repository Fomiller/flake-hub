{
  name = "svc-go";
  codeowners = [ "@Fomiller" ];
  language = "go";
  deploy = {
    ecrRepo = "charts";
    roleToAssume = "arn:aws:iam::000000000000:role/github-actions";
  };
}
