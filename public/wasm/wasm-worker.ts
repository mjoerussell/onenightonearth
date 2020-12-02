import { sizedCanvasPoint, sizeOf } from './size';
import { WasmInterface } from './wasm-interface';

let instance: WasmInterface;
let num_stars = 0;

const wasm_log = (msg_ptr: number, msg_len: number) => {
    const message = instance.getString(msg_ptr, msg_len);
    console.log(`[WASM] ${message}`);
};

onmessage = (event: MessageEvent) => {
    switch (event.data.type) {
        case 'init':
            {
                WebAssembly.instantiate(event.data.wasm_buffer, {
                    env: {
                        consoleLog: wasm_log,
                    },
                }).then(wasm_result => {
                    instance = new WasmInterface(wasm_result.instance);
                    num_stars = instance.initialize(event.data.stars);
                    postMessage({ type: 'init_complete' });
                });
            }
            break;
        case 'project_stars':
            {
                const { latitude, longitude, timestamp } = event.data;
                // Get cached pointers for result length and result points if they exist, otherwise allocate new ones
                const result_len_ptr = event.data.result_len_ptr ?? instance.allocBytes(4);
                const result_ptr = event.data.result_ptr ?? instance.allocBytes(num_stars * sizeOf(sizedCanvasPoint));
                if (event.data.result_ptr == null) {
                    console.warn('Allocated array for canvas points');
                }
                const canvas_points = instance.projectStars(latitude, longitude, timestamp, result_len_ptr, result_ptr);
                const message = {
                    type: 'draw_point_wasm',
                    points: canvas_points,
                    result_ptr,
                    result_len_ptr,
                };
                postMessage(message);
            }
            break;
        case 'find_waypoints':
            {
                const waypoints = instance.findWaypoints(event.data.start, event.data.end, 75);
                postMessage({
                    type: 'find_waypoints',
                    waypoints,
                });
            }
            break;
        case 'drag_and_move':
            {
                const coord = instance.dragAndMove(event.data.drag_start, event.data.drag_end);
                postMessage({
                    type: 'drag_and_move',
                    coord,
                });
            }
            break;
    }
};
