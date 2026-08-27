# syntax=docker/dockerfile:1
#
# agent-sandbox — base image for an interactive dev VM.
#
# Built with Docker, but Docker is not the runtime. The image is exported with
# `docker save` and booted by smolvm as a persistent microVM:
#
#   docker build -t agent-sandbox .
#   docker save agent-sandbox -o agent-sandbox.tar
#   smolvm machine create --name agent-sandbox -s ./agent-sandbox.smolfile \
#       --image ./agent-sandbox.tar --net-backend virtio-net

FROM ubuntu:24.04

# The pre-installed agent harnesses (both installed by the per-user dev tools
# layer below) phone home:
#
#   opencode: an auto-update check against api.github.com, a model catalog
#             fetch from models.opencode.ai, and LSP server auto-downloads.
#   pi:       a version check and a model catalog refresh against pi.dev, an
#             npm-registry check for pi-package updates (plus auto-install of
#             missing configured packages), and install/update telemetry to
#             pi.dev/api/report-install. Independent of PI_OFFLINE, it also
#             adds provider attribution headers (X-OpenRouter-Title,
#             X-BILLING-INVOKE-ORIGIN, a Cloudflare User-Agent) to LLM API
#             requests unless telemetry is disabled.
#
# pi.dev and models.opencode.ai are not in the VM's egress allow-list, but two
# hosts pi reaches — api.github.com (helper binary downloads, via the
# github.com wildcard) and registry.npmjs.org (pi-package updates) — are, so
# without the flags those phone-homes would succeed in-VM. The flags make the
# guarantee explicit in the image itself, and env (unlike .zshrc) applies to
# non-login `smolvm machine exec` sessions too. The env form also cannot be
# overridden by a project-level config (opencode.json / .pi/settings.json),
# which wins over the global config below — the sandbox runs untrusted
# projects, so this matters. PI_OFFLINE disables all of pi's startup network
# operations; PI_TELEMETRY=0 additionally disables install telemetry and the
# attribution headers, the one pi behavior PI_OFFLINE does not cover.
# PATH adds the per-user tool directories (mise, pi, node) for *every* process
# in the image, including non-interactive `smolvm machine exec` sessions,
# which never read ~/.zshrc. (~/.zshrc exports them too, for interactive
# shells.)
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/home/agent/.local/bin:/home/agent/.local/share/mise/shims:/home/agent/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OPENCODE_DISABLE_AUTOUPDATE=true \
    OPENCODE_DISABLE_MODELS_FETCH=true \
    OPENCODE_DISABLE_LSP_DOWNLOAD=true \
    PI_OFFLINE=1 \
    PI_TELEMETRY=0

# ---------------------------------------------------------------------------
# Packages.
#
# policy-rc.d makes every service-start attempt during install a no-op. The
# docker.io postinst tries to start the daemon; there is no init system in a
# build layer, so without this it emits noise and can fail the build. Removed
# in the same layer so it has no effect at runtime.
#
# The BuildKit cache mounts persist apt's package and index caches on the
# build host across builds, so if this layer is invalidated it reinstalls
# from local .debs instead of re-downloading (requires buildx; see Taskfile).
#
# docker-buildx puts the buildx client inside the image, so the in-VM dockerd
# can also use `docker buildx build`.
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt/archives \
    --mount=type=cache,target=/var/lib/apt/lists \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
  && chmod 0755 /usr/sbin/policy-rc.d \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       docker-buildx \
       docker-compose-v2 \
      docker.io \
      fd-find \
      fzf \
      git \
      htop \
      ripgrep \
      sudo \
      vim \
      xsel \
      zsh \
  # The base image's dpkg config excludes /usr/share/doc/* to keep the image
  # small, which drops the zsh scripts the fzf package ships under
  # /usr/share/doc/fzf/examples/. The oh-my-zsh fzf plugin needs them because
  # the packaged fzf binary is built without the `fzf --zsh` script generator.
  # Re-unpack the package with the exclude lifted. The base image's Post-Invoke
  # hook removes downloads from the apt archive cache after every dpkg run, so
  # the .deb is fetched into the build directory and deleted afterward. The
  # trailing tests fail the build if either script is missing.
  && mv /etc/dpkg/dpkg.cfg.d/excludes /tmp/dpkg-excludes \
  && apt-get download fzf \
  && dpkg -i ./fzf_*.deb \
  && rm -f ./fzf_*.deb \
  && mv /tmp/dpkg-excludes /etc/dpkg/dpkg.cfg.d/excludes \
  && test -f /usr/share/doc/fzf/examples/completion.zsh \
  && test -f /usr/share/doc/fzf/examples/key-bindings.zsh \
  # Ubuntu's fd-find package installs the binary only as /usr/bin/fdfind, but
  # pi's find tool (and most users) invoke it as fd. The symlink lives in
  # /usr/local/bin, which dpkg does not manage.
  && ln -s /usr/bin/fdfind /usr/local/bin/fd \
  && test -x /usr/local/bin/fd \
  && rm -rf /var/lib/apt/lists/* /usr/sbin/policy-rc.d

# ---------------------------------------------------------------------------
# The agent user. Here we rename the default ubuntu user.
#
# The `docker` group already exists — the docker.io package creates it in its
# postinst — so agent can talk to the daemon socket without sudo.
# ---------------------------------------------------------------------------
RUN mkdir -p /home/ubuntu \
 && usermod -l agent -d /home/agent -m -s /usr/bin/zsh ubuntu \
 && groupmod -n agent ubuntu \
 && usermod -aG docker agent \
 && cp -rT /etc/skel /home/agent \
 && chown -R agent:agent /home/agent \
 && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-agent \
 && chmod 0440 /etc/sudoers.d/90-agent \
 && visudo -cf /etc/sudoers.d/90-agent

# Hack for changing guest non-root user's uid/gid to match host user's,
# so that mounts reflect and enforce the correct user/group ownership.
COPY fix-ownership /usr/local/bin/fix-ownership
RUN chmod 0755 /usr/local/bin/fix-ownership

# ---------------------------------------------------------------------------
# Brings up dockerd inside the guest. Must be run after every `machine start`:
#
#   smolvm machine exec --name agent-sandbox -- sudo start-dockerd
#
# sudo because exec lands as agent (see USER below); the mount and the daemon
# both need root.
#
# It re-applies the /storage/docker bind-mount, which does not survive a VM
# stop/start and which overlay2 requires. See the script for why.
# ---------------------------------------------------------------------------
COPY start-dockerd /usr/local/bin/start-dockerd
RUN chmod 0755 /usr/local/bin/start-dockerd

# ---------------------------------------------------------------------------
# Per-user dev tools (mise, oh-my-zsh, powerlevel10k, opencode, node, pi).
#
# Installed as agent rather than root so everything lives under /home/agent
# and is managed like dotfiles. This is a single stable layer: the image is
# never pushed, so extra layers cost nothing, and this layer only rebuilds
# when one of these install commands changes.
#
#   mise           -> ~/.local/bin/mise           (curl https://mise.run | sh)
#   oh-my-zsh      -> ~/.oh-my-zsh                (official installer, unattended)
#   powerlevel10k  -> ~/.oh-my-zsh/custom/themes  (git clone, per the OMZ docs)
#   opencode       -> ~/.opencode/bin/opencode    (curl https://opencode.ai/install | bash)
#   node           -> ~/.local/share/mise/shims   (mise use -g node@22; pi needs Node >= 22.19)
#   pi             -> ~/.local/bin/pi             (npm -g --ignore-scripts --prefix ~/.local)
#
# The oh-my-zsh installer writes a template .zshrc, but the agent-home/ COPY
# below overwrites it -- the version-controlled agent-home/.zshrc is the
# single source of truth for shell configuration: it sources oh-my-zsh,
# selects the powerlevel10k theme, and adds ~/.local/bin (mise, pi),
# ~/.local/share/mise/shims (node) and ~/.opencode/bin (opencode) to PATH.
# The opencode installer is told not to modify the shell rc
# (--no-modify-path) for the same reason.
#
# The phone-home behavior of opencode and pi is disabled in two places: the
# ENV block at the top of this file (covers every process, cannot be
# overridden by a project config) and the global configs baked in from
# agent-home/.config/opencode/opencode.json and
# agent-home/.pi/agent/settings.json (the user-visible knobs).
#
# The trailing checks fail the build if a download silently no-ops: `sh -c
# "$(curl ...)"` and `curl | sh` both exit 0 when curl itself fails.
# ---------------------------------------------------------------------------
USER agent
RUN curl -fsSL https://mise.run | sh \
  && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
  && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        /home/agent/.oh-my-zsh/custom/themes/powerlevel10k \
  && curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path \
  && mise use -g node@22 \
  && npm install -g --ignore-scripts --prefix /home/agent/.local @earendil-works/pi-coding-agent \
  && /home/agent/.local/bin/mise --version \
  && /home/agent/.local/share/mise/shims/node --version \
  && /home/agent/.opencode/bin/opencode --version \
  && /home/agent/.local/bin/pi --version \
  && test -f /home/agent/.oh-my-zsh/oh-my-zsh.sh \
  && test -f /home/agent/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme

# ---------------------------------------------------------------------------
# Home directory.
#
# The trailing slash on the source copies the *contents* of agent-home/, not
# the directory itself. Dotfiles and dotdirs are included. COPY preserves mode
# bits from the build context verbatim; --chown sets ownership recursively
# without touching them.
#
# This merges with the /etc/skel files useradd already placed there — where
# names collide, agent-home/ wins.
# ---------------------------------------------------------------------------
COPY --chown=agent:agent agent-home/ /home/agent/

# ---------------------------------------------------------------------------
# USER is what makes `smolvm machine shell` and `machine exec` land as agent
# rather than root. WORKDIR only sets the cwd of the long-running CMD process;
# where `shell`/`exec` sessions actually start is the machine's `workdir` (set
# in the Smolfile), resolved by smolvm at exec time.
#
# CMD keeps the machine alive: smolvm boots image-based machines as a
# container, so a command that exits would take the VM down with it. Nothing
# interactive belongs here — sessions arrive later via exec.
# ---------------------------------------------------------------------------
USER agent
WORKDIR /home/agent

CMD ["sleep", "infinity"]
