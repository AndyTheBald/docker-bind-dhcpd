#I Couldn't get Debian rsyslog to start - and need that to debug isc-dhcpd
#FROM debian:stable
# Instead use Ubuntu LTS
FROM ubuntu:latest

ENV BIND_USER=bind \
    DATA_DIR=/data

RUN apt-get update && apt-get install --no-install-recommends -y wget gnupg
# Systemctl needs to be installed before startup for it to work.  And rsyslog is needed to diagnose dhcpd
# RUN apt-get install -y systemctl rsyslog
RUN apt-get install -y ipcalc net-tools
RUN rm -rf /etc/apt/apt.conf.d/docker-gzip-indexes
RUN wget --no-check-certificate -q -O - http://www.webmin.com/jcameron-key.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/jcameron-key.gpg 
RUN echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y bind9 bind9-host webmin isc-dhcp-server
RUN rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 53/udp 53/tcp 67/udp 10000/tcp
VOLUME ["${DATA_DIR}"]
ENTRYPOINT ["/sbin/entrypoint.sh"]
# If you want a shell to debug installation
# ENTRYPOINT ["/bin/bash"]
CMD ["/usr/sbin/named"]
