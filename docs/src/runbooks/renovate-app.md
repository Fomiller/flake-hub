# Renovate GitHub App

Prerequisite for running Renovate in the cluster. Renovate needs its own GitHub
identity; a personal access token would tie every PR to a human account and
would not scope cleanly to a set of repos.

This is manual. Only the account owner can create a GitHub App.

## 1. Create the app

On the `Fomiller` account: **Settings → Developer settings → GitHub Apps → New
GitHub App**.

- **Name**: `fomiller-renovate-bot`
- **Homepage URL**: the flake-hub repo URL is fine
- **Webhook**: uncheck **Active**. Renovate runs on a schedule, not on webhooks.

## 2. Permissions

Repository permissions:

| Permission | Access |
| --- | --- |
| Contents | Read and write |
| Pull requests | Read and write |
| Metadata | Read-only |
| Workflows | Read and write |

Workflows write access is needed because Renovate PRs can touch files under
`.github/workflows/`, and GitHub rejects those pushes without it.

Subscribe to no events.

## 3. Install it

**Install App** on the `Fomiller` account for all repositories. The
`autodiscoverFilter` in homelab `k8s/apps/renovate/renovate-config.json` limits
which repos Renovate touches, so the install scope does not need to.

Note the **App ID** from the app's settings page, and the **Installation ID**
from the URL after installing (`.../installations/<id>`).

## 4. Private key

On the app's settings page, **Generate a private key**. A `.pem` file
downloads — this is the only time you get it. Losing it means generating a new
one, which is not a disaster.

## 5. Put the credentials in Doppler

The cluster reads these through an External Secret. They live in the Doppler
project `renovate`, config `dev`:

| Doppler secret | Value |
| --- | --- |
| `RENOVATE_APP_ID` | the App ID |
| `RENOVATE_CLIENT_ID` | the Client ID |
| `RENOVATE_INSTALLATION_ID` | the Installation ID |
| `RENOVATE_PRIVATE_KEY` | the full contents of the `.pem`, newlines included |

The private key is multi-line. Paste it whole; a key that has lost its newlines
fails at token exchange with an unhelpful error.

## 6. How the cluster uses the key

Self-hosted Renovate cannot use the App key directly. Each run first mints an
installation token from the key, using homelab
`k8s/apps/renovate/mint-token.js`, and hands that token to Renovate.

## 7. Verify

Once the cluster job runs, it should open a PR on a repo whose pins are behind.
If it authenticates but sees no repositories, the app is installed on the
account but not on that repository, or the repo is not in `autodiscoverFilter`.

## Operations

The CronJob `renovate` runs every 15 minutes in the `renovate` namespace.

- Logs: `kubectl -n renovate logs job/<name>`
- Manual run:
  `kubectl -n renovate create job --from=cronjob/renovate renovate-manual-1`
- Suspend:
  `kubectl -n renovate patch cronjob renovate -p '{"spec":{"suspend":true}}'`
  Set `suspend` to `false` to resume.
- Promote a pack:
  `kargo promote --project renovate-config --stage release --freight <name>`,
  or use the Kargo UI.

Pack pins move only after a Kargo promotion in the `renovate-config` repo.
