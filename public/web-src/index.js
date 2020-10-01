import { WasmInterface } from './wasm.js';
const canvasWidth = 700;
const canvasHeight = 700;
const backgroundRadius = 0.45 * Math.min(canvasWidth, canvasHeight);
const [centerX, centerY] = [canvasWidth / 2, canvasHeight / 2];
let dateInput;
let brightnessInput;
let star_brightness = 0;
let travelButton;
let starCanvas;
let starCanvasCtx;
let currentLatitude = 0;
let currentLongitude = 0;
let stars;
let wasm_instance;
let wasm_interface;
const radToDeg = (radians) => {
    return radians * 57.29577951308232;
};
const radToDegLong = (radians) => {
    const degrees = radToDeg(radians);
    return degrees > 180.0 ? degrees - 360.0 : degrees;
};
const degToRad = (degrees) => {
    return degrees * 0.017453292519943295;
};
const degToRadLong = (degrees) => {
    const normDeg = degrees < 0 ? degrees + 360 : degrees;
    return normDeg * 0.017453292519943295;
};
const renderStars = (stars, coord, date) => {
    if (!date) {
        if (dateInput.valueAsDate) {
            date = dateInput.valueAsDate;
        }
        else {
            return;
        }
    }
    const stars_simple = stars.map(s => {
        return {
            rightAscension: s.rightAscension,
            declination: s.declination,
            brightness: s.magnitude,
        };
    });
    const timestamp = date.valueOf();
    const brightness = parseFloat(brightnessInput.value);
    if (starCanvasCtx == null) {
        console.error('Could not get canvas context!');
        return;
    }
    starCanvasCtx.canvas.width = canvasWidth;
    starCanvasCtx.canvas.height = canvasHeight;
    wasm_interface.projectStars(stars_simple, coord, timestamp);
};
const drawPointWasm = (x, y, brightness) => {
    const pointX = centerX + backgroundRadius * x;
    const pointY = centerY - backgroundRadius * y;
    if (starCanvasCtx != null) {
        starCanvasCtx.fillStyle = `rgba(255, 246, 176, ${brightness + star_brightness})`;
        starCanvasCtx.fillRect(pointX, pointY, 2, 2);
    }
};
const drawUIElements = () => {
    const backgroundCanvas = document.getElementById('backdrop-canvas');
    const bgCtx = backgroundCanvas === null || backgroundCanvas === void 0 ? void 0 : backgroundCanvas.getContext('2d');
    const gridCanvas = document.getElementById('grid-canvas');
    const gridCtx = gridCanvas === null || gridCanvas === void 0 ? void 0 : gridCanvas.getContext('2d');
    if (bgCtx) {
        bgCtx.canvas.width = canvasWidth;
        bgCtx.canvas.height = canvasHeight;
        bgCtx.fillStyle = '#07102b';
        // Draw background
        bgCtx.arc(centerX, centerY, backgroundRadius, 0, Math.PI * 2);
        bgCtx.fill();
    }
    if (gridCtx) {
        gridCtx.canvas.width = canvasWidth;
        gridCtx.canvas.height = canvasHeight;
        gridCtx.fillStyle = '#6a818a55';
        gridCtx.strokeStyle = '#6a818a';
        gridCtx.arc(centerX, centerY, backgroundRadius, 0, Math.PI * 2);
        gridCtx.lineWidth = 3;
        gridCtx.stroke();
        // Draw altitude markers
        // const markerAltitudes = [0.39269908169872414, 0.7853981633974483, 1.1780972450961724];
        // const aziStep = (2 * Math.PI) / 2500;
        // for (const alt of markerAltitudes) {
        //     let azi = 0;
        //     while (azi <= 2 * Math.PI) {
        //         const point = wasm_interface.projectCoord(alt, azi);
        //         const pointX = centerX + backgroundRadius * point.x;
        //         const pointY = centerY - backgroundRadius * point.y;
        //         gridCtx.fillRect(pointX, pointY, 1, 1);
        //         azi += aziStep;
        //     }
        // }
        // // Draw azimuth markers
        // const markerAzis = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(i => i * ((2 * Math.PI) / 12));
        // const altStep = Math.PI / 2 / 500;
        // for (const azi of markerAzis) {
        //     let alt = 0;
        //     while (alt <= Math.PI / 2) {
        //         const point = wasm_interface.projectCoord(alt, azi);
        //         const pointX = centerX + backgroundRadius * point.x;
        //         const pointY = centerY - backgroundRadius * point.y;
        //         gridCtx.fillRect(pointX, pointY, 1, 1);
        //         alt += altStep;
        //     }
        // }
    }
};
const getDaysInMillis = (days) => days * 86400000;
const getDaysPerFrame = (daysPerSecond, frameTarget) => {
    return daysPerSecond / frameTarget;
};
const wasm_log = (msg_ptr, msg_len) => {
    const message = wasm_interface.getString(msg_ptr, msg_len);
    console.log(`[WASM] ${message}`);
};
document.addEventListener('DOMContentLoaded', async () => {
    // Get handles for all the input elements
    dateInput = document.getElementById('dateInput');
    brightnessInput = document.getElementById('brightnessInput');
    star_brightness = parseInt(brightnessInput.value);
    travelButton = document.getElementById('timelapse');
    starCanvas = document.getElementById('star-canvas');
    starCanvasCtx = starCanvas.getContext('2d');
    const latInput = document.getElementById('latInput');
    const longInput = document.getElementById('longInput');
    const locationUpdateButton = document.getElementById('locationUpdate');
    // Re-render stars when changing the date or brightness
    dateInput.addEventListener('change', () => renderStars(stars, { latitude: currentLatitude, longitude: currentLongitude }));
    brightnessInput.addEventListener('change', () => renderStars(stars, { latitude: currentLatitude, longitude: currentLongitude }));
    // Handle updating the viewing location
    locationUpdateButton.addEventListener('click', () => {
        const newLatitude = parseFloat(latInput.value);
        const newLongitude = parseFloat(longInput.value);
        if (newLatitude === currentLatitude && newLongitude === currentLongitude) {
            return;
        }
        const start = {
            latitude: degToRad(currentLatitude),
            longitude: degToRadLong(currentLongitude),
        };
        const end = {
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
                    currentLatitude = newLatitude;
                    currentLongitude = newLongitude;
                    latInput.value = currentLatitude.toString();
                    longInput.value = currentLongitude.toString();
                    clearInterval(travelInterval);
                }
            }, 25);
        }
        else {
            currentLatitude = newLatitude;
            currentLongitude = newLongitude;
            latInput.value = currentLatitude.toString();
            longInput.value = currentLongitude.toString();
            renderStars(stars, { latitude: currentLatitude, longitude: currentLongitude });
        }
    });
    // Handle time-travelling
    let travelIsOn = false;
    let travelInterval;
    const frameTarget = 60;
    travelButton.addEventListener('click', async () => {
        var _a;
        if (travelIsOn && travelInterval != null) {
            clearInterval(travelInterval);
        }
        else {
            let date = (_a = dateInput.valueAsDate) !== null && _a !== void 0 ? _a : new Date();
            travelInterval = setInterval(() => {
                const currentDate = new Date(date);
                if (currentDate) {
                    const nextDate = new Date(currentDate);
                    nextDate.setTime(nextDate.getTime() + getDaysInMillis(getDaysPerFrame(12, frameTarget)));
                    dateInput.valueAsDate = new Date(nextDate);
                    renderStars(stars, { latitude: currentLatitude, longitude: currentLongitude }, nextDate);
                    date = nextDate;
                }
            }, 1000 / frameTarget);
        }
        travelIsOn = !travelIsOn;
    });
    const star_response = await fetch('/stars');
    stars = await star_response.json();
    // Fetch and instantiate the WASM module
    const wasm_result = await WebAssembly.instantiateStreaming(fetch('./one-lib/zig-cache/lib/one-math.wasm'), {
        env: {
            consoleLog: wasm_log,
            drawPointWasm,
        },
    });
    wasm_instance = wasm_result.instance;
    wasm_interface = new WasmInterface(wasm_instance);
    currentLatitude = parseFloat(latInput.value);
    currentLongitude = parseFloat(longInput.value);
    // Do the initial render
    drawUIElements();
    renderStars(stars, { latitude: currentLatitude, longitude: currentLongitude });
    // @note This is just a test of the drag-and-travel feature
    // One thing about this version is that you're not really dragging the sky, you're dragging the world
    // underneath you. This isn't super disorienting and often feels almost right, but it still leads
    // to some unexpected results. The worst part imo is that the apparent drag direction changes based
    // on what part of the world you're in.
    //
    // Future versions of this should switch to a system where it gets the point in the sky corresponding
    // to the location dragged to, and then translates that back to lat & long before re-rendering.
    const canvas = document.getElementById('star-canvas');
    let is_dragging = false;
    let [drag_start_x, drag_start_y] = [0, 0];
    canvas.addEventListener('mousedown', event => {
        drag_start_x = event.offsetX;
        drag_start_y = event.offsetY;
        canvas.classList.add('moving');
        is_dragging = true;
    });
    canvas.addEventListener('mousemove', event => {
        if (is_dragging) {
            const drag_end_x = event.offsetX;
            const drag_end_y = event.offsetY;
            const dist_x = (drag_end_x - drag_start_x) * 0.4;
            const dist_y = (drag_end_y - drag_start_y) * 0.4;
            currentLatitude += dist_y;
            currentLongitude -= dist_x;
            if (currentLongitude > 180.0) {
                currentLongitude -= 360.0;
            }
            else if (currentLongitude < -180.0) {
                currentLongitude += 360.0;
            }
            latInput.value = currentLatitude.toString();
            longInput.value = currentLongitude.toString();
            drag_start_x = drag_end_x;
            drag_start_y = drag_end_y;
            renderStars(stars, { latitude: currentLatitude, longitude: currentLongitude });
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
//# sourceMappingURL=index.js.map