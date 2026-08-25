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

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# ---------------------------------------------------------------------------
# Packages.
#
# policy-rc.d makes every service-start attempt during install a no-op. The
# docker.io postinst tries to start the daemon; there is no init system in a
# build layer, so without this it emits noise and can fail the build. Removed
# in the same layer so it has no effect at runtime.
# ---------------------------------------------------------------------------
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
 && chmod 0755 /usr/sbin/policy-rc.d \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      docker-compose-v2 \
      docker.io \
      git \
      htop \
      ripgrep \
      sudo \
      vim \
      xsel \
      zsh \
 && rm -rf /var/lib/apt/lists/* /usr/sbin/policy-rc.d

# ---------------------------------------------------------------------------
# The agent user.
#
# The `docker` group already exists — the docker.io package creates it in its
# postinst — so agent can talk to the daemon socket without sudo.
# ---------------------------------------------------------------------------
RUN useradd --create-home --shell /usr/bin/zsh --groups docker agent \
 && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-agent \
 && chmod 0440 /etc/sudoers.d/90-agent \
 && visudo -cf /etc/sudoers.d/90-agent

# ---------------------------------------------------------------------------
# Brings up dockerd inside the guest. Must be run after every `machine start`:
#
#   smolvm machine exec --name agent-sandbox -- start-dockerd
#
# It re-applies the /storage/docker bind-mount, which does not survive a VM
# stop/start and which overlay2 requires. See the script for why.
# ---------------------------------------------------------------------------
COPY start-dockerd /usr/local/bin/start-dockerd
RUN chmod 0755 /usr/local/bin/start-dockerd

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
# rather than root. WORKDIR sets where those sessions start.
#
# CMD keeps the machine alive: smolvm boots image-based machines as a
# container, so a command that exits would take the VM down with it. Nothing
# interactive belongs here — sessions arrive later via exec.
# ---------------------------------------------------------------------------
USER agent
WORKDIR /home/agent

CMD ["sleep", "infinity"]
