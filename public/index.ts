import { Controls } from './controls';
import { Renderer } from './render';
import { Coord, Star } from './wasm/size';
import { WasmInterface } from './wasm/wasm-interface';

let controls: Controls;

let travel_button: HTMLButtonElement;

let renderer: Renderer;
let wasm_interface: WasmInterface;

// let current_latitude: number = 0;
// let current_longitude: number = 0;

const renderStars = (latitude: number, longitude: number, date?: Date) => {
    const render_date = date ?? controls.date;
    const timestamp = render_date.valueOf();

    if (renderer == null) {
        console.error('Could not get canvas context!');
        return;
    }

    if (renderer.settings_did_change) {
        console.log('Updating canvas settings');
        wasm_interface.updateSettings(renderer.getCanvasSettings());
    }

    wasm_interface.projectStars(latitude, longitude, BigInt(timestamp));
    const data = wasm_interface.getImageData();
    renderer.drawData(data);
    wasm_interface.resetImageData();
};

const drawUIElements = () => {
    const backgroundCanvas = document.getElementById('backdrop-canvas') as HTMLCanvasElement;
    const bgCtx = backgroundCanvas?.getContext('2d');

    const center_x = renderer.width / 2;
    const center_y = renderer.height / 2;

    if (bgCtx) {
        bgCtx.canvas.width = renderer.width;
        bgCtx.canvas.height = renderer.height;

        bgCtx.fillStyle = '#051430';
        bgCtx.arc(center_x, center_y, renderer.background_radius, 0, Math.PI * 2);
        bgCtx.fill();
    }
};

document.addEventListener('DOMContentLoaded', () => {
    controls = new Controls();
    renderer = new Renderer('star-canvas');

    controls.onDateChange(date => {
        renderStars(controls.latitude, controls.longitude);
    });

    travel_button = document.getElementById('timelapse') as HTMLButtonElement;

    fetch('/stars')
        .then(star_result => star_result.json())
        .then((stars: Star[]) =>
            WebAssembly.instantiateStreaming(fetch('./one-lib/zig-cache/lib/one-math.wasm'), {
                env: {
                    consoleLog: (msg_ptr: number, msg_len: number) => {
                        const message = wasm_interface.getString(msg_ptr, msg_len);
                        console.log(`[WASM] ${message}`);
                    },
                },
            })
                .then(wasm_result => {
                    wasm_interface = new WasmInterface(wasm_result.instance);
                    wasm_interface.initialize(stars, renderer.getCanvasSettings());

                    drawUIElements();
                    renderStars(controls.latitude, controls.longitude);
                })
                .catch(error => {
                    console.error('In WebAssembly Promise: ', error);
                })
        );

    // Handle updating the viewing location
    controls.onLocationUpdate(new_coord => {
        // If the longitude is exactly opposite of the original, then there's rendering issues
        // Introduce a slight offset to minimize this without significantly affecting end location
        if (new_coord.longitude === -controls.longitude) {
            new_coord.longitude += 0.05;
        }

        const start: Coord = { latitude: controls.latitude, longitude: controls.longitude };

        const waypoints = wasm_interface.findWaypoints(start, new_coord);
        if (waypoints == null || waypoints.length === 0) {
            renderStars(controls.latitude, controls.longitude);
            return;
        }

        let waypoint_index = 0;
        // @todo Update this loop so that all distances get traveled at the same speed,
        // not in the same amount of time
        const runWaypointTravel = () => {
            const waypoint = waypoints[waypoint_index];

            renderStars(waypoint.latitude, waypoint.longitude);
            waypoint_index += 1;
            if (waypoint_index < waypoints.length) {
                window.requestAnimationFrame(runWaypointTravel);
            }
        };
        window.requestAnimationFrame(runWaypointTravel);
    });

    controls.onTimelapse((current_date: Date) => {
        const days_per_frame = 0.33;
        const days_per_frame_millis = days_per_frame * 86400000;
        let next_date = new Date(current_date);
        next_date.setTime(next_date.getTime() + days_per_frame_millis);

        renderStars(controls.latitude, controls.longitude, next_date);
        return next_date;
    });

    const drag_state = {
        is_dragging: false,
        start_x: 0,
        start_y: 0,
    };

    renderer.addEventListener('mousedown', event => {
        const center_x = renderer.width / 2;
        const center_y = renderer.height / 2;
        drag_state.start_x = (event.offsetX - center_x) / renderer.canvas.width;
        drag_state.start_y = (event.offsetY - center_y) / renderer.canvas.height;

        renderer.canvas.classList.add('moving');

        drag_state.is_dragging = true;
    });

    renderer.addEventListener('mousemove', event => {
        if (!drag_state.is_dragging) return;
        const center_x = renderer.width / 2;
        const center_y = renderer.height / 2;
        const drag_end_x = (event.offsetX - center_x) / renderer.width;
        const drag_end_y = (event.offsetY - center_y) / renderer.height;

        // The new coordinate will be relative to the current latitude and longitude - it will be a lat/long
        // value that is measured with the current location as the origin.
        // This means that in order to calculate the actual next location, new_coord has to be added to current
        const new_coord = wasm_interface.dragAndMove(
            { latitude: drag_state.start_x, longitude: drag_state.start_y },
            { latitude: drag_end_x, longitude: drag_end_y }
        );

        // Add or subtract new_value from current_value depending on the orientation
        const directed_add = (current_value: number, new_value: number): number => {
            if (renderer.draw_north_up) {
                return current_value + new_value / renderer.zoom_factor;
            }
            return current_value - new_value / renderer.zoom_factor;
        };

        if (new_coord != null) {
            // The user crossed a pole if the new latitude is inside the bounds [-90, 90] but the new location
            // would be outside that range
            const crossed_pole =
                (controls.latitude < 90.0 && directed_add(controls.latitude, new_coord.latitude) > 90.0) ||
                (controls.latitude > -90.0 && directed_add(controls.latitude, new_coord.latitude) < -90.0);

            if (crossed_pole) {
                // Add 180 degrees to the longitude because crossing a pole in a straight line would bring you to the other side
                // of the world
                controls.longitude += 180.0;
                // Flip draw direction because if you were going south you're now going north and vice versa
                renderer.draw_north_up = !renderer.draw_north_up;
            }

            controls.latitude = directed_add(controls.latitude, new_coord.latitude);
            controls.longitude = directed_add(controls.longitude, -new_coord.longitude);

            // Keep the longitude value in the range [-180, 180]
            if (controls.longitude > 180.0) {
                controls.longitude -= 360.0;
            } else if (controls.longitude < -180.0) {
                controls.longitude += 360.0;
            }

            // Show the new location in the input boxes
            // latInput.value = current_latitude.toString();
            // longInput.value = current_longitude.toString();
        }

        // Reset the start positions to the current end positions for the next calculation
        drag_state.start_x = drag_end_x;
        drag_state.start_y = drag_end_y;

        renderStars(controls.latitude, controls.longitude);
    });

    renderer.addEventListener('mouseup', event => {
        renderer.canvas.classList.remove('moving');
        drag_state.is_dragging = false;
    });

    renderer.addEventListener('mouseleave', event => {
        renderer.canvas.classList.remove('moving');
        drag_state.is_dragging = false;
    });

    renderer.addEventListener('wheel', event => {
        // Zoom out faster than zooming in, because usually when you zoom out you just want
        // to go all the way out and it's annoying to have to do a ton of scrolling
        const delta_amount = event.deltaY < 0 ? 0.05 : 0.15;
        renderer.zoom_factor -= event.deltaY * delta_amount;
        // Don't let the user scroll out further than the default size
        if (renderer.zoom_factor < 1) renderer.zoom_factor = 1;
        // Re-render the stars
        renderStars(controls.latitude, controls.longitude);
    });
});
