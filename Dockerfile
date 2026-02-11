FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

# install packages
ARG OPENCLAW_DOCKER_APT_PACKAGES="nano ffmpeg jq"
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# add alias to bashrc
RUN if ! grep -qxF "alias openclaw='node /app/dist/index.js'" /etc/bash.bashrc; then \
    echo "alias openclaw='node /app/dist/index.js'" >> /etc/bash.bashrc; \
  fi

ARG TARGETARCH

# binaries (edit as needed)
RUN set -eux; \
  case "$TARGETARCH" in \
    arm64) BIN_ARCH=arm64 ;; \
    amd64) BIN_ARCH=amd64 ;; \
    *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
  esac; \
  echo "Using BIN_ARCH=$BIN_ARCH"; \
  \
  # gogcli
  curl -L https://github.com/steipete/gogcli/releases/download/v0.9.0/gogcli_0.9.0_linux_${BIN_ARCH}.tar.gz \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog; \
  \
  # goplaces
  curl -L https://github.com/steipete/goplaces/releases/download/v0.2.1/goplaces_0.2.1_linux_${BIN_ARCH}.tar.gz \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces; \
  \
  # wacli
  curl -L https://github.com/haider-patanwala/wacli/releases/download/v0.2.3/wacli-linux-${BIN_ARCH}.tar.gz \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/wacli; \
  \
  # himalaya (special naming handled once)
  if [ "$BIN_ARCH" = "arm64" ]; then HIMA_ARCH=aarch64; else HIMA_ARCH=x86_64; fi; \
  curl -L https://github.com/pimalaya/himalaya/releases/download/v1.1.0/himalaya.${HIMA_ARCH}-linux.tgz \
    | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/himalaya; \
  \
  # gh
  curl -L https://github.com/cli/cli/releases/download/v2.86.0/gh_2.86.0_linux_${BIN_ARCH}.tar.gz \
    | tar -xz -C /usr/local/bin --strip-components=2 "gh_2.86.0_linux_${BIN_ARCH}/bin/gh"; \
  chmod +x /usr/local/bin/gh


COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile
RUN npm install -g @steipete/summarize gitload-cli agent-browser

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# For container platforms requiring external health checks:
#   1. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD env var
#   2. Override CMD: ["node","openclaw.mjs","gateway","--allow-unconfigured","--bind","lan"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
