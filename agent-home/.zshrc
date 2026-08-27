# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# agent-sandbox shell config.
# Baked into the image from agent-home/ (see the Dockerfile). This file
# overwrites the oh-my-zsh installer's template .zshrc at build time, so it
# is the single source of truth for shell configuration.

# mise and other per-user installs land here.
export PATH="$HOME/.local/bin:$PATH"

# opencode (pre-installed by the Dockerfile; its --no-modify-path flag means
# the installer never touches this file).
export PATH="$HOME/.opencode/bin:$PATH"

# oh-my-zsh with powerlevel10k (both installed by the Dockerfile).
# The fzf plugin wires up fzf completion and Ctrl-R history search. Ubuntu's
# packaged fzf strips the `fzf --zsh` script generator, so the plugin uses the
# completion and key-binding files the fzf apt package ships under
# /usr/share/doc/fzf/examples/ instead.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git z fzf)
source "$ZSH/oh-my-zsh.sh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
