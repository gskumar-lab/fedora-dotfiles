set -l fzf_theme_opts "\
--color=bg+:#302721
--color=bg:#231d1a
--color=spinner:#f3f2f2
--color=hl:#aa5a29
--color=fg:#f3f2f2
--color=header:#aa5a29
--color=info:#d79a75
--color=pointer:#f3f2f2
--color=marker:#b6b2af
--color=fg+:#f3f2f2
--color=prompt:#d79a75
--color=hl+:#aa5a29
--color=selected-bg:#302721
--color=border:#302721
--color=label:#f3f2f2"

if set -q FZF_DEFAULT_OPTS[1]; and test -n "$FZF_DEFAULT_OPTS"
    set -Ux FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS
$fzf_theme_opts"
else
    set -Ux FZF_DEFAULT_OPTS "$fzf_theme_opts"
end
