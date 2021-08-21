import { Controls } from './controls';
import { Constellation, Coord, Star } from './wasm/size';
import { WasmInterface } from './wasm/wasm-interface';

let constellations: Constellation[] = [];
let wasm_interface: WasmInterface;

const renderStars = (controls: Controls, date?: Date) => {
    const render_date = date ?? controls.date;
    const timestamp = render_date.valueOf();

    if (controls.renderer == null) {
        console.error('Could not get canvas context!');
        return;
    }

    if (controls.renderer.settings_did_change) {
        wasm_interface.updateSettings(controls.renderer.getCanvasSettings());
    }

    wasm_interface.projectStars(controls.latitude, controls.longitude, BigInt(timestamp));
    wasm_interface.projectConstellationGrids(controls.latitude, controls.longitude, BigInt(timestamp));
    const data = wasm_interface.getImageData();
    controls.renderer.drawData(data);
    wasm_interface.resetImageData();
};

const drawUIElements = (controls: Controls) => {
    const backgroundCanvas = document.getElementById('backdrop-canvas') as HTMLCanvasElement;
    const bgCtx = backgroundCanvas?.getContext('2d');

    const center_x = controls.renderer.width / 2;
    const center_y = controls.renderer.height / 2;

    if (bgCtx) {
        bgCtx.canvas.width = controls.renderer.width;
        bgCtx.canvas.height = controls.renderer.height;

        bgCtx.fillStyle = '#030b1c';
        bgCtx.arc(center_x, center_y, controls.renderer.background_radius, 0, Math.PI * 2);
        bgCtx.fill();
    }
};

document.addEventListener('DOMContentLoaded', () => {
    const controls = new Controls();
    controls.date = new Date();

    WebAssembly.instantiateStreaming(fetch('./one-lib/zig-out/lib/one-math.wasm'), {
        env: {
            consoleLog: (msg_ptr: number, msg_len: number) => {
                const message = wasm_interface.getString(msg_ptr, msg_len);
                console.log(`[WASM] ${message}`);
            },
            consoleWarn: (msg_ptr: number, msg_len: number) => {
                const message = wasm_interface.getString(msg_ptr, msg_len);
                console.warn(`[WASM] ${message}`);
            },
            consoleError: (msg_ptr: number, msg_len: number) => {
                const message = wasm_interface.getString(msg_ptr, msg_len);
                console.error(`[WASM] ${message}`);
            },
        },
    }).then(wasm_result =>
        fetch('/stars')
            .then(star_result => star_result.json())
            .then((stars: Star[]) =>
                fetch('/constellations')
                    .then(const_result => const_result.json())
                    .then((consts: Constellation[]) => {
                        constellations = consts;
                        controls.setConstellations(constellations);
                        wasm_interface = new WasmInterface(wasm_result.instance);
                        wasm_interface.initialize(stars, constellations, controls.renderer.getCanvasSettings());

                        drawUIElements(controls);
                        renderStars(controls);
                    })
            )
            .catch(error => {
                console.error('In WebAssembly Promise: ', error);
            })
    );

    controls.onDateChange(date => {
        renderStars(controls);
    });

    controls.onChangeConstellationView(() => {
        renderStars(controls);
    });

    controls.onSetToday((current, target) => {
        const days_per_frame = 2;
        const days_per_frame_millis = days_per_frame * 86400000;

        let next_date = new Date(current);
        let diff = Math.abs(current.valueOf() - target.valueOf());
        const delta = diff > days_per_frame_millis ? days_per_frame_millis : diff;
        if (current > target) {
            next_date.setTime(next_date.getTime() - delta);
        } else {
            next_date.setTime(next_date.getTime() + delta);
        }

        renderStars(controls, next_date);
        return next_date;
    });

    const updateLocation = (new_coord: Coord, end_zoom_factor: number): void => {
        // If the longitude is exactly opposite of the original, then there will be issues calculating the
        // great circle, and the journey will look really weird.
        // Introduce a slight offset to minimize this without significantly affecting end location
        if (new_coord.longitude === -controls.longitude) {
            new_coord.longitude += 0.05;
        }

        const start: Coord = { latitude: controls.latitude, longitude: controls.longitude };

        const waypoints = wasm_interface.findWaypoints(start, new_coord);
        if (waypoints == null || waypoints.length === 0) {
            renderStars(controls);
            return;
        }

        let zoom_step = 0;
        if (controls.renderer.zoom_factor !== end_zoom_factor) {
            const zoom_diff = end_zoom_factor - controls.renderer.zoom_factor;
            zoom_step = zoom_diff / waypoints.length;
        }

        let waypoint_index = 0;
        const runWaypointTravel = () => {
            const waypoint = waypoints[waypoint_index];
            controls.latitude = waypoint.latitude;
            controls.longitude = waypoint.longitude;
            controls.renderer.zoom_factor += zoom_step;
            renderStars(controls);
            waypoint_index += 1;
            if (waypoint_index < waypoints.length) {
                window.requestAnimationFrame(runWaypointTravel);
            }
        };
        window.requestAnimationFrame(runWaypointTravel);
    };

    controls.onLocationUpdate(new_coord => updateLocation(new_coord, controls.renderer.zoom_factor));
    controls.onUseCurrentPosition(new_coord => updateLocation(new_coord, 1));

    controls.onTimelapse(current_date => {
        const days_per_frame = 0.15;
        const days_per_frame_millis = days_per_frame * 86400000;
        let next_date = new Date(current_date);
        next_date.setTime(next_date.getTime() + days_per_frame_millis);

        renderStars(controls, next_date);
        return next_date;
    });

    controls.onMapDrag((current_state, new_state) => {
        const new_coord = wasm_interface.dragAndMove(
            { latitude: current_state.x, longitude: current_state.y },
            { latitude: new_state.x, longitude: new_state.y }
        );

        // Add or subtract new_value from current_value depending on the orientation
        const directed_add = (current_value: number, new_value: number): number => {
            if (controls.renderer.draw_north_up) {
                return current_value + new_value / controls.renderer.zoom_factor;
            }
            return current_value - new_value / controls.renderer.zoom_factor;
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
                controls.renderer.draw_north_up = !controls.renderer.draw_north_up;
            }

            controls.latitude = directed_add(controls.latitude, new_coord.latitude);
            controls.longitude = directed_add(controls.longitude, -new_coord.longitude);

            // Keep the longitude value in the range [-180, 180]
            if (controls.longitude > 180.0) {
                controls.longitude -= 360.0;
            } else if (controls.longitude < -180.0) {
                controls.longitude += 360.0;
            }
        }

        window.requestAnimationFrame(() => renderStars(controls));
    });

    controls.onMapZoom(zoom_factor => {
        controls.renderer.zoom_factor = zoom_factor;
        renderStars(controls);
    });

    controls.onMapHover(point => {
        if (controls.renderer.draw_asterisms || controls.renderer.draw_constellation_grid) {
            const index = wasm_interface.getConstellationAtPoint(
                point,
                controls.latitude,
                controls.longitude,
                BigInt(controls.date.valueOf())
            );
            const data = wasm_interface.getImageData();
            controls.renderer.drawData(data);
            renderStars(controls);
            if (index >= 0) {
                controls.constellation_name = `${constellations[index].name} - ${constellations[index].epithet}`;
            }
        }
    });

    controls.onMapDoubleClick(point => {
        const new_coord = wasm_interface.getCoordForCanvasPoint(
            point,
            controls.latitude,
            controls.longitude,
            BigInt(controls.date.valueOf())
        );
        if (new_coord != null) {
            updateLocation(new_coord, 2.5);
        }
    });

    controls.onSelectConstellation(const_index => {
        controls.constellation_name = `${constellations[const_index].name} - ${constellations[const_index].epithet}`;
        const constellation_center = wasm_interface.getCosntellationCentroid(const_index);
        if (constellation_center) {
            const new_coord = wasm_interface.getCoordForSkyCoord(constellation_center, BigInt(controls.date.valueOf()));
            if (new_coord) {
                updateLocation(new_coord, 2.5);
            }
        }
    });
});
