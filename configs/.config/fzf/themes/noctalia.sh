fzf_theme_opts="\
--color=bg+:#41474d
--color=bg:#111416
--color=spinner:#e2e2e5
--color=hl:#ffb4ab
--color=fg:#e2e2e5
--color=header:#ffb4ab
--color=info:#9dccf1
--color=pointer:#e2e2e5
--color=marker:#c1c7ce
--color=fg+:#e2e2e5
--color=prompt:#9dccf1
--color=hl+:#ffb4ab
--color=selected-bg:#41474d
--color=border:#41474d
--color=label:#e2e2e5"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
