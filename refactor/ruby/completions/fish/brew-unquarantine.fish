# fish completion for brew-unquarantine

complete -c brew-unquarantine -f -l status -d "Check quarantine status only"
complete -c brew-unquarantine -f -l debug -d "Enable debug output"
complete -c brew-unquarantine -f -l help -d "Show help"

# Token (installed casks)
complete -c brew-unquarantine -f -a "(ls /opt/homebrew/Caskroom 2>/dev/null)"
