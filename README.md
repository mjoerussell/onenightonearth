# One Night on Earth

One Night on Earth is an interactive star map. This is not meant to be a scientific tool, it's simply a fun interactive experience.

One Night on Earth is written in Typescript and Zig.

[**onenightonearth.com**](https://onenightonearth.com)

## Controls

The controls currently available on the site are:

1. Change Date - Update the date that the sky is simulated for
2. Change Location - Enter a new latitude and/or longitude, then click 'Update Location' to move the simulation to the desired coordinates.
3. 'Use My Location' - Navigate to your current location.
4. 'Time Travel' - Click this button to start automatically advancing the date. Click again to stop.
5. Drag and Move - Click and drag on the map to move the sky. Your updated coordinates will be populated in the 'Latitude' and 'Longitude' fields.
6. Zoom - Scroll with your mouse while hovering over the map to zoom in/out.

## Running Locally

There are a few steps to get started:

**Pre-Requisites**

- Zig - See [Zig on GitHub](https://github.com/ziglang/zig) for more instructions.
- Node - See https://nodejs.org/en/download/

Run `zig build` to build the project, `zig build run` to build the project and start the server.

Now you're ready! Visit `localhost:8080` to view the site.
