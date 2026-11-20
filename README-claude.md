# Claude Code Sandbox

A Podman Compose setup that runs [Claude Code](https://claude.ai/code) in a network-isolated sandbox. Claude can reach only the HTTPS destinations explicitly allowed by Squid; the working tree and Claude home are bind-mounted from the host.

## Architecture and files

- `compose-claude.yaml` runs the non-root `claude` service on an internal-only network alongside Squid. Squid alone also joins the egress network.
- `Dockerfile.claude` installs Claude Code and the shell tools, creates a user mapped to the configured host UID/GID, and explicitly clones the [Ponytail plugin](https://github.com/DietrichGebert/ponytail) into `/opt/ponytail`.
- `entrypoint-claude.sh` seeds the mounted home directory without overwriting existing files, then registers and installs the local Ponytail marketplace/plugin before starting Claude Code.
- `squid-claude.conf` allows HTTPS CONNECT to `.claude.ai`, `.claude.com`, and `.anthropic.com`; all other destinations are denied.
- `env.claude` defines container names, the proxy port, host and Squid UID/GID, bind-mount paths, and the host log directory.
- `./work` is mounted at `/work`; `./claude-home` is mounted at `/home/claude` to persist Claude configuration and credentials. Squid logs are persisted under `./claude-squid-logs`.

The coding-agent container is attached only to the internal network, which has no external route. The proxy is the only service attached to the egress network. Preserve this topology when changing the compose file.

## Setup and usage

1. Review `env.claude`. Set `WORK_DIR` to the host project directory Claude should work on.
2. Start an interactive session:

   ```sh
   podman-compose -p claude --env-file env.claude -f compose-claude.yaml run --build --rm claude
   ```

3. Authenticate Claude Code as needed. Its home directory persists under `./claude-home`.

The `run-claude` alias in `aliases` wraps the same command. Use the distinct `-p claude` project name and `env.claude` file so this stack does not collide with the OpenCode and Mammouth stacks.

To start the services in the background instead, use `up --build -d`; attach or exec into the `claude` service/container as needed. Tear down the stack with:

```sh
podman-compose -p claude --env-file env.claude -f compose-claude.yaml down
```

## Proxy logs and allowlist

Watch allowed and denied requests in the host-mounted Squid log directory:

```sh
tail -f ./claude-squid-logs/access.log
```

If Claude needs another destination, inspect `TCP_DENIED` entries and add only the required hostname(s) to `allowed_domains` in `squid-claude.conf`. Recreate the proxy after changing the config. Do not broaden the allowlist without evidence that it is needed.

## Verify the fence

From the running `claude` container, verify that an allowed Claude/Anthropic host can be reached through the proxy and that an unrelated host is denied. Check `./claude-squid-logs/access.log` for the corresponding allowed and denied requests.

## Ponytail plugin

Ponytail is intentionally included: the Docker build clones it into `/opt/ponytail`, and `entrypoint-claude.sh` registers its local marketplace and installs the plugin on startup. Keep both steps if adapting the Claude image or entrypoint.
