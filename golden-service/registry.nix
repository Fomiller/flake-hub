{
  languages = {
    go = {
      buildImage = "golang:1.23";
      runtimeImage = "gcr.io/distroless/static-debian12";
      setupStep = ''
        - uses: actions/setup-go@v5
          with:
            go-version-file: go.mod
            cache: true'';
      # Go code lives under src/, and the binary goes to bin/ so a plain build
      # does not drop an untracked executable at the repo root.
      buildCmd = "go build -o bin/ ./src/...";
      testCmd = "go test ./src/... -race -cover";
      lintCmd = "go vet ./src/...";
    };
    rust = {
      buildImage = "rust:1.82";
      runtimeImage = "gcr.io/distroless/cc-debian12";
      setupStep = "- uses: dtolnay/rust-toolchain@stable";
      buildCmd = "cargo build --release";
      testCmd = "cargo test --all-features";
      lintCmd = "cargo clippy -- -D warnings";
    };
    # TypeScript. Node 24 is the active LTS line; 22 leaves support in October
    # 2026. Pinned here rather than read from a .nvmrc because that is how the
    # other two languages already work, and a repo missing the file would fail
    # in CI with an error that does not name it.
    node = {
      buildImage = "node:24";
      # Distroless, like the other two. Its ENTRYPOINT is already node, so the
      # Dockerfile passes the entry script as CMD rather than naming node.
      runtimeImage = "gcr.io/distroless/nodejs24-debian12";
      # Two steps, not one: nothing installs dependencies on its own the way
      # `go build` fetches modules, so the build and lint commands below would
      # have no node_modules to run against. `npm ci` over `npm install`
      # because it fails on a lockfile that disagrees with package.json
      # instead of quietly rewriting it.
      setupStep = ''
        - uses: actions/setup-node@v4
          with:
            node-version: 24
            cache: npm
        - name: install
          run: npm ci'';
      # npm scripts rather than the tools themselves. Go and Rust each have one
      # canonical build command; a TypeScript project's depends on its
      # framework, so package.json names them and this pack stays out of it.
      # The repo must define build, test, lint and typecheck.
      buildCmd = "npm run build";
      testCmd = "npm test";
      # typecheck runs here so `tsc --noEmit` (or `astro check`) is not
      # optional. A TypeScript repo that only lints still ships type errors,
      # because the bundler strips types without checking them.
      lintCmd = "npm run lint && npm run typecheck";
    };
  };
}
