fzf_theme_opts="\
--color=bg+:#46464d
--color=bg:#131315
--color=spinner:#e5e1e4
--color=hl:#ffb4ab
--color=fg:#e5e1e4
--color=header:#ffb4ab
--color=info:#c1c5e3
--color=pointer:#e5e1e4
--color=marker:#c7c5cd
--color=fg+:#e5e1e4
--color=prompt:#c1c5e3
--color=hl+:#ffb4ab
--color=selected-bg:#46464d
--color=border:#46464d
--color=label:#e5e1e4"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
