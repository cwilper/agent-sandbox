# Proposal for smolvm: per-mount uid/gid mapping for host volume mounts

This is a proposed feature for the
[smolmachines/smolvm](https://github.com/smolmachines/smolvm) project.

**Status:** draft for expert review
**Scope:** `smolvm` CLI/agent + the project's `libkrun` fork (virtiofs device)
**Platforms:** macOS (primary), Linux, Windows — one design, all three

## Feature Summary

Add an optional per-volume ownership mapping to host volume mounts:

```
-v HOST:GUEST[:OPTS]
OPTS:  [ro|rw] [,uid=<host_id>:<guest_id>] [,gid=<host_id>:<guest_id>]

# example — host user 502:20 (macOS) presenting a share as guest user 1000:1000
smolvm machine create -n dev -v ~/src:/app:uid=502:1000,gid=20:20
```

Files on the mounted share are presented to the guest with the mapped uid/gid
when they match the host id; everything else passes through unchanged. Guest
writes and chowns work normally inside the mapped range; the mapping is
invisible to the host. Unmapped mounts behave exactly as they do today.

## Problem and motivation

Host volumes are currently served with **pass-through ownership**: the guest
sees the raw host uid/gid from the host `stat()` result. smolvm's default
guest user is `1000:1000`; a typical macOS host user is `502:20` (staff). A
share mounted from such a host is therefore owned by an unknown user inside
the guest, and guest tools cannot create, edit, or delete files on it without
escalating to root.

There is no supported way to fix this today. The available workarounds are all
inferior:

- **Change ownership on the host** — rewrites the host's metadata; not
  acceptable for shared or managed directories.
- **Change the guest user to the host's ids (502:20)** — requires a custom or
  patched guest image, bakes one host's ids into every guest using it (not
  portable across hosts/CI), and requires `chown -R` of pre-existing image
  content.
- **Run guest workloads as root** — defeats the point of an isolated
  non-root user and is a standing security liability.
- **`cp` into guest-local storage** — breaks the live-sync use case that
  volumes exist for.

The request is to name the mapping at the mount: the same capability container
runtimes expose (`docker --mount ... ,uid=,gid=`, podman volume options,
Linux idmapped mounts), implemented for microVMs.

Value: first-class, portable support for the "share a host directory with a
non-root guest user" workflow across macOS (the headline gap), Linux, and
Windows, without touching host files, guest images, or workload users.

## Current state: why it doesn't work today

Ownership flows through three layers, and none of them has a mapping concept:

1. **Mount spec.** `HostMount { source, target, read_only }`
   (`src/data/storage.rs`); the spec grammar is `HOST:GUEST[:ro|:rw]`, parsed
   right-anchored by `HostMount::parse`. No other options exist.
2. **Hypervisor (libkrun).** Volumes are virtiofs devices created via
   `krun_add_virtiofs3(ctx, tag, path, shm_size, read_only)` — no id-mapping
   parameter. The C API has evolved in place (`krun_add_virtiofs` → `...2`
   adding `shm_size` → `...3` adding `read_only`), so a `...4` extension is
   the established pattern; smolvm resolves these symbols dynamically
   (`load_optional_sym!` in `src/agent/krun.rs`), so a newer symbol degrades
   gracefully against older libraries.
3. **Guest agent.** Mounts via `mount -t virtiofs <tag> <staging> -o dax,sync`
   then a bind into the rootfs (`crates/smolvm-agent/src/storage.rs`,
   `setup_volume_mounts`). A virtiofs guest mount has no ownership-translation
   option either — which is fine, because the right place to translate is the
   server, not the client.

A related mechanism already exists in smolvm — idmapped bind mounts
(`make_idmap_userns` / `setup_pack_idmap_mount`, `src/process.rs`) — but it is
host-kernel-based (Linux-only, root-only, kernel ≥ 5.12) and used solely for
the internal shared pack-layer store. It is **not** a viable path for user
volumes on macOS and would not generalize; the mapping belongs in the VMM's
FUSE server instead.

## Why it is feasible

The central insight: **the virtiofs FUSE server runs in user space, inside the
VMM process, on every platform.** It is not a host-kernel feature, so none of
the usual cross-platform obstacles apply — no kernel support, no root, no
macOS-vs-Linux asymmetry. Ownership is purely what the server reports in FUSE
`getattr`/`readdir` replies, and it is pure userspace id translation to
rewrite those values before sending them.

This is also where the project already invests: smolvm does not use upstream
libkrun. It pins **patched forks** of `libkrun`/`libkrunfw` as git submodules
(`smol-machines/libkrun`, fork of `libkrun/libkrun`), builds them from source
per platform, and has previously patched exactly this virtiofs code (the fork
carries virtiofs changes upstream never had). The virtiofs implementation in
the fork is a clean, layered structure:

- a shared FUSE dispatch server and a `FileSystem` trait with a per-request
  `Context { uid, gid, pid }` (the guest's identity, taken from the FUSE
  request header),
- a shared decorator pattern (`AugmentFs<T>`) for composing filesystem
  behavior,
- one small per-OS passthrough backend (linux/macos/windows) that does the
  actual `stat`/`open`/`write` calls.

The mapping plugs into the existing seams at a single choke point per backend:
the attribute-fill path (where the host `stat` result becomes the `Entry`
sent to the guest) and the software permission checks that compare the
guest's request uid against the host file owner (applied when the VMM is
unprivileged). Guest chown is handled by translating the requested id back
through the inverse mapping before the host `chown` — and can only produce a
host id the VMM was already able to stat/write, so it introduces no new host
privilege.

## Approach

Two coordinated changes: the libkrun fork (capability) and smolvm
(plumbing + user-facing surface).

### 1. libkrun fork: per-mount idmap on the virtiofs device

- New C API, following the established versioning:

  ```c
  int32_t krun_add_virtiofs4(uint32_t ctx_id, const char *tag, const char *path,
                             uint64_t shm_size, bool read_only,
                             uint32_t host_uid, uint32_t guest_uid,  /* UINT32_MAX = no map */
                             uint32_t host_gid, uint32_t guest_gid);
  ```

- Store the map per mount on the `Fs` device (alongside `read_only`), and
  apply it in the passthrough backends at:
  - **attribute presentation** — `st.st_uid/st.st_gid` are rewritten to the
    guest id when they equal the host id, in the entry-fill paths (getattr,
    readdir);
  - **permission checks** — the guest request uid in `Context` is translated
    back to the host id before the owner/permission comparison;
  - **setattr/chown** — inverse translation, so a guest chown to the mapped
    guest id becomes a host chown to the host id.
- Implementation choice: either apply the translation directly in each of the
  three passthrough backends (small, local), or as a shared `IdmapFs<T>`
  decorator in the style of the existing `AugmentFs` (more DRY; must also
  mediate the permission checks). Decide during implementation; the decorator
  is the architecturally cleaner option.

### 2. smolvm: one grammar, one parser, one data model

- **Spec syntax** (CLI `-v`, `[dev].volumes`, `machine update --volume`, and
  the HTTP API — all already funnel through `HostMount::parse`, so one change
  covers every surface):

  ```
  HOST:GUEST[:OPTS]
  OPTS: [ro|rw] [,uid=<host>:<guest>] [,gid=<host>:<guest>]
  ```

  Parse rule: the trailing slot is the option list **iff** it strictly
  validates as OPTS (at most one `ro`/`rw`, at most one `uid=`, at most one
  `gid=`, u32 values); otherwise it is parsed as today (path). This keeps every
  existing spec — including Windows `C:\data:/data:ro` — parsing identically.
- **Data model:** `MountIdmap { uid: Option<(u32,u32)>, gid: Option<(u32,u32)> }`
  in `crates/smolvm-protocol` (host↔guest shared crate; the mount-tag format
  already lives there) with the shared `parse_mount_opts`. `HostMount` gains
  an `#[serde(default)] idmap` field, so existing machine records and
  `.smolmachine` artifacts deserialize unchanged.
- **Transport:** the agent's boot env `SMOLVM_MOUNT_i=tag:guest_path:ro|rw`
  extends its third slot with the same OPTS string; both ends call the shared
  parser, so the format cannot drift.
- **Call sites:** the three `krun_add_virtiofs3` call sites gain the mapping
  via `krun_add_virtiofs4` (resolved through the existing optional-symbol
  machinery). **Fail hard, not silent passthrough:** if the user requested a
  mapping and the bundled libkrun lacks `krun_add_virtiofs4`, the machine
  start errors with a clear message.

### 3. Semantics and scope

- **Single-entry map per id space** (one host uid → one guest uid, same for
  gid). Everything else passes through. Squash-style "present everything as
  one uid" is a one-line variant at the same choke point and can be added
  later if demanded.
- **Applies to** every user-declared mount on every volume-taking surface:
  `machine run/create/update`, `pack run -v`, Smolfile `[dev].volumes`, HTTP
  API.
- **Does not apply to** internal devices (root virtiofs, packed layers,
  Rosetta) — the mechanism is per-device in libkrun, but the config surface
  exposes it only for user mounts.
- `ro` + mapping compose freely (a read-only share presented with mapped
  ownership).
- DAX shared memory is unaffected: data pages bypass FUSE, but ownership
  metadata still flows through `getattr`, which is where the mapping lives.
- Security: guest access to the share remains bounded by the VMM process's
  host privileges, exactly as today; the mapping relabels ids and does not
  widen them.

## Risks / open questions

- **Three passthrough backends** share little code today; the mapping must be
  behaviorally identical on macOS, Linux, and Windows. Mitigation: shared
  parser in `smolvm-protocol`, one shared translation helper, and parity
  tests per platform (the repo already carries per-platform test coverage for
  volume mounts).
- **Parser ambiguity** is pre-existing (a guest path literally ending in
  `/ro` is already read as the read-only flag today). The strict-validate
  rule above preserves today's behavior and only *adds* recognition of the
  new tokens; it does not widen the ambiguity surface in practice.
- **Old libkrun** (stale bundle, third-party build): mitigated by the
  hard-fail rule above rather than silent degradation.
- **FUSE attribute cache**: the passthroughs honor `attr_timeout`; a mapping
  is per-mount and immutable for the device's lifetime, so caching cannot
  serve stale mappings.

## Verification plan

- Unit: `parse_mount_opts` / `HostMount::parse` table tests (legacy specs,
  Windows drive paths, invalid tokens, duplicate tokens).
- Integration (macOS first, then Linux; Windows as far as CI allows): create a
  machine with `-v dir:/app:uid=<hostuid>:1000,gid=<hostgid>:1000`; verify
  `ls -ln` shows 1000:1000, that the guest user can create/modify/delete files,
  that a guest chown to 1000 stays 1000 (and is a correct host chown on disk),
  that unmapped files keep their real host ids, and that `ro` + mapping works.
- Regression: existing un-mapped mount tests unchanged.

## Key references

| Layer | Location |
|---|---|
| Spec parsing / data model | `src/data/storage.rs` (`HostMount`, `_parse`) |
| Mount bindings | `src/cli/parsers.rs` (`mounts_to_virtiofs_bindings`) |
| Agent mount env / mount | `crates/smolvm-agent/src/storage.rs` (`SMOLVM_MOUNT_i`, `setup_volume_mounts`) |
| libkrun symbol loading | `src/agent/krun.rs` |
| `krun_add_virtiofs*` call sites | `src/vm/backend/libkrun.rs`, `src/agent/launcher.rs`, `src/agent/launcher_dynamic.rs` |
| Fork virtiofs server | `libkrun/src/devices/src/virtio/fs/{server,filesystem,augment_fs,device,worker}.rs` |
| Fork per-OS passthrough | `libkrun/src/devices/src/virtio/fs/{linux,macos,windows}/passthrough.rs` |
| Fork C API | `libkrun/include/libkrun.h` |
| Precedent: internal idmap mounts | `src/process.rs` (`make_idmap_userns`, `setup_pack_idmap_mount`) |