set -l fzf_theme_opts "\
--color=bg+:#212a30
--color=bg:#1a1f23
--color=spinner:#f2f2f3
--color=hl:#fd4663
--color=fg:#f2f2f3
--color=header:#fd4663
--color=info:#75add7
--color=pointer:#f2f2f3
--color=marker:#afb3b6
--color=fg+:#f2f2f3
--color=prompt:#75add7
--color=hl+:#fd4663
--color=selected-bg:#212a30
--color=border:#212a30
--color=label:#f2f2f3"

if set -q FZF_DEFAULT_OPTS[1]; and test -n "$FZF_DEFAULT_OPTS"
    set -Ux FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS
$fzf_theme_opts"
else
    set -Ux FZF_DEFAULT_OPTS "$fzf_theme_opts"
end
