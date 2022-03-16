#!/bin/bash

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install visual-studio-code --cask
# lima
brew install lima docker
curl https://raw.githubusercontent.com/lima-vm/lima/master/examples/docker.yaml -o docker.yaml
limactl start docker.yaml --tty=false
limactl list
docker context create lima --docker "host=$(limactl list docker --format 'unix://{{.Dir}}/sock/docker.sock')"
docker context use lima


# install twingate from appstore
# install sourcetree from web
# install slack from web
# install mysqlworkbench
