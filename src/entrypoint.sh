#!/bin/bash

USE_ORACLE_JAVA=${I_ACCEPT_ORACLE_JAVA_LICENSE:-no}
USE_MINECRAFT=${I_ACCEPT_MINECRAFT_EULA:-no}

USER_ID=${LOCAL_USER_ID:-9001}
export HOME=/mc
export DATA=/mc_data

# Create account to run Minecraft Server
echo "Starting with UID : $USER_ID"
useradd -m -d /mc -o -c "Minecraft Server" mc -s /bin/bash -u $USER_ID
chown -R mc:mc $HOME
chown -R mc:mc $DATA

# Accept EULA ;-)
if [[ ! -e $DATA/eula.txt ]]; then
  if [ "$USE_MINECRAFT" == "yes" ]; then
    echo "eula=TRUE" > $DATA/eula.txt
    chown mc:mc $DATA/eula.txt
  else
    echo "The Minecraft EULA must be accepted by passing in I_ACCEPT_MINECRAFT_EULA=yes as an environment variable"
    exit 1
  fi
fi
ln -s $DATA/eula.txt $HOME/eula.txt
chown -h mc:mc $HOME/eula.txt

# Make sure JSON files are in place
JSON_FILES="banned-ips banned-players ops usercache whitelist"
for FILE in $JSON_FILES; do
  if [[ ! -e $DATA/$FILE.json ]]; then
    echo -n "[]" > $DATA/$FILE.json
    chown mc:mc $DATA/$FILE.json
  fi
  ln -s $DATA/$FILE.json $HOME/$FILE.json
  chown -h mc:mc $HOME/$FILE.json
done

# Make sure Server Properties are set
if [[ ! -e $DATA/server.properties ]]; then
  cp /tmp/server.properties $DATA/
  chown mc:mc $DATA/server.properties
fi
ln -s $DATA/server.properties $HOME/server.properties
chown -h mc:mc $HOME/server.properties

# Determine world folder
LEVELNAME=`cat $HOME/server.properties | grep "^level-name=" | sed -e "s/^.*=//"`

# Get Server Jar
if [[ ! -e $DATA/minecraft_server.jar.url ]]; then
  wget -q -O - https://minecraft.net/en/download/server \
   | grep 'minecraft_server\.[0-9]\+\.[0-9]\+\.[0-9]\+\.jar' \
   | sed -e 's/^.*a href="\(.*\)">.*$/\1/' \
   > $DATA/minecraft_server.jar.url
  chown mc:mc $DATA/minecraft_server.jar.url
fi
ln -s $DATA/minecraft_server.jar.url $HOME/minecraft_server.jar.url
chown -h mc:mc $HOME/minecraft_server.jar.url

wget -q -O - $(cat $HOME/minecraft_server.jar.url) \
 > $HOME/minecraft_server.jar
chown mc:mc $HOME/minecraft_server.jar

if [ "$USE_ORACLE_JAVA" == "yes" ]; then
  echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" \
    > /etc/apt/sources.list.d/webupd8team-ubuntu-java-xenial.list
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C2518248EEA14886
  echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
  echo debconf shared/accepted-oracle-license-v1-1 seen true   | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         oracle-java8-installer
else
  DEBIAN_FRONTEND=noninteractive set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         openjdk-8-jre
fi

EXEC=exec
DIRECTORIES="$LEVELNAME logs"
for DIRECTORY in $DIRECTORIES; do
  if [[ -e $DATA/$DIRECTORY ]]; then
    ln -s $DATA/$DIRECTORY $HOME/$DIRECTORY
    chown -h mc:mc $HOME/$DIRECTORY
  else
    EXEC=
  fi
done

if [[ -z $@ ]]; then
  cd /mc
  echo "$EXEC /usr/local/bin/gosu mc /tmp/wrapper.pl"
  $EXEC /usr/local/bin/gosu mc /tmp/wrapper.pl
else
  echo "$EXEC $@"
  $EXEC $@
fi

for DIRECTORY in $DIRECTORIES; do
  if [[ ! -e $DATA/$DIRECTORY ]] && [[ -e $HOME/$DIRECTORY ]]; then
    cp -r $HOME/$DIRECTORY $DATA/$DIRECTORY
    chown -R mc:mc $DATA/$DIRECTORY
  fi
done
