fzf_theme_opts="\
--color=bg+:#24262e
--color=bg:#1b1d22
--color=spinner:#f2f2f3
--color=hl:#fd4663
--color=fg:#f2f2f3
--color=header:#fd4663
--color=info:#8b98c1
--color=pointer:#f2f2f3
--color=marker:#afb1b6
--color=fg+:#f2f2f3
--color=prompt:#8b98c1
--color=hl+:#fd4663
--color=selected-bg:#24262e
--color=border:#24262e
--color=label:#f2f2f3"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
