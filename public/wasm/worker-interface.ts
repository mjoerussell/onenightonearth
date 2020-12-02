import { Coord, ConstellationBranch } from './size';

export interface WasmEnv {
    [func_name: string]: (...args: any[]) => any;
}

interface WorkerHandle {
    worker: Worker;
    processing: boolean;
    saved_data: any;
}

/**
 * A wrapper class used for the main code to interact with WebAssembly code. This class uses WebWorkers
 * to achieve multi-threaded rendering operations, when appropriate.
 */
export class WorkerInterface {
    private workers: WorkerHandle[] = [];

    constructor(private num_workers: number = 4) {}

    /**
     * Initialize the workers. This promise will resolve when all of the workers have finished their initialization process,
     * which involves compiling a WASM module and running its initialization code.
     * @param env
     */
    init(env: WasmEnv): Promise<void> {
        let num_complete = 0;
        // Get the star data from the server
        const star_promise: Promise<string[]> = fetch('/stars').then(star_result => star_result.json());
        // Get the WASM code from the server
        const wasm_promise = fetch('./one-lib/zig-cache/lib/one-math.wasm').then(response => response.arrayBuffer());

        return new Promise((resolve, reject) => {
            Promise.all([star_promise, wasm_promise]).then(([stars, wasm_buffer]) => {
                const range_size = Math.floor(stars.length / this.num_workers);
                for (let i = 0; i < this.num_workers; i++) {
                    const worker = new Worker('./dist/worker.js');
                    const start_index = range_size * i;
                    const end_index = i === this.num_workers - 1 ? stars.length : start_index + range_size;
                    const worker_star_data = stars.slice(start_index, end_index).join('\n');
                    // Add the new worker to the list of workers
                    this.workers.push({
                        worker,
                        processing: false,
                        saved_data: {},
                    });

                    // Receive the worker's messages
                    worker.onmessage = message => {
                        if (message.data.type === 'init_complete') {
                            num_complete += 1;
                            if (num_complete === this.num_workers) {
                                console.log('Finished initializing');
                                resolve();
                            }
                        } else if (message.data.type === 'draw_point_wasm') {
                            env.drawPoints(message.data.points);
                            this.workers[i].processing = false;
                            this.workers[i].saved_data = {
                                ...this.workers[i].saved_data,
                                projection_result_ptr: message.data.result_ptr,
                                projection_result_len_ptr: message.data.result_len_ptr,
                            };
                        } else if (message.data.type === 'find_waypoints') {
                            this.workers[i].processing = false;
                            this.workers[i].saved_data.waypoints = message.data.waypoints;
                        } else if (message.data.type === 'drag_and_move') {
                            this.workers[i].processing = false;
                            this.workers[i].saved_data.coord = message.data.coord;
                        }
                    };

                    // Initialize the worker with the star range to process and the WASM env
                    worker.postMessage({
                        type: 'init',
                        wasm_buffer,
                        stars: worker_star_data,
                    });
                }
            });
        });
    }

    projectStars({ latitude, longitude }: Coord, timestamp: number): Promise<void> {
        for (const handle of this.workers) {
            handle.processing = true;
            handle.worker.postMessage({
                type: 'project_stars',
                latitude,
                longitude,
                timestamp: BigInt(timestamp),
                result_len_ptr: handle.saved_data.projection_result_len_ptr,
                result_ptr: handle.saved_data.projection_result_ptr,
            });
        }
        return this.whenSettled();
    }

    projectConstellationBranch(branches: ConstellationBranch[], location: Coord, timestamp: number) {
        // const branches_ptr = this.allocArray(branches, sizedConstellationBranch);
        // const location_ptr = this.allocObject(location, sizedCoord);
        // (this.instance.exports.projectConstellation as any)(branches_ptr, branches.length, location_ptr, BigInt(timestamp));
    }

    async findWaypoints(start: Coord, end: Coord): Promise<Coord[]> {
        const waypoint_worker = await this.getIdleWorker();
        waypoint_worker.processing = true;
        waypoint_worker.worker.postMessage({
            type: 'find_waypoints',
            start,
            end,
        });
        return new Promise((resolve, reject) => {
            const check_if_done = () => {
                if (waypoint_worker.processing) {
                    window.requestAnimationFrame(check_if_done);
                    return;
                }
                resolve(waypoint_worker.saved_data.waypoints);
                delete waypoint_worker.saved_data.waypoints;
            };
            window.requestAnimationFrame(check_if_done);
        });
    }

    async dragAndMove(drag_start: Coord, drag_end: Coord): Promise<Coord> {
        const waypoint_worker = await this.getIdleWorker();
        waypoint_worker.processing = true;
        waypoint_worker.worker.postMessage({
            type: 'drag_and_move',
            drag_start,
            drag_end,
        });
        return new Promise((resolve, reject) => {
            const check_if_done = () => {
                if (waypoint_worker.processing) {
                    window.requestAnimationFrame(check_if_done);
                    return;
                }
                resolve(waypoint_worker.saved_data.coord);
                delete waypoint_worker.saved_data.coord;
            };
            window.requestAnimationFrame(check_if_done);
        });
    }

    private getIdleWorker(): Promise<WorkerHandle> {
        return new Promise((resolve, reject) => {
            const check_all = () => {
                for (const handle of this.workers) {
                    // Find the first non-processing worker
                    if (!handle.processing) {
                        resolve(handle);
                    }
                }
                window.requestAnimationFrame(check_all);
            };
            window.requestAnimationFrame(check_all);
        });
    }

    private whenSettled(): Promise<void> {
        return new Promise((resolve, reject) => {
            const check_all = () => {
                for (const handle of this.workers) {
                    if (handle.processing) {
                        window.requestAnimationFrame(check_all);
                        return;
                    }
                }
                resolve();
            };
            window.requestAnimationFrame(check_all);
        });
    }
}
