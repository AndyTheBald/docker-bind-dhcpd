#!/bin/bash
set -e

ROOT_PASSWORD=${ROOT_PASSWORD:-password}
WEBMIN_ENABLED=${WEBMIN_ENABLED:-true}

BIND_DATA_DIR=${DATA_DIR}/bind
WEBMIN_DATA_DIR=${DATA_DIR}/webmin
DHCP_DATA_DIR=${DATA_DIR}/dhcp

create_bind_data_dir() {
  mkdir -p ${BIND_DATA_DIR}

  # populate default bind configuration if it does not exist
  if [ ! -d ${BIND_DATA_DIR}/etc ]; then
    mv /etc/bind ${BIND_DATA_DIR}/etc
  fi
  rm -rf /etc/bind
  ln -sf ${BIND_DATA_DIR}/etc /etc/bind
  chmod -R 0775 ${BIND_DATA_DIR}
  chown -R ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}

  if [ ! -d ${BIND_DATA_DIR}/lib ]; then
    mkdir -p ${BIND_DATA_DIR}/lib
    chown ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}/lib
  fi
  rm -rf /var/lib/bind
  ln -sf ${BIND_DATA_DIR}/lib /var/lib/bind
}

create_dhcp_data_dir() {
  mkdir -p ${DHCP_DATA_DIR}

  # populate default dhcp configuration if it does not exist
  if [ ! -d ${DHCP_DATA_DIR}/etc ]; then
    mv /etc/dhcp ${DHCP_DATA_DIR}/etc
  fi
  rm -rf /etc/dhcp
  ln -sf ${DHCP_DATA_DIR}/etc /etc/dhcp
  chmod -R 0775 ${DHCP_DATA_DIR}
  chown -R ${DHCP_USER}:${DHCP_USER} ${DHCP_DATA_DIR}

  # link the lib dir into data
  if [ ! -d ${DHCP_DATA_DIR}/lib ]; then
    mkdir -p ${DHCP_DATA_DIR}/lib
    chown ${DHCP_USER}:${DHCP_USER} ${DHCP_DATA_DIR}/lib
  fi
  rm -rf /var/lib/dhcp
  ln -sf ${DHCP_DATA_DIR}/lib /var/lib/dhcp

  #link the default file into the data dir
  if [ ! -f ${DHCP_DATA_DIR}/init_defaults ]; then
	mv /etc/default/isc-dhcp-server ${DHCP_DATA_DIR}/init_defaults
  fi
  rm -f /etc/default/isc-dhcp-server
  ln -sf ${DHCP_DATA_DIR}/init_defaults /etc/default/isc-dhcp-server
}

create_webmin_data_dir() {
  mkdir -p ${WEBMIN_DATA_DIR}
  chmod -R 0755 ${WEBMIN_DATA_DIR}
  chown -R root:root ${WEBMIN_DATA_DIR}

  # populate the default webmin configuration if it does not exist
  if [ ! -d ${WEBMIN_DATA_DIR}/etc ]; then
    mv /etc/webmin ${WEBMIN_DATA_DIR}/etc
  fi
  rm -rf /etc/webmin
  ln -sf ${WEBMIN_DATA_DIR}/etc /etc/webmin
}

set_root_passwd() {
  echo "root:$ROOT_PASSWORD" | chpasswd
}

create_bind_pid_dir() {
  mkdir -m 0775 -p /var/run/named
  chown root:${BIND_USER} /var/run/named
}

create_dhcp_pid_dir() {
  mkdir -m 0775 -p /var/run/dhcp-server
  chown root:${DHCP_USER} /var/run/dhcp-server
}

create_bind_cache_dir() {
  mkdir -m 0775 -p /var/cache/bind
  chown root:${BIND_USER} /var/cache/bind
}

create_dhcp_current_network() {
  DHCPD_FILE=${DHCP_DATA_DIR}/etc/dhcpd.conf
  if [ -f ${DHCPD_FILE} ]; then
    # Get all the ipv4 networks
    ETH_CONFIG=`ifconfig | sed -n "s/inet \([^ \t]*\).*netmask \([^ ]*\).*/\1 \2/p"`
    echo "${ETH_CONFIG}" | while read ADAPTER; do
      IPCALC=`ipcalc -bn ${ADAPTER}`
      NETWORK=`echo $IPCALC | sed -n "s/.*Network:\s*\([0-9.]*\).*/\1/p"`
      SUBNET=`echo $IPCALC | sed -n "s/.*Netmask:\s*\([0-9.]*\).*/\1/p"`
      SUBNET_BLOCK="subnet ${NETWORK} netmask ${SUBNET}"

      # ignore loopback
      if [ "$NETWORK" == "127.0.0.0" ]; then
        continue
      fi

      # ignore any /32
      if [ "$SUBNET" == "255.255.255.255" ]; then
        continue
      fi

      # Does our subnet exist in the block?
      if grep -q "${SUBNET_BLOCK}" ${DHCPD_FILE}
      then
        echo We found our network ${NETWORK} in the setup
      else
        sed -i "0,/^#*subnet .*/s/^subnet .*/${SUBNET_BLOCK} {\n}\n\n&/" ${DHCPD_FILE}
        echo "Injected our subnet ${NETWORK}"
      fi
    done
  fi
}

create_bind9_service_link() {
  BIND9_SERVICE_FILE=/usr/lib/systemd/system/bind9.service
  NAMED_SERVICE_FILE=/usr/lib/systemd/system/named.service
  if [ ! -f ${BIND9_SERVICE_FILE} ]; then
    ln -s ${NAMED_SERVICE_FILE} ${BIND9_SERVICE_FILE}
  fi
}

#Don't activate ipv6, do be prepared to go on any ipv4
create_dhcp_listen_adapters() {
  #1: lo    in
  ADAPTERS=$(ip -4 -o a | sed -n "s/^[^:]*:[[:space:]]*\([^ ]*\).*/\1 /p" | tr -d '\n')
  QUOTED=\"${ADAPTERS}\"
  DHCP_DEFAULTS=${DHCP_DATA_DIR}/init_defaults
  if [ -f ${DHCP_DEFAULTS} ]; then
    sed -i "s/INTERFACESv4=.*/INTERFACESv4=${QUOTED}/g" ${DHCP_DEFAULTS}
  fi
}

create_bind_pid_dir
create_bind_data_dir
create_bind_cache_dir
create_bind9_service_link

create_dhcp_data_dir
create_dhcp_pid_dir
create_dhcp_current_network
create_dhcp_listen_adapters


# allow arguments to be passed to named
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$@"
  set --
elif [[ ${1} == named || ${1} == $(which named) ]]; then
  EXTRA_ARGS="${@:2}"
  set --
fi

# default behaviour is to launch named
if [[ -z ${1} ]]; then
  if [ "${WEBMIN_ENABLED}" == "true" ]; then
    create_webmin_data_dir
    set_root_passwd
    echo "Starting webmin..."
    systemctl restart webmin
  fi

  # If the PID file exists at this point it's an error
  if [ -f "/var/run/dhcpd.pid" ]; then
    echo "Deleting existing DHCP PID..."
    rm /var/run/dhcpd.pid
  fi
  echo "Starting dhcpd..."
  /etc/init.d/isc-dhcp-server start

  echo "Starting named..."
  exec $(which named) -u ${BIND_USER} -g ${EXTRA_ARGS}
else
  exec "$@"
fi
