#!/bin/bash

set -e
set -o pipefail

declare -r init_type='auto'

command_exists () {
  type "$1" &> /dev/null ;
}
addUser() {
  : ${1:?'User was not defined'}
  declare -r user="$1"
  declare -r uid="$2"

  if [ -z "$uid" ]; then
    declare -r uid_flags=""
  else
    declare -r uid_flags="--uid $uid"
  fi

  declare -r group=${3:-$user}
  declare -r descr=${4:-No description}
  declare -r shell=${5:-/bin/false}

  if ! getent passwd | grep -q "^$user:"; then
    echo "Creating system user: $user in $group with $descr and shell $shell"
    useradd $uid_flags --gid $group --no-create-home --system --shell $shell -c "$descr" $user
  fi
}
addGroup() {
  : ${1:?'Group was not defined'}
  declare -r group="$1"
  declare -r gid="$2"

  if [ -z "$gid" ]; then
    declare -r gid_flags=""
  else
    declare -r gid_flags="--gid $gid"
  fi

  if ! getent group | grep -q "^$group:" ; then
    echo "Creating system group: $group"
    groupadd $gid_flags --system $group
  fi
}
addGroup 'SmartHome' ''
addUser 'SmartHome' '' 'SmartHome' 'SmartHome user-daemon' '/bin/false'


##### ---------- INSTALL NVM ---------- #####
if ! command_exists nvm; then
  echo "Start setting up node"
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | sh

  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
fi
nvm install 9.8.0
##### ================================== #####


##### ---------- INSTALL GIT ---------- #####
apt-get update
if ! command_exists git; then
  apt-get install git-core -y
fi
##### ================================== #####


##### ---------- INSTALL MAIN NPM PACKAGES ---------- #####
apt-get install libavahi-compat-libdnssd-dev -y

rm -rf wiringPi
git clone git://git.drogon.net/wiringPi
cd wiringPi
. build
cd ~/

npm_g_install() {
  : {$1:?'Package name was not defined'}

  echo "Install npm dependency: " $1
  npm install --production -g -f --unsafe-perm $1
}

if ! command_exists homebridge ; then
  npm_g_install 'homebridge'
fi

if ! command_exists node-red ; then
  npm_g_install 'node-red'
fi

npm_install() {
  : {$1:?'Package name was not defined'}

  echo "Install npm dependency: " $1
  npm install --production -f --unsafe-perm $1
}

mkdir -p ~/.homebridge
mkdir -p ~/.node-red

cd ~/.node-red
npm_install 'node-red-dashboard'
npm_install 'rcswitch'
npm_install 'node-persist'

cd ~/

npm_g_install 'homebridge-websocket'
##### =============================================== #####


##### ---------- CONFIGURING UNIT FILES ---------- #####
NODE_RUNNER="$(which node)"
NODE_RED_RUNNER="$(which node-red)"
HOMEBRIDGE_RUNNER="$(which homebridge)"

wget https://raw.githubusercontent.com/ataomega/SmartHome/master/resources/template.service
sed -i "s@{{arg1}}@$NODE_RUNNER@g" template.service
cp template.service /etc/systemd/system/homebridge.service
cp template.service /etc/systemd/system/node-red.service
rm template.service

sed -i "s@{{arg2}}@$HOMEBRIDGE_RUNNER@g" /etc/systemd/system/homebridge.service
sed -i "s@{{arg2}}@$NODE_RED_RUNNER@g" /etc/systemd/system/node-red.service
##### ============================================ #####


##### ---------- CONFIGURING MAIN PACKAGES ---------- #####
sudo -i
wget https://raw.githubusercontent.com/ataomega/SmartHome/master/resources/homebridge_config.json
mv homebridge_config.json ~/.homebridge/config.json

wget https://raw.githubusercontent.com/ataomega/SmartHome/master/resources/node_red_settings.js
mv node_red_settings.js ~/.node-red/settings.js

wget https://raw.githubusercontent.com/ataomega/SmartHome/master/resources/SmartHome_flow.json
mv SmartHome_flow.json ~/.node-red/SmartHome_flow.json
##### ================================================ #####


##### ---------- STARTING UNITS ---------- #####
systemctl daemon-reload
systemctl is-enabled node-red.service; export NODE_RED_UNIT_FOUND=$?

echo '+-> Starting node-red service'
systemctl enable node-red.service
systemctl start node-red.service

echo '+-> Starting homebridge service'
systemctl enable homebridge.service
systemctl start homebridge.service
##### ==================================== #####
