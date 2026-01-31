FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES="nano ffmpeg jq"
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi


# binaries (edit as needed)
RUN curl -L https://github.com/steipete/gogcli/releases/download/v0.9.0/gogcli_0.9.0_linux_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog

RUN curl -L https://github.com/steipete/goplaces/releases/download/v0.2.1/goplaces_0.2.1_linux_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces

RUN curl -L https://github.com/haider-patanwala/wacli/releases/download/v0.2.3/wacli-linux-arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/wacli

RUN curl -L https://github.com/pimalaya/himalaya/releases/download/v1.1.0/himalaya.aarch64-linux.tgz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/himalaya

RUN curl -L https://github.com/cli/cli/releases/download/v2.86.0/gh_2.86.0_linux_arm64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gh

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile
RUN pnpm install -g @steipete/summarize gitload-cli

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
# USER node

CMD ["node", "dist/index.js"]
