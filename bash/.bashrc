# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User PATH
export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.cargo/bin:$PATH"
export TODO_DIR="$HOME"

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

#aliases
alias c="bat -p"
alias syu="sudo dnf upgrade --refresh"
alias mkdir="mkdir -pv"
alias x="chmod +x"
#alias rmdir="rmdir -v"

#Bulletproof History
#By default, bash history is too short and saves typos and duplicate commands. These settings ensure you never lose a complex command again.

# Append to the history file, don't overwrite it
shopt -s histappend

# Save a massive amount of history
HISTSIZE=100000
HISTFILESIZE=100000

# Ignore duplicate commands and commands that start with a space
HISTCONTROL=ignoreboth:erasedups

# Update the history file immediately after every command, 
# rather than waiting for the terminal session to close
#PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"


#Shell Options (Quality of Life)
#Bash has built-in features that are disabled by default. Turning these on makes navigating the file system much smoother.

# Fix minor spelling errors in directory names when using 'cd'
shopt -s cdspell

# Change into a directory by just typing its name (no 'cd' required)
shopt -s autocd

#Essential Aliases
#Aliases are shortcuts for longer commands. You can adjust these to fit your exact workflow, but these are the universal standard.

# Colorize output for core utilities
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Better list commands
alias ll='ls -lAh'      # Long format, human-readable sizes, includes hidden files
alias la='ls -A'        # Just hidden files
alias l='ls -CF'        # Column format

# Quick navigation up the directory tree
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Safety nets (prompts before overwriting or deleting files)
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Quick text editor access (change to nvim, code, or vim)
export EDITOR="vim"
alias e="$EDITOR"

#Time-Saving Functions
#While aliases are great for static commands, functions allow you to pass arguments. These act like mini-scripts.

#Create and Enter (mkcd)
#Instead of typing mkdir new_folder and then cd new_folder, this does both in one step.

mkcd() {
    mkdir -p "$1" && cd "$1"
}

#Extract Anything (extract)
#Never memorize tar flags again. Just type extract archive.tar.gz or extract file.zip, and it handles the rest based on the file extension.

extract() {
    if [[ $# -ne 1 ]]; then
        echo "Usage: extract <archive>"
        return 1
    fi

    if [[ ! -f "$1" ]]; then
        echo "Not a file: $1"
        return 1
    fi

    case "$1" in
        *.tar.bz2) tar xvjf "$1" ;;
        *.tar.gz)  tar xvzf "$1" ;;
        *.bz2)     bunzip2 "$1" ;;
        *.rar)     unrar x "$1" ;;
        *.gz)      gunzip "$1" ;;
        *.tar)     tar xvf "$1" ;;
        *.tbz2)    tar xvjf "$1" ;;
        *.tgz)     tar xvzf "$1" ;;
        *.zip)     unzip "$1" ;;
        *.Z)       uncompress "$1" ;;
        *.7z)      7z x "$1" ;;
        *)         echo "Unknown archive type: $1"; return 1 ;;
    esac
}


#starship init
eval "$(starship init bash)"


eval "$(zoxide init --cmd cd bash)"
