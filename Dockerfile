FROM alpine:3.13 AS zig

ARG ZIG_VERSION=0.8.0
ARG ZIG_URL=https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_SHA=502625d3da3ae595c5f44a809a87714320b7a40e6dff4a895b5fa7df3391d01e

# Download Zig@ZIG_VERSION from official site
WORKDIR /usr/src

RUN apk add --no-cache curl \
    && curl -s -o zig.tar.xz ${ZIG_URL} \
    && echo "${ZIG_SHA} *zig.tar.xz" | sha256sum -c -

RUN mkdir -p /usr/local/bin/zig

RUN apk add --no-cache tar xz \
    && tar -Jxvf zig.tar.xz -C /usr/local/bin/zig

RUN rm zig.tar.xz

RUN chmod +x /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig

# Build WASM Module
COPY ./public/one-lib .
RUN /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig build -Drelease-small=true

FROM node:15-alpine AS build

WORKDIR /usr/src

RUN mkdir server
RUN mkdir public

# Server Setup 
WORKDIR /usr/src/server

COPY ./server/package*.json .
RUN npm install

COPY ./server/server.ts .
COPY ./server/tsconfig.json .
RUN npm run build

# Client Setup
WORKDIR /usr/src/public

COPY ./public/package*.json .
RUN npm install

COPY ./public .
RUN npm run build:prod

FROM node:15-alpine

ENV HOST=0.0.0.0

WORKDIR /usr/src

RUN mkdir public
RUN mkdir server

# Copy over necessary files from build images
COPY ./server/sao_catalog ./server
COPY ./server/constellations ./server/constellations
COPY ./public/assets/favicon.ico ./public/assets/favicon.ico
COPY --from=build /usr/src/public/styles ./public/styles
COPY --from=build /usr/src/public/index.html ./public/index.html
COPY --from=build /usr/src/server/server.js ./server/server.js
COPY --from=build /usr/src/public/dist ./public/dist
COPY --from=zig /usr/src/zig-out/lib/one-math.wasm ./public/one-lib/zig-out/lib/

COPY --from=build /usr/src/server/node_modules ./server/node_modules 

RUN cd /usr/src/server

ENTRYPOINT [ "node", "/usr/src/server/server.js" ]
