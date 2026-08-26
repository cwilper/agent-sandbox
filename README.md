# agent-sandbox

A microVM sandbox for running untrusted code and coding agents, built on
[SmolVM](https://smolmachines.com/) from Smol Machines. It isolates agents from the host by limiting their disk and network
access to a single mounted workspace and an egress allow-list, while still
giving them real power inside the VM: passwordless `sudo` and a working
Docker daemon for building and running containers.

## Requirements

- [Docker](https://github.com/docker)
- [task](https://taskfile.dev)
- [SmolVM](https://smolmachines.com/)

Tested with macOS and Ubuntu as the host.

## Quick start

```sh
task create   # build the image and create the VM (deps on build)
task start    # boot the VM and start dockerd inside it
task shell    # open a shell inside as the agent user
```

The guest is Ubuntu 24.04 with a `agent` user (zsh, mise, docker, git, ripgrep,
...). `agent` has passwordless sudo and is in the `docker` group. Your host
workspace is mounted at `~/Work` in the guest, and the guest's Docker socket is
exposed to the host over vsock — smolvm prints the path on start, e.g.
`DOCKER_HOST=unix://<vm-data-dir>/docker.sock docker ps`.

## Taskfile targets

| Target      | What it does                                                        |
| ----------- | ------------------------------------------------------------------- |
| `build`     | Build the Docker image and export it to `agent-sandbox.tar`         |
| `create`    | Create the VM from the tarball, configured by the `Smolfile` (deps on `build`) |
| `start`     | Start the VM and bring up dockerd inside it (required after every boot) |
| `stop`      | Stop the VM                                                         |
| `shell`     | Open an interactive zsh login shell in the VM as `agent`            |
| `delete`    | Stop and delete the VM                                              |
| `clean`     | Remove the tarball and packed artifacts                             |
| `nuke`      | Delete the VM, clean artifacts, and remove the Docker image (best-effort) |

Note: the `/storage/docker` bind-mount that dockerd needs does not survive
stop/start, so `task start` always re-runs `sudo start-dockerd` (it is
idempotent).

## Limiting disk access

The guest sees no host files by default: its filesystem is the image plus its
own internal disks, and the only shared content is a single workspace mount
at `~/Work` in the guest. You control which host directory that is — `task
create` takes an absolute path via `HOST_WORKSPACE`:

```sh
task create HOST_WORKSPACE=/home/user/my-project
```

Defaults to `$HOME/Work` if unset.

## Limiting network access

Outbound traffic is filtered by the `[network]` section of the `Smolfile`,
which enforces two independent layers:

- **IP filter** (the real enforcement). At every `machine start`, `allow_hosts`
  entries are re-resolved to CIDRs and merged with `allow_cidrs`; every
  outbound packet is then checked by destination IP (CIDR membership). No
  reverse DNS is ever used to identify a destination.
- **DNS filter**. Guest DNS queries are proxied to the host; names not in
  `allow_hosts` (exact match plus wildcard subdomains) get NXDOMAIN. This
  limits name discovery, but the IP layer is what actually blocks traffic.

Notes:

- Bare IP literals work in `allow_hosts` (IPv4 → `/32`, IPv6 → `/128`), but
  `allow_cidrs` is the intended place for stable IP pins and ranges — it is
  not re-resolved and takes effect as written.
- No port filtering: all ports to an allowed IP are allowed.
- Resolution happens once at start, so a service that rotates IPs may need a
  re-`task start`. If all names fail to resolve, the policy fails closed
  (deny-all except the DNS endpoint), not open.
- Direct connections to a raw IP outside the resolved set are blocked, but
  any traffic to an allowed IP passes regardless of the hostname it is "for"
  (shared CDN IPs, etc.).
- You must include registry hosts in the list or `docker pull` will fail.
  Comment the whole `[network]` table out for unrestricted egress.