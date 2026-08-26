# agent-sandbox shell config.
# Baked into the image from agent-home/ (see the Dockerfile). This file
# overwrites the oh-my-zsh installer's template .zshrc at build time, so it
# is the single source of truth for shell configuration.

# mise and other per-user installs land here.
export PATH="$HOME/.local/bin:$PATH"

# oh-my-zsh with powerlevel10k (both installed by the Dockerfile).
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git z)
source "$ZSH/oh-my-zsh.sh"