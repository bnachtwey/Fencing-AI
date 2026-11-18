# Claude Code Sandbox

A Podman Compose setup that runs [Claude Code](https://claude.ai/code) inside a network-isolated sandbox, so the agent can only reach Anthropic's own domains and nothing else on the network.

## Why

Claude Code can run arbitrary shell commands on your behalf. This setup fences its egress traffic through a Squid proxy that only allows HTTPS CONNECT to `.claude.ai`, `.claude.com`, and `.anthropic.com`. The container running Claude has no other route to the host or the outside world, so even a compromised or misbehaving session can't exfiltrate data or reach arbitrary hosts.

## Architecture

Two services, two Podman networks, defined in `compose.yaml`:

- **`claude`** (`Dockerfile.claude`) — Alpine with Node, npm, git, ripgrep, and `@anthropic-ai/claude-code` installed globally. Runs as a non-root `claude` user (uid/gid from `HOST_UID`/`HOST_GID`, mapped via `userns_mode: keep-id`). Its entrypoint (`entrypoint.sh`) seeds `$HOME` from `/etc/skel` (a starter `.bashrc`, `.bash_profile`, and empty `.claude` dir) without overwriting anything already there, then execs the real command (`claude` by default).
- **`proxy`** (`Dockerfile.proxy`) — Alpine with Squid, configured by `squid.conf` to allow CONNECT only to the allowed Anthropic domains and deny everything else.
- **`isolated` network** — internal-only, no route to the host or the internet. Connects `claude` and `proxy`. This is the only network the `claude` container is on.
- **`egress` network** — connects only `proxy` to the outside world. This is the sole path any traffic from `claude` can take to leave the sandbox, and only through Squid's allowlist.
- **Volumes**:
  - `${WORK_DIR}` (host) → `/work` in the `claude` container — the working directory Claude operates in.
  - `${CLAUDE_HOME_DIR}` (host) → `/home/claude` — persists Claude's home directory (config, credentials, history) across container restarts.

Configuration — container names, the proxy port, host UID/GID, and bind-mount paths — lives in `.env` and is read by `compose.yaml`.

## Usage

```sh
# build and start both containers, launches `claude` in the sandbox
podman compose up --build

# subsequent runs, no rebuild needed
podman compose up

# get a shell in the sandbox instead of launching Claude directly
podman compose run claude bash

# tear down
podman compose down
```

`WORK_DIR` and `CLAUDE_HOME_DIR` (set in `.env`, default `./work` and `./claude-home`) are created on the host and bind-mounted in. Point `WORK_DIR` at the project you want Claude to work on.

## Verifying the fence

After starting the stack, confirm from inside the `claude` container that:

- Requests to `anthropic.com`/`claude.ai` succeed (through the proxy).
- A request to any other domain (e.g. `curl https://example.com`) fails — Squid's `http_access deny all` should reject it.

## Files

| File | Purpose |
| --- | --- |
| `compose-claude.yaml` | Defines the `claude` and `proxy` services and the `isolated`/`egress` networks |
| `Dockerfile.claude` | Builds the sandbox image Claude Code runs in |
| `Dockerfile.proxy` | Builds the Squid proxy image |
| `entrypoint.sh` | Seeds `$HOME` from `/etc/skel` without clobbering existing files, then execs the container command |
| `squid-claude.conf` | Proxy allowlist — only `.claude.ai`, `.claude.com`, `.anthropic.com` over HTTPS |
| `env.claude-sample` | a sample file for `.env` defining Container names, proxy port, host UID/GID, bind-mount paths |

## Notes

- Network isolation is the entire point of this setup. When editing `squid.conf` or `compose.yaml`, preserve the property that `isolated` has no route to the host/outside world and that `proxy` is the only service on `egress`. Don't widen `allowed_domains` without good reason.
- `entrypoint.sh` uses `cp -a -n` (never overwrite) so that re-running the container doesn't reset an existing `$HOME` bind-mounted from `${CLAUDE_HOME_DIR}`.
