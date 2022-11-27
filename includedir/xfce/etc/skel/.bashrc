# .bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
PS1='[\u@\h \W]\$ '

#Custom Bash prompt
triangle=$'\uE0B0'
triangle_left=

PS1=' \[\e[0;38;5;23m\]$triangle_left\[\e[0;48;5;23m\] \[\e[0;48;5;23m\]\u\[\e[0;48;5;23m\]@\[\e[0;48;5;23m\]\h\[\e[0;48;5;23m\] \[\e[0;38;5;23;48;5;29m\]$triangle\[\e[0;48;5;29m\] \[\e[0;48;5;29m\]\w\[\e[0;48;5;29m\] \[\e[0;38;5;29;48;5;35m\]$triangle\[\e[0;48;5;35m\] \[\e[0;48;5;35m\]\@\[\e[0;48;5;35m\] \[\e[0;38;5;35;48;5;42m\]$triangle\[\e[0;48;5;42m\] \[\e[0;38;5;235;48;5;42m\]$(git branch 2>/dev/null | grep '"'"'^*'"'"' | colrm 1 2) $\[\e[0;48;5;42m\] \[\e[0;38;5;42m\]$triangle\[\e[0m\] '

[[ $- == *i* ]] && . /usr/share/blesh/ble.sh
