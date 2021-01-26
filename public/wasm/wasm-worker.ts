import { WasmInterface } from './wasm-interface';

let instance: WasmInterface;

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
                    // instance.initialize(event.data.stars);
                    postMessage({ type: 'init_complete' });
                });
            }
            break;
        case 'project_stars':
            {
                // const { latitude, longitude, timestamp } = event.data;
                // // Get cached pointers for result length and result points if they exist, otherwise allocate new ones
                // const result_len_ptr = event.data.result_len_ptr ?? instance.allocBytes(4);
                // const pixel_data = instance.projectStars(latitude, longitude, timestamp, result_len_ptr);
                // if (pixel_data == null) {
                //     postMessage({
                //         type: 'error',
                //         during: 'projectStars',
                //     });
                // } else {
                //     postMessage({
                //         type: 'draw_point_wasm',
                //         points: pixel_data,
                //         result_len_ptr,
                //     });
                // }
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
        case 'update_settings':
            {
                // instance.setZoomFactor(event.data.zoom_factor);
                // instance.setDrawNorthUp(event.data.draw_north_up);
                postMessage({
                    type: 'update_settings',
                });
            }
            break;
    }
};
