import { Star, Coord, WasmInterface } from './wasm.js';

interface StarEntry {
    rightAscension: number;
    declination: number;
    magnitude: number;
    name: string;
}

const canvas_width = 700;
const canvas_height = 700;

const background_radius = 0.45 * Math.min(canvas_width, canvas_height);
const [center_x, center_y] = [canvas_width / 2, canvas_height / 2];

let date_input: HTMLInputElement;
let brightness_input: HTMLInputElement;
let star_brightness = 0;
let travel_button: HTMLButtonElement;

let star_canvas: HTMLCanvasElement;
let star_canvas_ctx: CanvasRenderingContext2D | null;

let current_latitude: number = 0;
let current_longitude: number = 0;
let draw_north_up = true;

let stars: StarEntry[];

let wasm_instance: WebAssembly.Instance;
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

const renderStars = (stars: StarEntry[], coord: Coord, date?: Date) => {
    if (!date) {
        if (date_input.valueAsDate) {
            date = date_input.valueAsDate;
        } else {
            return;
        }
    }

    const stars_simple: Star[] = stars.map(s => {
        return {
            rightAscension: s.rightAscension,
            declination: s.declination,
            brightness: s.magnitude,
        };
    });

    const timestamp = date.valueOf();

    // const brightness = parseFloat(brightnessInput.value);

    if (star_canvas_ctx == null) {
        console.error('Could not get canvas context!');
        return;
    }

    star_canvas_ctx.canvas.width = canvas_width;
    star_canvas_ctx.canvas.height = canvas_height;

    wasm_interface.projectStars(stars_simple, coord, timestamp);
};

const drawPointWasm = (x: number, y: number, brightness: number) => {
    const direction_modifier = draw_north_up ? 1 : -1;
    const pointX = center_x + direction_modifier * background_radius * x;
    const pointY = center_y - direction_modifier * background_radius * y;

    if (star_canvas_ctx != null) {
        star_canvas_ctx.fillStyle = `rgba(255, 246, 176, ${brightness + star_brightness})`;
        star_canvas_ctx.fillRect(pointX, pointY, 2, 2);
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

        bgCtx.fillStyle = '#07102b';

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

    brightness_input = document.getElementById('brightnessInput') as HTMLInputElement;
    star_brightness = parseInt(brightness_input.value);

    travel_button = document.getElementById('timelapse') as HTMLButtonElement;
    star_canvas = document.getElementById('star-canvas') as HTMLCanvasElement;

    star_canvas_ctx = star_canvas.getContext('2d')!;

    const latInput = document.getElementById('latInput') as HTMLInputElement;
    const longInput = document.getElementById('longInput') as HTMLInputElement;
    const locationUpdateButton = document.getElementById('locationUpdate') as HTMLButtonElement;

    // Re-render stars when changing the date or brightness
    date_input.addEventListener('change', () => renderStars(stars, { latitude: current_latitude, longitude: current_longitude }));
    brightness_input.addEventListener('change', () => renderStars(stars, { latitude: current_latitude, longitude: current_longitude }));

    // Handle updating the viewing location
    locationUpdateButton.addEventListener('click', () => {
        const newLatitude = parseFloat(latInput.value);
        const newLongitude = parseFloat(longInput.value);

        if (newLatitude === current_latitude && newLongitude === current_longitude) {
            return;
        }

        const start: Coord = {
            latitude: degToRad(current_latitude),
            longitude: degToRadLong(current_longitude),
        };

        const end: Coord = {
            latitude: degToRad(newLatitude),
            longitude: degToRadLong(newLongitude),
        };

        const waypoints = wasm_interface.getWaypoints(start, end).map(coord => {
            return {
                latitude: radToDeg(coord.latitude),
                longitude: radToDegLong(coord.longitude),
            };
        });

        let waypointIndex = 0;
        if (waypoints != null && waypoints.length > 0) {
            // @todo Update this loop so that all distances get traveled at the same speed,
            // not in the same amount of time
            const travelInterval = setInterval(() => {
                renderStars(stars, waypoints[waypointIndex]);
                waypointIndex += 1;

                if (waypointIndex === waypoints.length) {
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

            renderStars(stars, { latitude: current_latitude, longitude: current_longitude });
        }
    });

    // Handle time-travelling
    let travelIsOn = false;
    let travelInterval: number;
    const frameTarget = 60;
    travel_button.addEventListener('click', async () => {
        if (travelIsOn && travelInterval != null) {
            clearInterval(travelInterval);
        } else {
            let date = date_input.valueAsDate ?? new Date();
            travelInterval = setInterval(() => {
                const currentDate = new Date(date);
                if (currentDate) {
                    const nextDate = new Date(currentDate);
                    nextDate.setTime(nextDate.getTime() + getDaysInMillis(getDaysPerFrame(12, frameTarget)));
                    date_input.valueAsDate = new Date(nextDate);
                    renderStars(stars, { latitude: current_latitude, longitude: current_longitude }, nextDate);
                    date = nextDate;
                }
            }, 1000 / frameTarget);
        }
        travelIsOn = !travelIsOn;
    });

    const star_response = await fetch('/stars');
    stars = await star_response.json();

    // Fetch and instantiate the WASM module
    WebAssembly.instantiateStreaming(fetch('./one-lib/zig-cache/lib/one-math.wasm'), {
        env: {
            consoleLog: wasm_log,
            drawPointWasm,
        },
    }).then(wasm_result => {
        wasm_instance = wasm_result.instance;
        wasm_interface = new WasmInterface(wasm_instance);

        current_latitude = parseFloat(latInput.value);
        current_longitude = parseFloat(longInput.value);

        // Do the initial render
        drawUIElements();
        renderStars(stars, { latitude: current_latitude, longitude: current_longitude });
    });

    const canvas = document.getElementById('star-canvas') as HTMLCanvasElement;
    let is_dragging = false;
    let [drag_start_x, drag_start_y] = [0, 0];

    canvas.addEventListener('mousedown', event => {
        drag_start_x = (event.offsetX - center_x) / canvas.width;
        drag_start_y = (event.offsetY - center_y) / canvas.height;

        canvas.classList.add('moving');

        is_dragging = true;
    });

    canvas.addEventListener('mousemove', event => {
        if (is_dragging) {
            const drag_end_x = (event.offsetX - center_x) / canvas.width;
            const drag_end_y = (event.offsetY - center_y) / canvas.height;

            const new_coord = wasm_interface.dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y);

            const directed_add = (current_value: number, new_value: number): number => {
                if (draw_north_up) {
                    return current_value + new_value;
                }
                return current_value - new_value;
            };

            const crossed_pole =
                (current_latitude < 90.0 && directed_add(current_latitude, new_coord.latitude) > 90.0) ||
                (current_latitude > -90.0 && directed_add(current_latitude, new_coord.latitude) < -90.0);

            if (crossed_pole) {
                current_longitude += 180.0;
                draw_north_up = !draw_north_up;
            }

            current_latitude = directed_add(current_latitude, new_coord.latitude);
            current_longitude = directed_add(current_longitude, -new_coord.longitude);

            if (current_longitude > 180.0) {
                current_longitude -= 360.0;
            } else if (current_longitude < -180.0) {
                current_longitude += 360.0;
            }

            latInput.value = current_latitude.toString();
            longInput.value = current_longitude.toString();

            drag_start_x = drag_end_x;
            drag_start_y = drag_end_y;

            renderStars(stars, { latitude: current_latitude, longitude: current_longitude });
        }
    });

    canvas.addEventListener('mouseup', event => {
        canvas.classList.remove('moving');
        is_dragging = false;
    });

    canvas.addEventListener('mouseleave', event => {
        canvas.classList.remove('moving');
        is_dragging = false;
    });
});
