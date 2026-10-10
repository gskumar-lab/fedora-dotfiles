fzf_theme_opts="\
--color=bg+:#5e3f3a
--color=bg:#200f0c
--color=spinner:#fedbd5
--color=hl:#ffb4ab
--color=fg:#fedbd5
--color=header:#ffb4ab
--color=info:#ffb4a8
--color=pointer:#fedbd5
--color=marker:#e8bcb5
--color=fg+:#fedbd5
--color=prompt:#ffb4a8
--color=hl+:#ffb4ab
--color=selected-bg:#5e3f3a
--color=border:#5e3f3a
--color=label:#fedbd5"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
