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
  };
}
