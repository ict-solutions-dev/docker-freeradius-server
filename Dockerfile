# Start from FreeRadius image
FROM freeradius/freeradius-server:3.2.3

# Set labels for metadata
LABEL Description="FreeRadius Docker image based on Ubuntu 20.04 LTS." \
      Version="3.2.3"

# Set non-interactive mode
ARG DEBIAN_FRONTEND=noninteractive

# Set timezone
ENV TZ=Europe/Bratislava

# Install packages and cleanup in one RUN statement
RUN apt-get update && apt-get install --yes --no-install-recommends \
    apt-utils \
    ipcalc \
    tzdata \
    net-tools \
    mariadb-client \
    libmysqlclient-dev \
    unzip \
    wget \
    && ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && dpkg-reconfigure tzdata \
    && rm -rf /var/lib/apt/lists/* \
    # Create directories
    && mkdir /data /internal_data \
    # Forward radius logs to docker log collector
    && ln -sf /dev/stdout /var/log/freeradius/radius.log

# Copy init script and make it executable
COPY assets/01-init.sh /
RUN chmod +x /01-init.sh

# Expose necessary ports
EXPOSE 1812/udp 1813/udp 18121/udp

# Set entrypoint
ENTRYPOINT ["/01-init.sh"]

# Set default command
CMD ["freeradius"]
