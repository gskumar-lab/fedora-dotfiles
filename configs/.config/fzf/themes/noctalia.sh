fzf_theme_opts="\
--color=bg+:#45474d
--color=bg:#131315
--color=spinner:#e4e2e4
--color=hl:#ffb4ab
--color=fg:#e4e2e4
--color=header:#ffb4ab
--color=info:#bac7e2
--color=pointer:#e4e2e4
--color=marker:#c5c6cd
--color=fg+:#e4e2e4
--color=prompt:#bac7e2
--color=hl+:#ffb4ab
--color=selected-bg:#45474d
--color=border:#45474d
--color=label:#e4e2e4"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
