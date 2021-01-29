FROM ubuntu:18.04 AS zig

ARG ZIG_VERSION=0.7.1
ARG ZIG_URL=https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_SHA=18c7b9b200600f8bcde1cd8d7f1f578cbc3676241ce36d771937ce19a8159b8d

WORKDIR /usr/src

RUN apt-get update

RUN apt-get install -y curl \
    && curl -s -o zig.tar.xz ${ZIG_URL} \
    && echo "${ZIG_SHA} *zig.tar.xz" | sha256sum -c -

RUN mkdir -p /usr/local/bin/zig

RUN apt-get install -y tar xz-utils \
    && tar -Jxvf zig.tar.xz -C /usr/local/bin/zig

RUN rm zig.tar.xz

RUN chmod +x /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig

COPY ./public/one-lib .
RUN /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig build -Drelease-small=true

FROM node:15 AS build

WORKDIR /usr/src

RUN mkdir server
RUN mkdir public

COPY ./server ./server
COPY ./public ./public

RUN cd /usr/src/server \
    && npm install \
    && npm run build
RUN cd /usr/src/public \
    && npm install \
    && npm run build:prod

FROM node:15

WORKDIR /usr/src

RUN mkdir public
RUN mkdir server

COPY --from=zig /usr/src/zig-cache/lib/one-math.wasm ./public/one-lib/zig-cache/lib/
COPY --from=build /usr/src/public/dist ./public/dist
COPY ./public/assets/favicon.ico ./public/assets/favicon.ico
COPY --from=build /usr/src/public/styles ./public/styles
COPY --from=build /usr/src/public/index.html ./public/index.html
COPY ./server/sao_catalog ./server
COPY --from=build /usr/src/server/server.js ./server/server.js


COPY --from=build /usr/src/server/node_modules ./server/node_modules 

RUN cd /usr/src/server

EXPOSE 80
ENTRYPOINT [ "node", "/usr/src/server/server.js" ]






