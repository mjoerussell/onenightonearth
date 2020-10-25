import { Coord, ConstellationBranch, StarCoord, WasmInterface } from './wasm';

interface StarEntry extends StarCoord {
    magnitude: number;
    name: string;
    constellation: string | null;
    consId: string | null;
}

interface ConstellationEntry {
    name: string;
    branches: ConstellationBranch[];
}

const canvas_width = 700;
const canvas_height = 700;

const background_radius = 0.45 * Math.min(canvas_width, canvas_height);
const [center_x, center_y] = [canvas_width / 2, canvas_height / 2];

let date_input: HTMLInputElement;
let brightness_input: HTMLInputElement;
let constellations_on_input: HTMLInputElement;
let star_brightness = 0;
let zoom_factor = 1.0;
let travel_button: HTMLButtonElement;

let star_canvas: HTMLCanvasElement;
let star_canvas_ctx: CanvasRenderingContext2D | null;

let current_latitude: number = 0;
let current_longitude: number = 0;
let draw_north_up = true;

// let stars: StarEntry[];
let constellations: ConstellationEntry[];

let wasm_interface: WasmInterface;

const radToDeg = (radians: number): number => {
    return radians * 57.29577951308232;
};

const radToDegLong = (radians: number): number => {
    const degrees = radToDeg(radians);
    return degrees > 180.0 ? degrees - 360.0 : degrees;
};

const degToRad = (degrees: number): number => {
    return degrees * 0.017453292519943295;
};

const degToRadLong = (degrees: number): number => {
    const normDeg = degrees < 0 ? degrees + 360 : degrees;
    return normDeg * 0.017453292519943295;
};

const renderStars = (coord: Coord, date?: Date) => {
    if (!date) {
        if (date_input.valueAsDate) {
            date = date_input.valueAsDate;
        } else {
            return;
        }
    }

    const timestamp = date.valueOf();

    if (star_canvas_ctx == null) {
        console.error('Could not get canvas context!');
        return;
    }

    star_canvas_ctx.canvas.width = canvas_width;
    star_canvas_ctx.canvas.height = canvas_height;

    wasm_interface.projectStars(coord, timestamp);
};

const renderConstellations = (constellations: ConstellationEntry[], coord: Coord, date?: Date) => {
    if (!constellations_on_input.checked) return;
    if (star_canvas_ctx == null) return;

    if (!date) {
        if (date_input.valueAsDate) {
            date = date_input.valueAsDate;
        } else {
            return;
        }
    }

    // @todo This is just a first step for the constellations. This version is super slow, even with just 1 constellation
    // It needs to be optimized for passing a lot of data to wasm in 1 allocation
    for (const constellation of constellations) {
        wasm_interface.projectConstellationBranch(constellation.branches, coord, date.valueOf());
    }
};

const drawPointWasm = (x: number, y: number, brightness: number) => {
    const direction_modifier = draw_north_up ? 1 : -1;
    const pointX = center_x + direction_modifier * (background_radius * zoom_factor) * x;
    const pointY = center_y - direction_modifier * (background_radius * zoom_factor) * y;

    if (star_canvas_ctx != null) {
        star_canvas_ctx.fillStyle = `rgba(255, 246, 176, ${brightness / 3.5})`;
        star_canvas_ctx.fillRect(pointX, pointY, 2, 2);
    }
};

const drawLineWasm = (x1: number, y1: number, x2: number, y2: number) => {
    const direction_modifier = draw_north_up ? 1 : -1;
    const pointX1 = center_x + direction_modifier * (background_radius * zoom_factor) * x1;
    const pointY1 = center_y - direction_modifier * (background_radius * zoom_factor) * y1;
    const pointX2 = center_x + direction_modifier * (background_radius * zoom_factor) * x2;
    const pointY2 = center_y - direction_modifier * (background_radius * zoom_factor) * y2;

    if (star_canvas_ctx != null) {
        star_canvas_ctx.strokeStyle = 'rgb(255, 246, 176, 0.15)';
        star_canvas_ctx.beginPath();
        star_canvas_ctx.moveTo(pointX1, pointY1);
        star_canvas_ctx.lineTo(pointX2, pointY2);
        star_canvas_ctx.stroke();
    }
};

const drawUIElements = () => {
    const backgroundCanvas = document.getElementById('backdrop-canvas') as HTMLCanvasElement;
    const bgCtx = backgroundCanvas?.getContext('2d');

    const gridCanvas = document.getElementById('grid-canvas') as HTMLCanvasElement;
    const gridCtx = gridCanvas?.getContext('2d');

    if (bgCtx) {
        bgCtx.canvas.width = canvas_width;
        bgCtx.canvas.height = canvas_height;

        bgCtx.fillStyle = '#051430';

        // Draw background
        bgCtx.arc(center_x, center_y, background_radius, 0, Math.PI * 2);
        bgCtx.fill();
    }

    if (gridCtx) {
        gridCtx.canvas.width = canvas_width;
        gridCtx.canvas.height = canvas_height;

        gridCtx.fillStyle = '#6a818a55';
        gridCtx.strokeStyle = '#6a818a';
        gridCtx.arc(center_x, center_y, background_radius, 0, Math.PI * 2);
        gridCtx.lineWidth = 3;
        gridCtx.stroke();
    }
};

const getDaysInMillis = (days: number): number => days * 86400000;

const getDaysPerFrame = (daysPerSecond: number, frameTarget: number): number => {
    return daysPerSecond / frameTarget;
};

const wasm_log = (msg_ptr: number, msg_len: number) => {
    const message = wasm_interface.getString(msg_ptr, msg_len);
    console.log(`[WASM] ${message}`);
};

document.addEventListener('DOMContentLoaded', async () => {
    // Get handles for all the input elements
    date_input = document.getElementById('dateInput') as HTMLInputElement;
    date_input.addEventListener('change', () => {
        renderStars({ latitude: current_latitude, longitude: current_longitude });
        renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude });
    });
    travel_button = document.getElementById('timelapse') as HTMLButtonElement;

    star_canvas = document.getElementById('star-canvas') as HTMLCanvasElement;
    star_canvas_ctx = star_canvas.getContext('2d')!;

    brightness_input = document.getElementById('brightnessInput') as HTMLInputElement;
    brightness_input.addEventListener('change', () => {
        renderStars({ latitude: current_latitude, longitude: current_longitude });
        renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude });
    });

    constellations_on_input = document.getElementById('constellationsOn') as HTMLInputElement;
    constellations_on_input.addEventListener('click', () => {
        const coord: Coord = { latitude: current_latitude, longitude: current_longitude };
        renderConstellations(constellations, coord);
        renderStars(coord);
    });

    star_brightness = parseInt(brightness_input.value);

    const latInput = document.getElementById('latInput') as HTMLInputElement;
    const longInput = document.getElementById('longInput') as HTMLInputElement;
    const locationUpdateButton = document.getElementById('locationUpdate') as HTMLButtonElement;

    // Handle updating the viewing location
    locationUpdateButton.addEventListener('click', () => {
        const newLatitude = parseFloat(latInput.value);
        const newLongitude = parseFloat(longInput.value);

        if (newLatitude === current_latitude && newLongitude === current_longitude) {
            return;
        }

        const getDistance = (start: Coord, end: Coord): number => {
            const start_longitude = start.longitude < 0 ? start.longitude + 360.0 : start.longitude;
            const end_longitude = end.longitude < 0 ? end.longitude + 360.0 : end.longitude;
            const lat_diff = end.latitude - start.latitude;
            const long_diff = end_longitude - start_longitude;
            return Math.sqrt(Math.pow(lat_diff, 2) + Math.pow(long_diff, 2));
        };

        const start: Coord = {
            latitude: degToRad(current_latitude),
            longitude: degToRadLong(current_longitude),
        };

        const end: Coord = {
            latitude: degToRad(newLatitude),
            longitude: degToRadLong(newLongitude),
        };

        const coord_dist = getDistance(start, end);
        // 4000 = 4 seconds for the whole traversal
        const point_interval = 4000 / coord_dist;

        const waypoints = wasm_interface.getWaypoints(start, end).map(coord => {
            return {
                latitude: radToDeg(coord.latitude),
                longitude: radToDegLong(coord.longitude),
            };
        });

        let waypoint_index = 0;
        if (waypoints != null && waypoints.length > 0) {
            // @todo Update this loop so that all distances get traveled at the same speed,
            // not in the same amount of time
            const travelInterval = setInterval(() => {
                renderStars(waypoints[waypoint_index]);
                renderConstellations(constellations, waypoints[waypoint_index]);
                waypoint_index += 1;

                if (waypoint_index === waypoints.length) {
                    current_latitude = newLatitude;
                    current_longitude = newLongitude;

                    latInput.value = current_latitude.toString();
                    longInput.value = current_longitude.toString();
                    clearInterval(travelInterval);
                }
            }, 25);
        } else {
            current_latitude = newLatitude;
            current_longitude = newLongitude;

            latInput.value = current_latitude.toString();
            longInput.value = current_longitude.toString();

            renderStars({ latitude: current_latitude, longitude: current_longitude });
            renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude });
        }
    });

    // Handle time-travelling
    let travelIsOn = false;
    let travelInterval: number;
    const frame_target = 60;
    travel_button.addEventListener('click', async () => {
        if (travelIsOn && travelInterval != null) {
            travel_button.innerText = 'Time Travel';
            clearInterval(travelInterval);
        } else {
            travel_button.innerText = 'Stop';
            let date = date_input.valueAsDate ?? new Date();
            travelInterval = setInterval(() => {
                const currentDate = new Date(date);
                if (currentDate) {
                    const nextDate = new Date(currentDate);
                    nextDate.setTime(nextDate.getTime() + getDaysInMillis(getDaysPerFrame(20, frame_target)));
                    date_input.valueAsDate = new Date(nextDate);
                    renderStars({ latitude: current_latitude, longitude: current_longitude }, nextDate);
                    renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude }, nextDate);
                    date = nextDate;
                }
            }, 1000 / frame_target);
        }
        travelIsOn = !travelIsOn;
    });

    // const constellation_response = await fetch('/constellations');
    // constellations = await constellation_response.json();
    constellations = [];

    // Fetch and instantiate the WASM module
    WebAssembly.instantiateStreaming(fetch('./one-lib/zig-cache/lib/one-math.wasm'), {
        env: {
            consoleLog: wasm_log,
            drawPointWasm,
            drawLineWasm,
        },
    }).then(wasm_result => {
        wasm_interface = new WasmInterface(wasm_result.instance);

        wasm_interface.init();

        current_latitude = parseFloat(latInput.value);
        current_longitude = parseFloat(longInput.value);

        // Do the initial render
        drawUIElements();
        renderStars({ latitude: current_latitude, longitude: current_longitude });
        renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude });
    });

    let is_dragging = false;
    let [drag_start_x, drag_start_y] = [0, 0];

    star_canvas.addEventListener('mousedown', event => {
        drag_start_x = (event.offsetX - center_x) / star_canvas.width;
        drag_start_y = (event.offsetY - center_y) / star_canvas.height;

        star_canvas.classList.add('moving');

        is_dragging = true;
    });

    star_canvas.addEventListener('mousemove', event => {
        if (!is_dragging) return;
        const drag_end_x = (event.offsetX - center_x) / star_canvas.width;
        const drag_end_y = (event.offsetY - center_y) / star_canvas.height;

        // The new coordinate will be relative to the current latitude and longitude - it will be a lat/long
        // value that is measured with the current location as the origin.
        // This means that in order to calculate the actual next location, new_coord has to be added to current
        const new_coord = wasm_interface.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y);

        // Add or subtract new_value from current_value depending on the orientation
        const directed_add = (current_value: number, new_value: number): number => {
            if (draw_north_up) {
                return current_value + new_value / zoom_factor;
            }
            return current_value - new_value / zoom_factor;
        };

        // The user crossed a pole if the new latitude is inside the bounds [-90, 90] but the new location
        // would be outside that range
        const crossed_pole =
            (current_latitude < 90.0 && directed_add(current_latitude, new_coord.latitude) > 90.0) ||
            (current_latitude > -90.0 && directed_add(current_latitude, new_coord.latitude) < -90.0);

        if (crossed_pole) {
            // Add 180 degrees to the longitude because crossing a pole in a straight line would bring you to the other side
            // of the world
            current_longitude += 180.0;
            // Flip draw direction because if you were going south you're now going north and vice versa
            draw_north_up = !draw_north_up;
        }

        current_latitude = directed_add(current_latitude, new_coord.latitude);
        current_longitude = directed_add(current_longitude, -new_coord.longitude);

        // Keep the longitude value in the range [-180, 180]
        if (current_longitude > 180.0) {
            current_longitude -= 360.0;
        } else if (current_longitude < -180.0) {
            current_longitude += 360.0;
        }

        // Show the new location in the input boxes
        latInput.value = current_latitude.toString();
        longInput.value = current_longitude.toString();

        // Reset the start positions to the current end positions for the next calculation
        drag_start_x = drag_end_x;
        drag_start_y = drag_end_y;

        renderStars({ latitude: current_latitude, longitude: current_longitude });
        renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude });
    });

    star_canvas.addEventListener('mouseup', event => {
        star_canvas.classList.remove('moving');
        is_dragging = false;
    });

    star_canvas.addEventListener('mouseleave', event => {
        star_canvas.classList.remove('moving');
        is_dragging = false;
    });

    star_canvas.addEventListener('wheel', event => {
        // Zoom out faster than zooming in, because usually when you zoom out you just want
        // to go all the way out and it's annoying to have to do a ton of scrolling
        const delta_amount = event.deltaY < 0 ? 0.05 : 0.15;
        zoom_factor -= event.deltaY * delta_amount;
        // Don't let the user scroll out further than the default size
        if (zoom_factor < 1) zoom_factor = 1;
        // Re-render the stars
        renderStars({ latitude: current_latitude, longitude: current_longitude });
        renderConstellations(constellations, { latitude: current_latitude, longitude: current_longitude });
    });
});
