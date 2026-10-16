fzf_theme_opts="\
--color=bg+:#474747
--color=bg:#131313
--color=spinner:#e2e2e2
--color=hl:#ffb4ab
--color=fg:#e2e2e2
--color=header:#ffb4ab
--color=info:#a3d578
--color=pointer:#e2e2e2
--color=marker:#c6c6c6
--color=fg+:#e2e2e2
--color=prompt:#a3d578
--color=hl+:#ffb4ab
--color=selected-bg:#474747
--color=border:#474747
--color=label:#e2e2e2"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
