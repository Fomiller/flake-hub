{
  name = "publish-repo";
  github = {
    codeowners = [ "@Fomiller" ];
    roleToAssume = "arn:aws:iam::000000000000:role/github-actions";
    publishImage = true;
    publishChart = true;
    platforms = [ "linux/amd64" "linux/arm64" ];
  };
}
