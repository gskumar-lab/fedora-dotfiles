fzf_theme_opts="\
--color=bg+:#45464e
--color=bg:#131316
--color=spinner:#e4e2e5
--color=hl:#ffb4ab
--color=fg:#e4e2e5
--color=header:#ffb4ab
--color=info:#b9c5f1
--color=pointer:#e4e2e5
--color=marker:#c6c6cf
--color=fg+:#e4e2e5
--color=prompt:#b9c5f1
--color=hl+:#ffb4ab
--color=selected-bg:#45464e
--color=border:#45464e
--color=label:#e4e2e5"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
