FROM --platform=linux/arm64 debian:bookworm-slim

ARG PAYLOAD=dist/yunshu-headless-arm64
ARG YUNSHU_CORP_CODE=cpe
ARG YUNSHU_SP_ADDR=https://sp.eagleyun.cn/

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      iproute2 \
      nftables \
      mini-httpd \
      libgcc-s1 \
      zlib1g \
 && rm -rf /var/lib/apt/lists/*

COPY ${PAYLOAD}/opt/apps/yunshu/files/bin/ /opt/apps/yunshu/files/bin/
COPY ${PAYLOAD}/opt/apps/yunshu/files/config/version.ini /usr/local/share/yunshu/version.ini

RUN set -eu; \
    _arch="$(dpkg --print-architecture)"; \
    _m="$(od -An -tx1 -j18 -N2 /opt/apps/yunshu/files/bin/yunshu-daemon | tr -d ' ')"; \
    case "${_arch}" in \
      arm64) _want=b700 ;; \
      amd64) _want=3e00 ;; \
      *)     _want="" ;; \
    esac; \
    if [ -n "${_want}" ] && [ "${_m}" != "${_want}" ]; then \
      echo "payload 架构与镜像架构不符: 镜像=${_arch} 期望 e_machine=${_want} 实际=${_m}" >&2; \
      echo "arm64 镜像需 PAYLOAD=dist/yunshu-headless-arm64" >&2; \
      echo "amd64 镜像需 PAYLOAD=dist/yunshu-headless" >&2; \
      exit 1; \
    fi; \
    echo "架构校验通过: 镜像=${_arch} e_machine=${_m} payload=${PAYLOAD}"

RUN mkdir -p /var/lib/yunshu \
 && for d in config socket tmp bak logs; do ln -sfn "/var/lib/yunshu/$d" "/opt/apps/yunshu/files/$d"; done

COPY image/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY image/login.sh      /usr/local/bin/yunshu-login.sh
COPY image/connect.sh    /usr/local/bin/yunshu-connect.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
               /usr/local/bin/yunshu-login.sh \
               /usr/local/bin/yunshu-connect.sh

ENV YUNSHU_CORP_CODE=${YUNSHU_CORP_CODE} \
    YUNSHU_SP_ADDR=${YUNSHU_SP_ADDR} \
    YUNSHU_STATE_DIR=/var/lib/yunshu \
    YUNSHU_BIN=/opt/apps/yunshu/files/bin/yunshu \
    YUNSHU_LOGIN_HTTP_ADDR=0.0.0.0 \
    YUNSHU_LOGIN_HTTP_PORT=8080

VOLUME ["/var/lib/yunshu"]
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
