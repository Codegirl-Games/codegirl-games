FROM debian:bookworm-slim AS builder

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        libx11-dev \
    && rm -rf /var/lib/apt/lists/*

COPY examples/mover/main.c /src/main.c
RUN cc -std=c11 -O2 -Wall -Wextra -Werror /src/main.c -lX11 -o /mover

FROM debian:bookworm-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libx11-6 \
        openbox \
        scrot \
        x11-utils \
        xdotool \
        xvfb \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 agentbox

COPY --from=builder /mover /opt/agentbox/mover
COPY environment/entrypoint.sh /opt/agentbox/entrypoint.sh
RUN chmod 0755 /opt/agentbox/entrypoint.sh /opt/agentbox/mover

USER agentbox
ENV DISPLAY=:99
ENTRYPOINT ["/opt/agentbox/entrypoint.sh"]
