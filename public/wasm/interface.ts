import { Coord, CanvasPoint, ConstellationBranch } from './size';

export interface WasmEnv {
    [func_name: string]: (...args: any[]) => any;
}

interface WorkerHandle {
    worker: Worker;
    processing: boolean;
}

export class WasmInterface {
    private workers: WorkerHandle[] = [];

    constructor(private num_workers: number = 4) {}

    init(env: WasmEnv): Promise<void> {
        let num_complete = 0;
        const star_promise: Promise<string[]> = fetch('/stars').then(star_result => star_result.json());
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
                    });

                    // Receive the worker's messages
                    worker.onmessage = message => {
                        if (message.data.type === 'INIT_COMPLETE') {
                            num_complete += 1;
                            console.log(`${num_complete} workers initialized`);
                            if (num_complete === this.num_workers) {
                                // console.log('finishing initializing');
                                resolve();
                            }
                        } else if (message.data.type === 'drawPointWasm') {
                            for (const point of message.data.points as CanvasPoint[]) {
                                env.drawPointWasm(point.x, point.y, point.brightness);
                            }
                            this.workers[i].processing = false;
                            // env.drawPointWasm(message.data.x, message.data.y, message.data.brightness);
                        }
                    };

                    // Initialize the worker with the star range to process and the WASM env
                    worker.postMessage({
                        type: 'INIT',
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
                type: 'PROJECT',
                latitude,
                longitude,
                timestamp: BigInt(timestamp),
            });
        }

        return new Promise((resolve, reject) => {
            const check_interval = setInterval(() => {
                let all_done: boolean = true;
                for (const handle of this.workers) {
                    if (handle.processing) {
                        all_done = false;
                        break;
                    }
                }
                if (all_done) {
                    console.log('done');
                    clearInterval(check_interval);
                    resolve();
                } else {
                    console.log('not done');
                }
            }, 1);
        });
    }

    projectConstellationBranch(branches: ConstellationBranch[], location: Coord, timestamp: number) {
        // const branches_ptr = this.allocArray(branches, sizedConstellationBranch);
        // const location_ptr = this.allocObject(location, sizedCoord);
        // (this.instance.exports.projectConstellation as any)(branches_ptr, branches.length, location_ptr, BigInt(timestamp));
    }
}
