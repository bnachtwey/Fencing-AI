# Mammouth Code Sandbox

A Podman Compose setup that runs [Mammouth Code](https://info.mammouth.ai/docs/mammouth-code) in an isolated container. Runtime network access is restricted to the Mammouth API via Squid; the working tree and Mammouth home are bind-mounted from the host.

## Architecture and files

- `compose-mammouth.yaml` runs the non-root `mammouth` service on an internal-only network alongside Squid. Squid alone also joins the egress network.
- `Dockerfile.mammouth` downloads a version-pinned Linux musl release binary, installs it as `/usr/local/bin/mammouth`, and creates a non-root user mapped to the host UID/GID.
- `squid-mammouth.conf` allows HTTPS CONNECT only to `api.mammouth.ai` by default. All other destinations are denied and logged.
- `env.mammouth` sets container names, paths, architecture, and the Mammouth Code release version.
- `./work` is mounted at `/work`; `./mammouth-home` is mounted at `/home/mammouth` to persist configuration, credentials, and sessions.

The container's only network is the internal network, so it cannot bypass the proxy. The proxy is the only service attached to the external egress network. Keep this topology intact when changing the compose file.

## Setup and usage

1. Review `env.mammouth`. Set `MAMMOUTH_ARCH` to `x64` (amd64 hosts) or `arm64` and choose the pinned `MAMMOUTH_VERSION`.
2. The default `WORK_DIR=./work` is shared with the OpenCode setup. Set it to another host directory if you want separate working files.
3. Start an interactive session with the `run-mammouth` shell alias (defined in `aliases`), or run directly:

   ```sh
   podman-compose -p mammouth --env-file env.mammouth -f compose-mammouth.yaml run --build --rm mammouth
   ```

4. On first run, authenticate Mammouth Code with your Mammouth API key when prompted. Its home directory persists under `./mammouth-home`.

To upgrade, change `MAMMOUTH_VERSION` in `env.mammouth` to a reviewed release and rebuild. The image is pinned; in-container self-update is not required and will not have access to arbitrary download hosts.

## Network allowlist

The default proxy policy allows `api.mammouth.ai`, the documented Mammouth API endpoint. If the client reports a network error, inspect `./mammouth-squid-logs/access.log` for `TCP_DENIED` requests. Add only the specific required hostname(s) to `allowed_domains` in `squid-mammouth.conf`; then recreate the proxy. Do not add broad domains such as all of `.mammouth.ai` without evidence that they are needed.

## Verify the fence

From the running Mammouth container, verify that the API host can be reached and an unrelated host is denied. Squid's access log should show the allowed request and the denied request. `curl` is not installed in the runtime image by default; temporarily add it to `Dockerfile.mammouth` if you need this check.

Always use the separate `-p mammouth` project name and `env.mammouth` file so this stack does not collide with the OpenCode stack.
