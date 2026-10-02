set -l fzf_theme_opts "\
--color=bg+:#2b2130
--color=bg:#201a23
--color=spinner:#f2f2f3
--color=hl:#fd4663
--color=fg:#f2f2f3
--color=header:#fd4663
--color=info:#b675d7
--color=pointer:#f2f2f3
--color=marker:#b4afb6
--color=fg+:#f2f2f3
--color=prompt:#b675d7
--color=hl+:#fd4663
--color=selected-bg:#2b2130
--color=border:#2b2130
--color=label:#f2f2f3"

if set -q FZF_DEFAULT_OPTS[1]; and test -n "$FZF_DEFAULT_OPTS"
    set -Ux FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS
$fzf_theme_opts"
else
    set -Ux FZF_DEFAULT_OPTS "$fzf_theme_opts"
end
