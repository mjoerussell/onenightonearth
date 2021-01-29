# One Night on Earth

One Night on Earth is an interactive star map. This is not meant to be a scientific tool, it's simply a fun interactive experience.

One Night on Earth is written in Typescript and Zig.

[**onenightonearth.com**](https://onenightonearth.com)

> Note: Currently appears to run best in Firefox, some issues have been seen in Chrome which are currently being worked on.

## Running Locally

### Docker

The easiest way to run locally is to build and run the included `Dockerfile`. Simply run the command

```
docker build . -t one-night
docker run -p 8080:8080 -d one-night
```

> Note: You can replace `one-night` with anything you want

Then visit `localhost:8080` in your browser.

### Without Docker

If you don't have Docker, or would rather run the app directly, there's a few steps to get started:

**Prerequisites**

- Zig - See [Zig on GitHub](https://github.com/ziglang/zig) for more instructions.
- Node - See https://nodejs.org/en/download/

**On First Run Only:**

1. Run `cd public && npm install`
2. Run `cp server && npm install`

**Each Run:**

1. In one terminal, run `cd server && npm start`.
2. In another terminal, run `cd public && npm run build`. Do this every time you want to view changes you've made to the frontend code.
3. In the same terminal from 2. (or a different one if you prefer, doesn't really matter) run `cd public/one-lib && zig build`. Do this
   every time you want to make changes to the WASM code.

Now you're ready! Like before, visit `localhost:8080` to view the site.

## Controls

The controls currently available on the site are:

1. Change Date - Update the date that the sky is simulated for
2. Change Location - Enter a new latitude and/or longitude, then click 'Update Location' to move the simulation to the desired coordinates.
3. 'Time Travel' - Click this button to start automatically advancing the date. Click again to stop.
4. Drag and Move - Click and drag on the map to move the sky. Your updated coordinates will be populated in the 'Latitude' and 'Longitude' fields.
5. Zoom - Scroll with your mouse while hovering over the map to zoom in/out.
