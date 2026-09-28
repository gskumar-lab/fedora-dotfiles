fzf_theme_opts="\
--color=bg+:#30212c
--color=bg:#231a20
--color=spinner:#f3f2f2
--color=hl:#fd4663
--color=fg:#f3f2f2
--color=header:#fd4663
--color=info:#c18bb0
--color=pointer:#f3f2f2
--color=marker:#b6afb4
--color=fg+:#f3f2f2
--color=prompt:#c18bb0
--color=hl+:#fd4663
--color=selected-bg:#30212c
--color=border:#30212c
--color=label:#f3f2f2"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS
}$fzf_theme_opts"
