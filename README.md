# Fencing-AI

Podman Compose sandboxes for coding and CLI agents. Each agent runs as a non-root user with a host-mounted project directory and a network path restricted through its own Squid proxy allowlist.

The project currently supports **Claude Code**, **OpenCode**, and **Mammouth Code**. The three stacks share the same isolation pattern, but use separate compose projects, proxy containers, allowlists, home directories, and Squid logs.

## Security model and limitations

Each compose file defines two networks:

- The agent joins only `isolated`, an internal network with no external route.
- Its Squid proxy joins `isolated` and `egress`. The proxy is the agent's only intended outbound path and allows HTTPS CONNECT only to the hostnames in that agent's Squid config.

This restricts **runtime network egress**, not the agent's filesystem capabilities. The agent can read and modify everything under its mounted `WORK_DIR`, and it can access its mounted home directory. Choose those host paths accordingly; do not mount sensitive directories unnecessarily. These containers are not a replacement for reviewing agent actions or keeping backups.

Image builds are separate from runtime networking: package installation, fetching agent binaries, and Claude's Ponytail clone happen during image builds using the build host's network. The Squid runtime allowlist does not constrain build-time downloads.

## Shared layout

| Agent | Compose / env | Image | Squid allowlist | Host home | Host Squid logs |
| --- | --- | --- | --- | --- | --- |
| Claude Code | `compose-claude.yaml` / `env.claude` | `Dockerfile.claude` | `squid-claude.conf` | `./claude-home` | `./claude-squid-logs` |
| OpenCode | `compose-opencode.yaml` / `env.opencode` | `Dockerfile.opencode` | `squid-opencode.conf` | `./opencode-home` | `./opencode-squid-logs` |
| Mammouth Code | `compose-mammouth.yaml` / `env.mammouth` | `Dockerfile.mammouth` | `squid-mammouth.conf` | `./mammouth-home` | `./mammouth-squid-logs` |

Each env file sets its stack's container names, proxy port, UID/GID values, work/home/log bind mounts, and Squid's in-container log path. The defaults all mount `./work` at `/work`, so the agents share the same working tree. Set `WORK_DIR` separately in an env file if you want an agent to operate on a different checkout.

Every stack uses `PROXY_PORT=3128` internally. Since the stacks use separate Podman Compose projects and networks, they can coexist without publishing this port on the host. Use the matching project name and env file when invoking compose; otherwise containers and networks may collide or interpolate the wrong values.

## Quick start

Run commands from the repository directory. Build and start an interactive session with the corresponding command:

```sh
# Claude Code
podman-compose -p claude --env-file env.claude -f compose-claude.yaml run --build --rm claude

# OpenCode
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml run --build --rm opencode

# Mammouth Code
podman-compose -p mammouth --env-file env.mammouth -f compose-mammouth.yaml run --build --rm mammouth
```

The shell aliases in `aliases` provide `run-claude`, `run-opencode`, and `run-mammouth` shortcuts. Source that file in your shell if you want to use them.

The work directory and home directories are bind-mounted from the host. Set `WORK_DIR` and the relevant `*_HOME_DIR` in the selected env file before launching if the defaults are not suitable. Authenticate the agent inside its sandbox; its home mount preserves credentials and settings between runs.

To launch a stack in the background, add `up --build -d` instead of `run ...`. Use the same `-p`, `--env-file`, and `-f` values to inspect or stop it, for example:

```sh
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml logs -f opencode
podman-compose -p opencode --env-file env.opencode -f compose-opencode.yaml down
```

## Differences between the agents

### Claude Code

- Installs `@anthropic-ai/claude-code` from npm in `Dockerfile.claude`.
- The default Squid allowlist is `.claude.ai`, `.claude.com`, and `.anthropic.com`.
- **Ponytail is intentionally included:** the image clones `https://github.com/DietrichGebert/ponytail` into `/opt/ponytail`; `entrypoint-claude.sh` registers that local marketplace and installs the plugin on startup. Keep both the image clone and entrypoint registration if changing Claude's setup.
- Claude-specific environment settings include `USE_BUILTIN_RIPGREP=0` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

### OpenCode

- Installs `@opencode/cli` with npm in `Dockerfile.opencode`; `OPENCODE_VERSION` and `OPENCODE_CACHEBUST` are build arguments in `env.opencode`.
- Its default Squid allowlist includes `.models.dev` and `.opencode.ai`. Add the chosen LLM provider's domain to `squid-opencode.conf`; without it, model requests may be denied.
- Disables OpenCode auto-update and automatic LSP downloads via environment variables in `compose-opencode.yaml`.
- Authenticate with `opencode auth login` inside the container; config and credentials persist in `./opencode-home`.

### Mammouth Code

- Downloads the version-pinned Linux musl release binary in `Dockerfile.mammouth`; `MAMMOUTH_VERSION` and `MAMMOUTH_ARCH` (`x64` or `arm64`) are set in `env.mammouth`.
- Its default Squid allowlist is only `api.mammouth.ai`. Inspect denied requests before allowing any additional hostnames.
- Authenticate Mammouth Code with a Mammouth API key inside the container; configuration and credentials persist in `./mammouth-home`.
- Upgrade by changing `MAMMOUTH_VERSION` to a reviewed release and rebuilding the image.

## Proxy logs and allowlists

Each stack writes Squid's `access.log` and `cache.log` to its own host-mounted log directory. Follow access requests (including denied requests) with:

```sh
tail -f ./claude-squid-logs/access.log
tail -f ./opencode-squid-logs/access.log
tail -f ./mammouth-squid-logs/access.log
```

When a required request is blocked, find its `TCP_DENIED` line and add only the needed hostname to the corresponding `allowed_domains` ACL in `squid-claude.conf`, `squid-opencode.conf`, or `squid-mammouth.conf`. Then recreate/restart that stack's proxy so it loads the changed config. Avoid broad wildcard domains unless logs show they are necessary.

The configs allow HTTPS CONNECT on port 443 only. They do not inspect encrypted request paths or content; the allowlist is hostname-based.

## UID/GID and Podman

The agent containers run as non-root users with `HOST_UID`/`HOST_GID` mapped through `userns_mode: keep-id`, so files created in mounted project and home directories are usable by the host user. The Squid containers similarly use `SQUID_UID`/`SQUID_GID` from the env files so their bind-mounted log files are host-readable. Adjust these values for your host if needed.

The `:Z` suffix on bind mounts is for SELinux relabeling. Keep the `isolated` network internal and ensure the proxy is the only service attached to `egress` when editing compose files; that topology is central to the runtime network fence.
