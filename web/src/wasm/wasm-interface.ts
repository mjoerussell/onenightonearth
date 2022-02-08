import {
    WasmPrimative,
    Coord,
    pointer,
    Sized,
    sizeOf,
    sizeOfPrimative,
    sizedCanvasSettings,
    CanvasPoint,
    SkyCoord,
    Allocatable,
} from './size';
import { CanvasSettings } from '../renderer';

interface WasmLib {
    memory: WebAssembly.Memory;
    allocateStars: (num_stars: number) => pointer;
    initializeStars: () => void;
    initializeCanvas: (settings: pointer) => void;
    initializeConstellations: (constellation_data: pointer) => void;
    initializeResultData: () => pointer;
    updateCanvasSettings: (settings: pointer) => pointer;
    getImageData: () => pointer;
    resetImageData: () => void;
    projectStarsAndConstellations: (observer_latitude: number, observer_longitude: number, observer_timestamp: BigInt) => void;
    getConstellationAtPoint: (
        x: number,
        y: number,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => number;
    getConstellationCentroid: (constellation_index: number) => pointer;
    dragAndMove: (drag_start_x: number, drag_start_y: number, drag_end_x: number, drag_end_y: number) => void;
    findWaypoints: (start_lat: number, start_long: number, end_lat: number, end_long: number) => pointer;
    getCoordForSkyCoord: (right_ascension: number, declination: number, observer_timestamp: BigInt) => void;
    getCoordForCanvasPoint: (
        x: number,
        y: number,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => void;
}

export class WasmInterface {
    private lib: WasmLib;

    /** Pointer to the wasm canvas settings. */
    private settings_ptr: number = 0;
    /** Pointer to wasm result data, for returning multiple values from functions. */
    private result_ptr: number = 0;

    /** Pointer to star data. */
    private star_ptr: number = 0;

    /** Pointer to the image data. */
    private pixel_data_ptr: number = 0;
    /** The number of pixels in the image. This may change if the window is resized. */
    private pixel_count: number = 0;

    constructor(private instance: WebAssembly.Instance) {
        this.lib = this.instance.exports as any;
    }

    /**
     * Initialize the wasm module, performing initial allocations and settng up the canvas. This function **must** be called
     * before any other wasm function, as everything relies on these steps being completed.
     * @param num_stars The *total* number of stars that will eventually be added.
     * @param constellation_data The constellation data to use when rendering.
     * @param canvas_settings The initial canvas settings.
     */
    initialize(star_data: Uint8Array, constellation_data: Uint8Array, canvas_settings: CanvasSettings): void {
        const init_start = performance.now();

        const const_ptr = this.allocBytes(constellation_data.byteLength);
        const const_view = new Uint8Array(this.memory, const_ptr);
        const_view.set(constellation_data);
        this.lib.initializeConstellations(const_ptr);

        const num_stars = star_data.byteLength / 13;

        this.star_ptr = this.lib.allocateStars(num_stars);
        const star_view = new Uint8Array(this.memory, this.star_ptr, star_data.byteLength);
        star_view.set(star_data);

        this.lib.initializeStars();

        this.settings_ptr = this.allocObject(canvas_settings, sizedCanvasSettings);
        this.lib.initializeCanvas(this.settings_ptr);

        this.result_ptr = this.lib.initializeResultData();

        this.pixel_data_ptr = this.lib.getImageData();
        this.pixel_count = new Uint32Array(this.memory, this.result_ptr, 2)[0];

        const init_end = performance.now();
        console.log(`Took ${init_end - init_start} ms to initialize`);
    }

    projectStarsAndConstellations(latitude: number, longitude: number, timestamp: BigInt): void {
        this.lib.projectStarsAndConstellations(latitude, longitude, timestamp);
    }

    getConstellationAtPoint(point: CanvasPoint, latitude: number, longitude: number, timestamp: BigInt): number {
        const constellation_index = this.lib.getConstellationAtPoint(point.x, point.y, latitude, longitude, timestamp);
        return constellation_index;
    }

    getConstellationCentroid(index: number): SkyCoord | null {
        this.lib.getConstellationCentroid(index);
        const result_data = new Float32Array(this.memory, this.result_ptr, 2);
        return {
            right_ascension: result_data[0],
            declination: result_data[1],
        };
    }

    /** Clear the canvas. */
    resetImageData(): void {
        this.lib.resetImageData();
    }

    /**
     * Get the pixel data, which can then be put onto the canvas.
     * @returns
     */
    getImageData(): Uint8ClampedArray {
        return new Uint8ClampedArray(this.memory, this.pixel_data_ptr, this.pixel_count);
    }

    /**
     * Find waypoints between two coordinates. This will return 150 waypoints.
     * @returns A `Float32Array` containing the waypoint latitude and longitudes. Every 2 sequential floats in
     *      this array represent 1 waypoint coordinate.
     */
    findWaypoints(start: Coord, end: Coord): Float32Array {
        const result_ptr = this.lib.findWaypoints(start.latitude, start.longitude, end.latitude, end.longitude);
        return new Float32Array(this.memory.slice(result_ptr, result_ptr + 4 * 300));
    }

    dragAndMove(start_x: number, start_y: number, end_x: number, end_y: number): Coord {
        this.lib.dragAndMove(start_x, start_y, end_x, end_y);
        const result_data = new Float32Array(this.memory, this.result_ptr, 2);
        return {
            latitude: result_data[0],
            longitude: result_data[1],
        };
    }

    getCoordForSkyCoord(sky_coord: SkyCoord, timestamp: BigInt): Coord {
        this.lib.getCoordForSkyCoord(sky_coord.right_ascension, sky_coord.declination, timestamp);
        const result_data = new Float32Array(this.memory, this.result_ptr, 2);
        return {
            latitude: result_data[0],
            longitude: result_data[1],
        };
    }

    updateSettings(settings: CanvasSettings): void {
        this.setObject(new DataView(this.memory, this.settings_ptr), settings, sizedCanvasSettings);
        const pixel_data_ptr = this.lib.updateCanvasSettings(this.settings_ptr);
        if (pixel_data_ptr !== 0) {
            this.pixel_data_ptr = pixel_data_ptr;
            this.pixel_count = new Uint32Array(this.memory, this.result_ptr, 2)[0];
        }
    }

    getString(ptr: pointer, len: number): string {
        const message_mem = this.memory.slice(ptr, ptr + len);
        const decoder = new TextDecoder();
        return decoder.decode(message_mem);
    }

    allocObject<T extends Allocatable>(data: T, size: Sized<T>): pointer {
        const total_bytes = sizeOf(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        this.setObject(data_mem, data, size);
        return ptr;
    }

    allocBytes(num_bytes: number): pointer {
        return (this.instance.exports as any)._wasm_alloc(num_bytes);
    }

    freeBytes(location: pointer, num_bytes: number): void {
        (this.instance.exports as any)._wasm_free(location, num_bytes);
    }

    setObject<T extends Allocatable>(mem: DataView, data: T, type: Sized<T>, offset = 0): number {
        let current_offset = offset;
        for (const key in data) {
            this.setPrimative(mem, data[key], type[key], current_offset);
            current_offset += sizeOfPrimative(type[key]);
        }
        return current_offset;
    }

    private setPrimative(mem: DataView, value: number | boolean, type: WasmPrimative, offset = 0) {
        let val: number;
        if (typeof value === 'boolean') {
            val = value ? 1 : 0;
        } else {
            val = value;
        }
        switch (type) {
            case WasmPrimative.bool: {
                mem.setUint8(offset, val);
                break;
            }
            case WasmPrimative.u8: {
                mem.setUint8(offset, val);
                break;
            }
            case WasmPrimative.u16: {
                mem.setUint16(offset, val, true);
                break;
            }
            case WasmPrimative.u32: {
                mem.setUint32(offset, val, true);
                break;
            }
            case WasmPrimative.u64: {
                mem.setBigUint64(offset, BigInt(val), true);
                break;
            }
            case WasmPrimative.i8: {
                mem.setInt8(offset, val);
                break;
            }
            case WasmPrimative.i16: {
                mem.setInt16(offset, val, true);
                break;
            }
            case WasmPrimative.i32: {
                mem.setInt32(offset, val, true);
                break;
            }
            case WasmPrimative.i64: {
                mem.setBigInt64(offset, BigInt(val), true);
                break;
            }
            case WasmPrimative.f32: {
                mem.setFloat32(offset, val, true);
                break;
            }
            case WasmPrimative.f64: {
                mem.setFloat64(offset, val, true);
                break;
            }
        }
    }

    get memory(): ArrayBuffer {
        return this.lib.memory.buffer;
    }
}
