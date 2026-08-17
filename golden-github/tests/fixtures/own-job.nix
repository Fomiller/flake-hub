{
  name = "own-job-repo";
  github.codeowners = [ "@Fomiller" ];
  # A job a repo wrote itself. Nothing requires it to carry `stepsFrom`.
  ci.jobs = [{
    name = "docs";
    steps = [ "- name: build docs\n  run: make docs" ];
  }];
}
