#!/bin/sh

# Adding user if needed
add_user() {
  local USER=$1
  local GROUP=$2
  local UID=$3
  local GID=$4
  local DISTRO=$5
  if [ "$DISTRO" = "alpine" ]; then
    groups | grep "$GROUP" > /dev/null || addgroup -g "$GID" "$GROUP" 2>/dev/null
    id -u "$GROUP" > /dev/null || adduser -H -D -G "$GROUP" -u "$UID" "$USER" "$GROUP" 2>/dev/null
  else
    groups | grep "$GROUP" > /dev/null || groupadd --force --gid "$GID" "$GROUP" 2>/dev/null
    id -u "$GROUP" > /dev/null || useradd --gid "$GID" -M -N --uid "$UID" "$USER" 2>/dev/null
  fi;
}

# Veridy user
verify_user() {
  local USER=$1
  local GROUP=$2
  local DISTRO=$3
  id -u "$USER" > /dev/null
  groups | grep "$GROUP" > /dev/null
  if [ "$DISTRO" = "alpine" ]; then
    true
    # is there a chsh we can use? do we need to?
  else
    chsh -s /bin/bash $USER || true
  fi;
}

# Reset user
reset_user() {
  local USER=$1
  local GROUP=$2
  local HOST_UID=$3
  local HOST_GID=$4
  local DISTRO=$5
  local HOST_GROUP=$(getent group "$HOST_GID" | cut -d: -f1)
  if [ "$DISTRO" = "alpine" ]; then
    deluser "$USER" 2>/dev/null
    addgroup -g "$HOST_GID" "$GROUP" 2>/dev/null | addgroup "$GROUP" 2>/dev/null
    addgroup -g "$HOST_GID" "$HOST_GROUP" 2>/dev/null
    adduser -u "$HOST_UID" -G "$HOST_GROUP" -h /var/www -D "$USER" 2>/dev/null
    adduser "$USER" "$GROUP" 2>/dev/null
  else
    usermod -o -u "$HOST_UID" "$USER" 2>/dev/null
    groupmod -g "$HOST_GID" "$GROUP" 2>/dev/null || true
    usermod -g $(getent group "$HOST_GID" | cut -d: -f1) "$USER" 2>/dev/null || true
    usermod -a -G "$GROUP" "$USER" 2>/dev/null || true
  fi;
  # If this mapping is incorrect lets abort here
  if [ "$(id -u $USER)" != "$HOST_UID" ]; then
    echo "Looks like host/container user mapping was not possible! aborting..."
    exit 0
  fi
}

# Perm sweeper
# Note that while the order of these things might seem weird and/or redundant
# it is designed to fix more "critical" directories first
perm_sweep() {
  local USER=$1
  local GROUP=$2

  # Start with the directories that are likely blockers
  chown -R $USER:$GROUP /usr/local/bin
  chown $USER:$GROUP /var/www
  chown $USER:$GROUP /app
  chmod 755 /var/www

  # Do a background sweep
  nohup chown -R $USER:$GROUP /app >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /var/www/.ssh >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /user/.ssh >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /var/www >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /usr/local/bin >/dev/null 2>&1 &
  nohup chmod -R 755 /var/www >/dev/null 2>&1 &

  # Lets also make some /usr/locals chowned
  nohup chown -R $USER:$GROUP /usr/local/lib >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /usr/local/share >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /usr/local >/dev/null 2>&1 &

  # Make sure we chown the $USER home directory
  nohup chown -R $USER:$GROUP $(getent passwd $USER | cut -d : -f 6) >/dev/null 2>&1 &
  nohup chown -R $USER:$GROUP /lando >/dev/null 2>&1 &
}
