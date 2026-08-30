{
  name = "publish-repo";
  github = {
    codeowners = [ "@Fomiller" ];
    publishImage = true;
    publishChart = true;
    platforms = [ "linux/amd64" "linux/arm64" ];
  };
}
