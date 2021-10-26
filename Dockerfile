
FROM alpine:3.13 AS night-math
ARG ZIG_VERSION=0.9.0-dev.1444+e2a2e6c14
# ARG ZIG_URL=https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_URL=https://ziglang.org/builds/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_SHA=c9a901c2df0661eede242a0860cddc30bbdb34d33f329ddae3e5cbdaed27306c

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
COPY ./night-math .
RUN /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig build -Drelease-small

FROM alpine:3.13 AS prepare-data

ARG ZIG_VERSION=0.9.0-dev.1444+e2a2e6c14
# ARG ZIG_URL=https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_URL=https://ziglang.org/builds/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_SHA=c9a901c2df0661eede242a0860cddc30bbdb34d33f329ddae3e5cbdaed27306c
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

RUN mkdir -p prepare-data
COPY ./prepare-data ./prepare-data

WORKDIR /usr/src/prepare-data
RUN /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig build -Drelease-small
WORKDIR /usr/src

RUN prepare-data/zig-out/bin/parse-data star_data.bin const_data.bin

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
RUN mkdir prepare-data

# Copy over necessary files from build images
# COPY ./server/sao_catalog ./server
COPY ./prepare-data/constellations ./prepare-data/constellations
COPY ./public/assets/favicon.ico ./public/assets/favicon.ico
COPY --from=build /usr/src/public/styles ./public/styles
COPY --from=build /usr/src/public/index.html ./public/index.html
COPY --from=build /usr/src/server/server.js ./server/server.js
COPY --from=build /usr/src/public/dist ./public/dist
COPY --from=night-math /usr/public/dist/wasm ./public/dist/wasm
COPY --from=prepare-data /usr/src/star_data.bin ./server/star_data.bin
COPY --from=prepare-data /usr/src/const_data.bin ./server/const_data.bin

COPY --from=build /usr/src/server/node_modules ./server/node_modules 

# RUN cd /usr/src/server

ENTRYPOINT [ "node", "/usr/src/server/server.js" ]
