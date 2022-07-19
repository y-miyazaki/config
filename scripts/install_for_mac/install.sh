#!/bin/bash

# brew
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#--------------------------------------------------------------
# docker/docker-compse/lima
#--------------------------------------------------------------
sudo chown -R $(whoami) $(brew --prefix)/*
brew install lima docker docker-compose
limactl start docker.yaml --tty=false
limactl list

docker context create lima --docker "host=$(limactl list docker --format 'unix://{{.Dir}}/sock/docker.sock')"
docker context use lima
#--------------------------------------------------------------
# Docker for Desktop
#--------------------------------------------------------------
# brew install docker --cask

# install twingate from appstore
# install sourcetree from web
# install slack from web
# install mysqlworkbench
