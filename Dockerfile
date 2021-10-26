FROM alpine:3.13 AS zig
ARG ZIG_VERSION=0.9.0-dev.1444+e2a2e6c14
ARG ZIG_URL=https://ziglang.org/builds/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_SHA=c9a901c2df0661eede242a0860cddc30bbdb34d33f329ddae3e5cbdaed27306c

WORKDIR /usr/src

RUN apk add --no-cache curl \
    && curl -s -o zig.tar.xz ${ZIG_URL} \
    && echo "${ZIG_SHA} *zig.tar.xz" | sha256sum -c -

RUN mkdir -p /usr/local/bin/zig

RUN apk add --no-cache tar xz \
    && tar -Jxvf zig.tar.xz -C /usr/local/bin/zig

RUN rm zig.tar.xz

RUN mkdir -p /usr/src/bin

RUN chmod +x /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/zig
RUN cp -R /usr/local/bin/zig/zig-linux-x86_64-${ZIG_VERSION}/. /usr/src/bin/

FROM alpine:3.13 AS night-math

WORKDIR /usr/src

# Build WASM Module
COPY --from=zig /usr/src/bin /usr/src/bin
COPY ./night-math .

RUN /usr/src/bin/zig build -Drelease-small

# Prepare the star and constellation data
FROM alpine:3.13 AS prepare-data

WORKDIR /usr/src

COPY --from=zig /usr/src/bin /usr/src/bin

RUN mkdir -p prepare-data
COPY ./prepare-data .

RUN /usr/src/bin/zig build run -Drelease-fast -- star_data.bin const_data.bin 

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

ENTRYPOINT [ "node", "/usr/src/server/server.js" ]
