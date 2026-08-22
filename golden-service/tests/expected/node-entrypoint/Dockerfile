# ---------------------------------------------------------------------------
# GENERATED FILE — managed by flake-hub (golden-service).
# Do not edit manually: `nix run .#generate` overwrites it.
# To change it, edit repo.nix, or the template in the pack that owns it.
# ---------------------------------------------------------------------------

FROM node:24 AS build
WORKDIR /src
# Manifests before sources, so an edit that leaves dependencies alone reuses
# the install layer.
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build
# devDependencies built the app and have no business in the runtime image.
RUN npm prune --omit=dev

FROM gcr.io/distroless/nodejs24-debian12
WORKDIR /app
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/dist ./dist
EXPOSE 8080
# The distroless node image already entrypoints on node, so this is the script
# to run, not the command.
CMD ["dist/server/entry.mjs"]
