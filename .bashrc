#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

export PATH="$PATH:~/.local/bin"
export PATH="$PATH:~/go/bin"

# Starship
eval "$(starship init bash)"

# Distrobox setup
# Check if we are inside a Distrobox container
if [ -n "$CONTAINER_ID" ] || [ -n "$ON_DISTROBOX" ]; then

    # bash-completion
    . /usr/share/bash-completion/bash_completion

    # GitHub CLI quirks
    git config --global --unset-all credential.helper
    gh auth setup-git

    export LIBGL_ALWAYS_SOFTWARE=1
    export QT_X11_NO_MITSHM=1

    # Force display to the host's actual display
    HOST_DISPLAY=$(distrobox-host-exec printenv DISPLAY 2>/dev/null)
    if [ -n "$HOST_DISPLAY" ]; then
        export DISPLAY="$HOST_DISPLAY"
    fi

    # Check if specifically inside the ROS container
    if [[ "$CONTAINER_ID" == "ros1" ]]; then
        export DISABLE_ROS1_EOL_WARNINGS=1

        source /opt/ros/noetic/setup.bash
 
    elif [[ "$CONTAINER_ID" == "ros2" ]]; then
        source /opt/ros/kilted/setup.bash
 
    fi

    return

else
    alias ros1="echo '[*] Entering ROS 1...' && distrobox enter ros1"
    alias ros2="echo '[*] Entering ROS 2...' && distrobox enter ros2"
fi

# Docker
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock


