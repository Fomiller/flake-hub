{
  name = "gated-off";
  github = {
    codeowners = [ "@Fomiller" ];
    renovate = false;
    agents = false;
    buildAndTest = false;
  };
  # A job is contributed on purpose: buildAndTest = false has to win over it.
  ci.jobs = [{ name = "docs"; steps = [ "- run: make docs" ]; }];
}
