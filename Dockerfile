FROM alpine:latest

# Install minimal dependencies
RUN apk add --no-cache ca-certificates openssl

# Create necessary directories
RUN mkdir -p /etc/hysteria /var/log/hysteria

# Health check - verify process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ps aux | grep -q "[/]hysteria" || exit 1

# Hysteria2 binary and config will be mounted via volumes
# This image is used as a base with the binary injected via docker run -v

# Run as non-root for security (optional, comment out if not needed)
# RUN addgroup -g 1000 hysteria && adduser -D -u 1000 -G hysteria hysteria
# USER hysteria

# Default command - will be overridden by docker run
ENTRYPOINT ["/hysteria"]