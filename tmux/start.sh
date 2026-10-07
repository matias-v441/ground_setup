#!/bin/bash

# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=`dirname $SCRIPT`
cd "$SCRIPTPATH"

# the workspace build and the client environment come from ../setup.sh
if [ ! -d ../holoswarm_ros_packages/install ] || [ ! -x ../holoswarm-client/.venv/bin/holoswarm-client ]; then
  echo "Not set up yet: run ./setup.sh in the repository root first."
  exit 1
fi

export TMUX_SESSION_NAME=remote
export TMUX_SOCKET_NAME=mrs

# start tmuxinator
tmuxinator start -p ./session.yml

# if we are not in tmux
if [ -z $TMUX ]; then

  # just attach to the session
  tmux -L $TMUX_SOCKET_NAME a -t $TMUX_SESSION_NAME

# if we are in tmux
else

  # switch to the newly-started session
  tmux detach-client -E "tmux -L $TMUX_SOCKET_NAME a -t $TMUX_SESSION_NAME"

fi
