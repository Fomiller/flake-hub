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
      buildCmd = "go build ./...";
      testCmd = "go test ./... -race -cover";
      lintCmd = "go vet ./...";
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
