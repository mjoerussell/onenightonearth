###############################
# This layer is for downloading and installing the specified version
# of zig. Other layers can copy the binary from it
###############################

FROM alpine:3.13 AS zig
ARG ZIG_VERSION=0.10.0-dev.555+1b6a1e691
ARG ZIG_URL=https://ziglang.org/builds/zig-linux-x86_64-${ZIG_VERSION}.tar.xz
ARG ZIG_SHA=342ae034706d1a43de968414264896df710d45ecbf6058b2f16de7206d290eca

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

####################################
# This layer is for building the WASM night-math library
####################################

FROM alpine:3.13 AS night-math

WORKDIR /usr/src

# Build WASM Module
COPY --from=zig /usr/src/bin /usr/src/bin
COPY ./night-math .

RUN /usr/src/bin/zig build -Drelease-fast

#####################################
# Prepare the star and constellation data
#####################################

FROM alpine:3.13 AS prepare-data

WORKDIR /usr/src

COPY --from=zig /usr/src/bin /usr/src/bin

RUN mkdir -p prepare-data
COPY ./prepare-data .

RUN /usr/src/bin/zig build run -Drelease-fast -- star_data.bin const_data.bin const_meta.json

#####################################
# Build the server
#####################################

FROM alpine:3.13 AS build-server

WORKDIR /usr/src

COPY --from=zig /usr/src/bin /usr/src/bin

COPY ./zig-server .

RUN /usr/src/bin/zig build -Drelease-fast

##################################################
# Build the static files for the site
##################################################

FROM node:15-alpine AS build-web  

WORKDIR /usr/src

COPY ./tsconfig.base.json .

WORKDIR /usr/src/web

COPY ./web/package*.json .
RUN npm install

COPY ./web .
RUN npm run build

#############################################
# Combine all the assets from the previous layers and
# provide an entrypoint that starts the server
#############################################

FROM node:15-alpine

WORKDIR /usr/src

RUN mkdir web
RUN mkdir server

# Copy over necessary files from build images
COPY ./web/assets/favicon.ico ./web/assets/favicon.ico

COPY --from=build-web /usr/src/web/styles ./web/styles
COPY --from=build-web /usr/src/web/index.html ./web/index.html
COPY --from=build-web /usr/src/web/dist ./web/dist

COPY --from=build-server /usr/src/zig-out/bin/zig-server /usr/src/server

COPY --from=night-math /usr/web/dist/wasm ./web/dist/wasm

COPY --from=prepare-data /usr/src/const_meta.json ./server/const_meta.json
COPY --from=prepare-data /usr/src/star_data.bin ./server/star_data.bin
COPY --from=prepare-data /usr/src/const_data.bin ./server/const_data.bin

WORKDIR /usr/src/server

ENTRYPOINT [ "./zig-server" ]
