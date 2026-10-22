set -l fzf_theme_opts "\
--color=bg+:#474747
--color=bg:#131313
--color=spinner:#e2e2e2
--color=hl:#ffb4ab
--color=fg:#e2e2e2
--color=header:#ffb4ab
--color=info:#4cdadb
--color=pointer:#e2e2e2
--color=marker:#c6c6c6
--color=fg+:#e2e2e2
--color=prompt:#4cdadb
--color=hl+:#ffb4ab
--color=selected-bg:#474747
--color=border:#474747
--color=label:#e2e2e2"

if set -q FZF_DEFAULT_OPTS[1]; and test -n "$FZF_DEFAULT_OPTS"
    set -Ux FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS
$fzf_theme_opts"
else
    set -Ux FZF_DEFAULT_OPTS "$fzf_theme_opts"
end
