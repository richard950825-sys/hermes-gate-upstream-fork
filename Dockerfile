FROM alpine:latest

# 安装依赖：bash, ssh, mosh, tmux, fzf, jq, ping, ps
RUN apk add --no-cache \
    bash \
    openssh-client \
    mosh \
    tmux \
    fzf \
    jq \
    iputils \
    procps \
    bc

# 创建非 root 用户
RUN adduser -D -s /bin/bash hermes
USER hermes
WORKDIR /home/hermes

# 复制 tmux 配置和脚本
COPY --chown=hermes:hermes tmux-local.conf /home/hermes/.tmux.conf
COPY --chown=hermes:hermes entrypoint.sh hermes-manager.sh netwatch.sh render-status.sh /home/hermes/
RUN chmod +x /home/hermes/*.sh

ENTRYPOINT ["/home/hermes/entrypoint.sh"]
