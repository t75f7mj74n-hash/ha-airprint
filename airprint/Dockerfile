FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Many vendor drivers (Brother's especially) ship only 32-bit x86 binaries.
# On amd64, enable the i386 architecture so those .debs install and run.
# No vendor driver is bundled; this only adds the 32-bit C library.
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then dpkg --add-architecture i386; fi \
 && apt-get update \
 && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
      apt-get install -y --no-install-recommends libc6:i386; \
    fi \
 && apt-get install -y --no-install-recommends \
      avahi-daemon \
      avahi-utils \
      ca-certificates \
      cups \
      cups-bsd \
      cups-client \
      cups-filters \
      curl \
      dbus \
      ghostscript \
      jq \
      python3 \
      snmp \
 && apt-get install -y --no-install-recommends \
      printer-driver-all \
      printer-driver-brlaser \
      printer-driver-cups-pdf \
      openprinting-ppds \
      foomatic-db-compressed-ppds \
 && apt-get install -y --no-install-recommends \
      libcupsimage2 \
      libgtk-3-0 \
      libjpeg62-turbo \
      libjbig0 \
      libgcrypt20 \
      lsb-release \
 && rm -rf /var/lib/apt/lists/*

COPY cupsd.conf /etc/cups/cupsd.conf
COPY cupsd.conf /usr/share/airprint/cupsd.conf
COPY avahi-daemon.conf /etc/avahi/avahi-daemon.conf
COPY printer.png /usr/share/airprint/printer.png
COPY drivers/ /usr/share/airprint/drivers/
COPY run.sh /run.sh
COPY monitor.sh /monitor.sh
COPY drivers.sh /drivers.sh
COPY discover.sh /discover.sh
COPY queue.sh /queue.sh
RUN chmod +x /run.sh /monitor.sh /drivers.sh /discover.sh /queue.sh

CMD ["/run.sh"]
