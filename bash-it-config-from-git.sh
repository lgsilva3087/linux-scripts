#!/usr/bin/env bash

### https://github.com/Bash-it/bash-it
pushd ~
if [ ! -d ~/.bash_it/ ]; then
  git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it
  ~/.bash_it/install.sh
  sed -i 's/BASH_IT_THEME=.*$/BASH_IT_THEME='\''modern'\''/' ~/.bashrc
fi
popd

