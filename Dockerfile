FROM alpine:latest

# Install dependencies
RUN apk add --no-cache ca-certificates curl openssl

# Download and install Hysteria2
RUN HYSTERIA_VERSION=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' | sed 's/app\///') && \
    curl -Lo /usr/local/bin/hysteria https://github.com/apernet/hysteria/releases/download/app/v${HYSTERIA_VERSION}/hysteria-linux-amd64 && \
    chmod +x /usr/local/bin/hysteria

# Create directories
RUN mkdir -p /etc/hysteria /var/log/hysteria

# Copy configuration
COPY config.yaml /etc/hysteria/config.yaml

# Expose port
EXPOSE 443/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD hysteria version || exit 1

# Run Hysteria2
CMD ["/usr/local/bin/hysteria", "server", "-c", "/etc/hysteria/config.yaml"]
