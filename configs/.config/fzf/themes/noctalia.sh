fzf_theme_opts="\
--color=bg+:#404848
--color=bg:#111414
--color=spinner:#e2e3e2
--color=hl:#ffb4ab
--color=fg:#e2e3e2
--color=header:#ffb4ab
--color=info:#9fcfcf
--color=pointer:#e2e3e2
--color=marker:#c0c8c8
--color=fg+:#e2e3e2
--color=prompt:#9fcfcf
--color=hl+:#ffb4ab
--color=selected-bg:#404848
--color=border:#404848
--color=label:#e2e3e2"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
