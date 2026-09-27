fzf_theme_opts="\
--color=bg+:#26272c
--color=bg:#1d1d21
--color=spinner:#f2f2f3
--color=hl:#fd4663
--color=fg:#f2f2f3
--color=header:#fd4663
--color=info:#8b96c1
--color=pointer:#f2f2f3
--color=marker:#afb0b6
--color=fg+:#f2f2f3
--color=prompt:#8b96c1
--color=hl+:#fd4663
--color=selected-bg:#26272c
--color=border:#26272c
--color=label:#f2f2f3"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
