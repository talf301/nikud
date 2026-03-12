# My nikud fork

Personal fork of [quicknir/nikud](https://github.com/quicknir/nikud).

> **Note:** The upstream `setup.sh` uses micromamba/conda to install tools. On Mac, use Homebrew instead (see below).

## Mac Setup

### 1. Clone and wire up

```bash
git clone git@github.com:talf301/nikud.git ~/nikud
cd ~/nikud && git submodule update --init --recursive
ln -sf ~/nikud/zsh/zdotdir/my_env.zsh ~/.zshenv
```

### 2. Install tools via Homebrew

These are used by the zsh config and must be on PATH:

```bash
# Core tools used heavily in fzf/shell config
brew install eza        # ls replacement (alias ls, ll)
brew install bat        # cat replacement (alias cat, less)
brew install fd         # find replacement (used by fzf widgets)
brew install fzf        # fuzzy finder (ctrl-t, ctrl-j, ctrl-r, ctrl-s)
brew install ripgrep    # grep replacement (used by ctrl-s rg widget)

# Shell / prompt
brew install zsh
# powerlevel10k, fzf-tab, fast-syntax-highlighting, zsh-autosuggestions
# are bundled as submodules — no separate install needed

# Editor
brew install neovim

# Optional but nice
brew install lazygit    # TUI git client (lazygit function in my_rc.zsh)
brew install atuin      # shell history sync (disabled by default if not installed)
```

### 3. Create machine-specific config

Create `~/nikud/zsh/zdotdir/ignore_env.zsh` (gitignored) with your machine-specific paths:

```zsh
# Example ignore_env.zsh
eval "$(/opt/homebrew/bin/brew shellenv)"
path=("$HOME/.juliaup/bin" $path)
path=("$HOME/go/bin" $path)
path=("$HOME/.local/bin" "$HOME/bin" $path)
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
export PATH
```

### 4. Open a new terminal — done

To reconfigure the p10k prompt: `p10k configure`

---

# nikud
A dotfiles repo

### Highlights
 - Installs all needed executables contained inside the cloned repo directory
   - Includes zsh and tmux
   - fzf, fd-find, bat and eza which are used heavily in the integrated and improved fzf
    setup
   - and other useful tools like ripgrep, neovim, git-delta, etc. Easy to add tools.
   - also installs auto-completion for many of these executables
 - A zsh config that includes a lot of the most useful functionality without being
   overwhelming. Code is well organized and documented.
 - Includes several of the top of zsh plugins:
   - powerline10k
   - fzf-tab
   - fast-syntax-highlighting
   - autosuggestions
 - Includes a nice simple tmux setup - a nice powerline aesthetic with some informative segments including CPU and RAM usage, various small keybindings and improved defaults, and < 150 lines of code total
 - Some vscode/terminal integration niceties (particularly between vscode and tmux)
 - Includes a basic neovim setup - easy to extend further
 - config of other applications handled via XDG_CONFIG_HOME - no bare repo, no symlinks
 - and some other small things I can't remember


### Installation
Clone the repo recursively (anywhere), and from the cloned directory
run `./setup.sh`.

### Uninstallation
To stop using the dotfiles repo, just delete the symlink at `~/.zshenv`. If desired, the
old zshenv can be restored - it's backed up to `~/.zshenv.bak_<number>`. The dotfiles repo
folder can then be deleted - this removes all traces of installation, including executables.

### Is nikud a framework?
No. I'm not trying to make this some kind of general purpose solution that people can change
a handful of environment variables or config file, to suit their needs (a la OMZ, prezto,
etc). It's my personal dotfiles that I've taken a bit of extra time to document and organize,
that I think will be useful for other folks. You should fork it and change what you want!

