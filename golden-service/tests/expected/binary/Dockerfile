# ---------------------------------------------------------------------------
# GENERATED FILE — managed by flake-hub (golden-service).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.
# ---------------------------------------------------------------------------

FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/worker ./src/cmd/worker

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/worker /worker
EXPOSE 8080
ENTRYPOINT ["/worker"]
