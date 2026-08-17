test:
    nix run ./golden-base#test-eval

fmt:
    nix run nixpkgs#nixpkgs-fmt -- golden-engine golden-base golden-github golden-service golden-infra golden-argocd golden-docs renovate docs

docs:
    mdbook serve docs --open

docs-build:
    mdbook build docs
