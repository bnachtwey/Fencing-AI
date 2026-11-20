# OpenCode Sandbox

A podman-compose setup that runs [OpenCode](https://opencode.ai) inside a network-isolated sandbox, so the agent can only reach a short allowlist of domains and nothing else on the network and internet.
By adapting `squid-opencode.conf`, additional access is possible (see [Allowing more domains](#allowing-more-domains)).

## Why

OpenCode can run arbitrary shell commands on your behalf. This setup fences its egress traffic through a Squid proxy that only allows HTTPS CONNECT to the domains listed in `squid-opencode.conf` (by default `.models.dev` and `.opencode.ai`, plus whatever LLM provider you add). The container running OpenCode has no other route to the host or the outside world, so even a compromised or misbehaving session can't exfiltrate data or reach arbitrary hosts.

## Architecture

Two services, two Podman networks, defined in `compose-opencode.yaml`:

- **`opencode`** (`Dockerfile.opencode`) — Alpine with Node, npm, git, ripgrep, and `opencode-ai` installed globally. Runs as a non-root `opencode` user (uid/gid from `HOST_UID`/`HOST_GID`, mapped via `userns_mode: keep-id`). Its entrypoint (`entrypoint-opencode.sh`) seeds `$HOME` from `/etc/skel` (a starter `.bashrc`, `.bash_profile`, and empty `.config/opencode` dir) without overwriting anything already there, then execs the real command (`opencode` by default).
- **`proxy`** (`Dockerfile.proxy`) — Alpine with Squid, configured by `squid-opencode.conf` to allow CONNECT only to the allowed domains and deny everything else. Every request, allowed or denied, is logged to `${SQUIDLOG}/access.log` (errors/debug to `${SQUIDLOG}/cache.log`), bind-mounted to `${SQUIDLOG_HOST}` on the host.
- **`isolated` network** — internal-only, no route to the host or the internet. Connects `opencode` and `proxy`. This is the only network the `opencode` container is on.
- **`egress` network** — connects only `proxy` to the outside world. This is the sole path any traffic from `opencode` can take to leave the sandbox, and only through Squid's allowlist.
- **Volumes**:
  - `${WORK_DIR}` (host) → `/work` in the `opencode` container — the working directory OpenCode operates in.
  - `${OPENCODE_HOME_DIR}` (host) → `/home/opencode` — persists OpenCode's home directory (config in `~/.config/opencode`, credentials and sessions in `~/.local/share/opencode`, plus state and cache) across container restarts.

Configuration — container names, the proxy port, host UID/GID, bind-mount paths, and the Squid log directory — lives in `env.opencode` and is passed to compose with `--env-file`.

The compose project is always started with `-p opencode` so that it doesn't collide with the Claude stack (which also has a `proxy` service and `isolated`/`egress` networks) when both live in the same directory.

### Environment inside the container

Set in `compose-opencode.yaml`:

| Variable                                                    | Purpose                                                                                         |
| :---------------------------------------------------------- | :---------------------------------------------------------------------------------------------- |
| `HTTPS_PROXY`, `HTTP_PROXY`, `https_proxy`, `http_proxy`    | Send all outbound traffic through Squid. Both cases are set because tools disagree on which one they read (e.g. curl ignores uppercase `HTTP_PROXY`). |
| `NO_PROXY=localhost,127.0.0.1,::1`                          | Keeps OpenCode's own local TUI/server traffic off the proxy (Squid would deny it).              |
| `OPENCODE_DISABLE_AUTOUPDATE=true`                          | No self-update attempts (they would be blocked anyway).                                         |
| `OPENCODE_DISABLE_LSP_DOWNLOAD=true`                        | No automatic LSP server downloads (blocked anyway).                                             |
| `SQUIDLOG`                                                  | Directory inside the proxy container where Squid writes `access.log` and `cache.log` (default `/squidlog`). |
| `SQUIDLOG_HOST`                                             | Host directory bind-mounted onto `${SQUIDLOG}` so proxy logs are readable on the host (default `./squid-logs`). |

## Setup

Adapt your settings in env file `env-opencode`.

Then add your LLM provider's domain to `squid-opencode.conf` (see below). Without it, OpenCode starts but cannot reach any model.

### Credentials

Either authenticate once inside the sandbox:

```bash
opencode auth login
```

The result is stored in `~/.local/share/opencode/` and persists through the `${OPENCODE_HOME_DIR}` bind mount. Or pass an API key via `environment:` in `compose-opencode.yaml` (e.g. `ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}`).

## Usage

```bash
# build and start both containers, launches `opencode` in the sandbox in the foreground with immediately killing the pod on leave
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml run --rm opencode

# build and start both containers, launches `opencode` in the sandbox in the background
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml up --build -d

# attach to the running OpenCode session (the main process, `opencode`, with its TTY)
podman attach ${OPENCODE_CONTAINER_NAME}
# detach WITHOUT stopping it: Ctrl-p, Ctrl-q

# open an additional shell in the running container (separate process)
podman exec -it ${OPENCODE_CONTAINER_NAME} bash

# same thing via compose, using the service name
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml exec opencode bash

# watch OpenCode logs / check state
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml logs -f opencode
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml ps

# watch the proxy access log (every request, allowed and denied)
tail -f "${SQUIDLOG_HOST:-./squid-logs}/access.log"

# tear down (at least squid will survive even if stack was started with --rm)
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml down
```

`${OPENCODE_CONTAINER_NAME}` is the value from `env.opencode` (default `opencode-sandbox`); the shell does not expand it unless you export it, so substitute the name when running the `podman attach`/`podman exec` lines by hand.

`WORK_DIR` and `OPENCODE_HOME_DIR` (set in `env.opencode`, default `./work` and `./opencode-home`) are created on the host and bind-mounted in. Point `WORK_DIR` at the project you want OpenCode to work on.

### Pinning the OpenCode version

`Dockerfile.opencode` takes an `OPENCODE_VERSION` build arg (default `latest`). To pin it, add it under `build.args` in `compose-opencode.yaml`, e.g. `OPENCODE_VERSION: "1.2.3"`, and rebuild with `up --build`.

## Allowing more domains

The allowlist is the `allowed_domains` ACL in `squid-opencode.conf`. A leading dot also matches all subdomains:

```bash
acl allowed_domains dstdomain .models.dev .opencode.ai .anthropic.com
```

Common additions are your provider's API domain (e.g. `.anthropic.com`, `.openai.com`, `.openrouter.ai`). A good way to find what is missing is to tail the proxy access log (`tail -f "${SQUIDLOG_HOST:-./squid-logs}/access.log"`) and look for `TCP_DENIED` lines. After editing the file, restart the proxy (`restart proxy`, or `down` and `up`).

- `.models.dev` — OpenCode fetches its model list from here; if blocked it falls back to a bundled snapshot.
- `.opencode.ai` — OpenCode's own services (e.g. OpenCode Zen, auth, sharing).

## Verifying the fence

After starting the stack, confirm from inside the `opencode` container that:

- Requests to an allowed domain (e.g. `curl -I https://models.dev`) succeed (through the proxy).
- A request to any other domain (e.g. `curl -I https://example.com`) fails — Squid's `http_access deny all` should reject it, and a `TCP_DENIED` line shows up in `${SQUIDLOG:-/squidlog}/access.log`.

`curl` is not part of the Alpine base image; add it to the `apk add` line in `Dockerfile.opencode` if you want to run these checks.

## Files

| File                     | Purpose                                                                                                |
| :----------------------- | :----------------------------------------------------------------------------------------------------- |
| `compose-opencode.yaml`  | Defines the `opencode` and `proxy` services and the `isolated`/`egress` networks                       |
| `Dockerfile.opencode`    | Builds the sandbox image OpenCode runs in                                                              |
| `Dockerfile.proxy`       | Builds the Squid proxy image                                                                           |
| `entrypoint-opencode.sh` | Seeds `$HOME` from `/etc/skel` without clobbering existing files, then execs the container command     |
| `entrypoint-proxy.sh`    | Generates `squid.conf` from template (substituting `SQUIDLOG`), fixes log dir ownership, then runs Squid |
| `squid-opencode.conf`    | Proxy allowlist template — HTTPS CONNECT only, to the listed domains                                |
| `env.opencode`           | Sample for `env.opencode` defining container names, proxy port, host UID/GID, bind-mount paths         |

## Notes

- Network isolation is the entire point of this setup. When editing `squid-opencode.conf` or `compose-opencode.yaml`, preserve the property that `isolated` has no route to the host/outside world and that `proxy` is the only service on `egress`. Don't widen `allowed_domains` without good reason.
- `entrypoint-opencode.sh` uses `cp -a -n` (never overwrite) so that re-running the container doesn't reset an existing `$HOME` bind-mounted from `${OPENCODE_HOME_DIR}`.
- Always pass `-p opencode --env-file env.opencode`: compose only auto-reads a file called `.env`, and the project name keeps this stack separate from the Claude one.
