#!/usr/bin/env bash

### https://github.com/gpakosz/.tmux
pushd ~
if [ ! -d ~/.tmux/ ]; then
  git clone --depth=1 https://github.com/gpakosz/.tmux.git
  ln -s -f ~/.tmux/.tmux.conf
fi
if [ ! -f ~/.tmux.conf.local ]; then	
  cp ~/.tmux/.tmux.conf.local ~/
  echo "set -g mouse on" | tee -a ~/.tmux.conf.local
  echo "set -g history-limit 100000" | tee -a ~/.tmux.conf.local
  echo "new-session" | tee -a ~/.tmux.conf.local
fi
popd
