{
  name = "svc-node-entry";
  github.codeowners = [ "@Fomiller" ];
  language = "node";
  # An Astro standalone build, which is the reason the key exists: the entry
  # script is nowhere near the dist/index.js default.
  service.entrypoint = "dist/server/entry.mjs";
}
