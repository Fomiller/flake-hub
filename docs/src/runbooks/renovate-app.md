# Renovate GitHub App

Prerequisite for running Renovate in the cluster. Renovate needs its own GitHub
identity; a personal access token would tie every PR to a human account and
would not scope cleanly to a set of repos.

This is manual. Only the account owner can create a GitHub App.

## 1. Create the app

On the `Fomiller` account: **Settings → Developer settings → GitHub Apps → New
GitHub App**.

- **Name**: `fomiller-renovate`
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

**Install App** on the `Fomiller` account, and select the repositories that pin
flake-hub packs. Installing on all repositories also works and needs no
maintenance as repos are added.

Note the **App ID** from the app's settings page, and the **Installation ID**
from the URL after installing (`.../installations/<id>`).

## 4. Private key

On the app's settings page, **Generate a private key**. A `.pem` file
downloads — this is the only time you get it. Losing it means generating a new
one, which is not a disaster.

## 5. Put the credentials in Doppler

The cluster reads these through an External Secret. Store them under exactly
these names:

| Doppler secret | Value |
| --- | --- |
| `RENOVATE_APP_ID` | the App ID |
| `RENOVATE_INSTALLATION_ID` | the Installation ID |
| `RENOVATE_PRIVATE_KEY` | the full contents of the `.pem`, newlines included |

The private key is multi-line. Paste it whole; a key that has lost its newlines
fails at token exchange with an unhelpful error.

## 6. Verify

Once the cluster job runs, it should open a PR on a repo whose pins are behind.
If it authenticates but sees no repositories, the app is installed on the
account but not on that repository.
