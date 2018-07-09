FROM debian:stretch

ENV BIND_USER=bind \
    BIND_VERSION=1:9.10 \
    WEBMIN_VERSION=1.8 \
	DHCPD_VERSION=4.3 \
    DATA_DIR=/data

RUN apt-get update && apt-get install --no-install-recommends -y wget
RUN rm -rf /etc/apt/apt.conf.d/docker-gzip-indexes \
 && wget http://www.webmin.com/jcameron-key.asc -qO - | apt-key add - \
 && echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
   bind9=${BIND_VERSION}* \
   bind9-host=${BIND_VERSION}* \
   webmin=${WEBMIN_VERSION}* \
   isc-dhcp-server=${DHCPD_VERSION}* \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 53/udp 53/tcp 67/udp 10000/tcp
VOLUME ["${DATA_DIR}"]
ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/usr/sbin/named"]
