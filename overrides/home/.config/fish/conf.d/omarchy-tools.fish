# Tools from the Omarchy setup; each only activates once installed.
if status is-interactive
    type -q mise; and mise activate fish | source
    type -q zoxide; and zoxide init fish | source
    type -q starship; and starship init fish | source
end
