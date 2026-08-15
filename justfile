test:
    nix run ./golden-base#test-eval

fmt:
    nixpkgs-fmt golden-engine golden-base
