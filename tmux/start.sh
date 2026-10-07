#!/bin/bash

# Absolute path to this script. /home/user/bin/foo.sh
SCRIPT=$(readlink -f $0)
# Absolute path this script is in. /home/user/bin
SCRIPTPATH=`dirname $SCRIPT`
cd "$SCRIPTPATH"

git submodule update --init --recursive # --remote # pull last versions

cd ../compose
./build.sh 
cd ..

cd holoswarm-client
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
deactivate
cd ..

cd "$SCRIPTPATH"

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
