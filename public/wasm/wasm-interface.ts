import {
    WasmPrimative,
    Coord,
    sizedCoord,
    pointer,
    Sized,
    sizeOf,
    sizeOfPrimative,
    sizedCanvasSettings,
    sizedSkyCoord,
    CanvasPoint,
    SkyCoord,
    Allocatable,
} from './size';
import { CanvasSettings } from '../renderer';

interface WasmFns {
    initializeStars: (star_data: pointer, star_len: number) => void;
    initializeCanvas: (settings: pointer) => void;
    initializeConstellations: (constellation_data: pointer) => void;
    updateCanvasSettings: (settings: pointer) => void;
    getImageData: (size_in_bytes: pointer) => pointer;
    resetImageData: () => void;
    projectStars: (observer_latitude: number, observer_longitude: number, observer_timestamp: BigInt) => void;
    projectConstellationGrids: (observer_latitude: number, observer_longitude: number, observer_timestamp: BigInt) => void;
    getConstellationAtPoint: (
        x: number,
        y: number,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => number;
    getConstellationCentroid: (constellation_index: number) => pointer;
    dragAndMove: (drag_start_x: number, drag_start_y: number, drag_end_x: number, drag_end_y: number) => pointer;
    findWaypoints: (start_lat: number, start_long: number, end_lat: number, end_long: number) => pointer;
    getCoordForSkyCoord: (right_ascension: number, declination: number, observer_timestamp: BigInt) => pointer;
    getSkyCoordForCanvasPoint: (
        x: number,
        y: number,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => pointer;
    getCoordForCanvasPoint: (
        x: number,
        y: number,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => pointer;
}

export class WasmInterface {
    private lib: WasmFns;

    constructor(private instance: WebAssembly.Instance) {
        this.lib = this.instance.exports as any;
    }

    initialize(stars: Uint8Array, constellation_data: Uint8Array, canvas_settings: CanvasSettings): void {
        const init_start = performance.now();

        const const_ptr = this.allocBytes(constellation_data.byteLength);
        const const_view = new Uint8Array(this.memory, const_ptr);
        const_view.set(constellation_data);
        this.lib.initializeConstellations(const_ptr);

        const star_ptr = this.allocBytes(stars.byteLength);
        const view = new Uint8Array(this.memory, star_ptr);
        view.set(stars);

        this.lib.initializeStars(star_ptr, stars.byteLength / 13);

        const settings_ptr = this.allocObject(canvas_settings, sizedCanvasSettings);
        this.lib.initializeCanvas(settings_ptr);

        const init_end = performance.now();
        console.log(`Took ${init_end - init_start} ms to initialize`);
    }

    projectStars(latitude: number, longitude: number, timestamp: BigInt): void {
        this.lib.projectStars(latitude, longitude, timestamp);
    }

    projectConstellationGrids(latitude: number, longitude: number, timestamp: BigInt): void {
        this.lib.projectConstellationGrids(latitude, longitude, timestamp);
    }

    getConstellationAtPoint(point: CanvasPoint, latitude: number, longitude: number, timestamp: BigInt): number {
        const constellation_index = this.lib.getConstellationAtPoint(point.x, point.y, latitude, longitude, timestamp);
        return constellation_index;
    }

    getConstellationCentroid(index: number): SkyCoord | null {
        const coord_ptr = this.lib.getConstellationCentroid(index);
        if (coord_ptr === 0) {
            return null;
        }
        const coord = this.readObject(coord_ptr, sizedSkyCoord);
        this.freeBytes(coord_ptr, sizeOf(sizedSkyCoord));
        return coord;
    }

    resetImageData(): void {
        this.lib.resetImageData();
    }

    getImageData(): Uint8ClampedArray {
        const size_ptr = this.allocBytes(4);
        const pixel_data_ptr = this.lib.getImageData(size_ptr);
        const pixel_data_size = this.readPrimative(size_ptr, WasmPrimative.u32);
        this.freeBytes(size_ptr, 4);
        return new Uint8ClampedArray(this.memory, pixel_data_ptr, pixel_data_size);
    }

    findWaypoints(start: Coord, end: Coord): Float32Array {
        const result_ptr = this.lib.findWaypoints(start.latitude, start.longitude, end.latitude, end.longitude);
        return new Float32Array(this.memory.slice(result_ptr, result_ptr + 4 * 300));
    }

    dragAndMove(drag_start: Coord, drag_end: Coord): Coord {
        const result_ptr = this.lib.dragAndMove(drag_start.latitude, drag_start.longitude, drag_end.latitude, drag_end.longitude);
        const result: Coord = this.readObject(result_ptr, sizedCoord);
        this.freeBytes(result_ptr, sizeOf(sizedCoord));
        return result;
    }

    getCoordForSkyCoord(sky_coord: SkyCoord, timestamp: BigInt): Coord {
        const coord_ptr = this.lib.getCoordForSkyCoord(sky_coord.right_ascension, sky_coord.declination, timestamp);
        const coord = this.readObject(coord_ptr, sizedCoord);
        this.freeBytes(coord_ptr, sizeOf(sizedCoord));
        return coord;
    }

    getSkyCoordForCanvasPoint(
        point: CanvasPoint,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ): SkyCoord | null {
        const sky_coord_ptr = this.lib.getSkyCoordForCanvasPoint(
            point.x,
            point.y,
            observer_latitude,
            observer_longitude,
            observer_timestamp
        );
        if (sky_coord_ptr === 0) {
            return null;
        } else {
            const sky_coord = this.readObject(sky_coord_ptr, sizedSkyCoord);
            this.freeBytes(sky_coord_ptr, sizeOf(sizedSkyCoord));
            return sky_coord;
        }
    }

    getCoordForCanvasPoint(
        point: CanvasPoint,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ): Coord | null {
        const coord_ptr = this.lib.getCoordForCanvasPoint(point.x, point.y, observer_latitude, observer_longitude, observer_timestamp);
        if (coord_ptr === 0) {
            return null;
        } else {
            const coord = this.readObject(coord_ptr, sizedCoord);
            this.freeBytes(coord_ptr, sizeOf(sizedCoord));
            return coord;
        }
    }

    updateSettings(settings: CanvasSettings): void {
        const settings_ptr = this.allocObject(settings, sizedCanvasSettings);
        this.lib.updateCanvasSettings(settings_ptr);
    }

    getString(ptr: pointer, len: number): string {
        const message_mem = this.memory.slice(ptr, ptr + len);
        const decoder = new TextDecoder();
        return decoder.decode(message_mem);
    }

    allocPrimative(data: number, size: WasmPrimative): pointer {
        const total_bytes = sizeOfPrimative(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        try {
            this.setPrimative(data_mem, data, size, 0);
        } catch (error) {
            if (error instanceof RangeError) {
                console.error(
                    `RangeError: Could not allocate primative (size = ${total_bytes}) for DataView with size ${data_mem.byteLength}`
                );
            } else {
                throw error;
            }
        }
        return ptr;
    }

    readPrimative(ptr: pointer, size: WasmPrimative): number {
        const total_bytes = sizeOfPrimative(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        return this.getPrimative(data_mem, size) as number;
    }

    allocObject<T extends Allocatable>(data: T, size: Sized<T>): pointer {
        const total_bytes = sizeOf(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        this.setObject(data_mem, data, size);
        return ptr;
    }

    readObject<T extends Allocatable>(ptr: pointer, size: Sized<T>): T {
        const total_bytes = sizeOf(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        const result: any = {};
        let current_offset = 0;
        for (const key in size) {
            const value = this.getPrimative(data_mem, size[key] as WasmPrimative, current_offset);
            result[key] = value;
            current_offset += sizeOfPrimative(size[key] as WasmPrimative);
        }

        return result;
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

    private getPrimative(mem: DataView, type: WasmPrimative, offset = 0): number | boolean | BigInt {
        switch (type) {
            case WasmPrimative.bool: {
                return mem.getUint8(offset) == 1;
            }
            case WasmPrimative.u8: {
                return mem.getUint8(offset);
            }
            case WasmPrimative.u16: {
                return mem.getUint16(offset, true);
            }
            case WasmPrimative.u32: {
                return mem.getUint32(offset, true);
            }
            case WasmPrimative.u64: {
                return mem.getBigUint64(offset, true);
            }
            case WasmPrimative.i8: {
                return mem.getInt8(offset);
            }
            case WasmPrimative.i16: {
                return mem.getInt16(offset, true);
            }
            case WasmPrimative.i32: {
                return mem.getInt32(offset, true);
            }
            case WasmPrimative.i64: {
                return mem.getBigInt64(offset, true);
            }
            case WasmPrimative.f32: {
                return mem.getFloat32(offset, true);
            }
            case WasmPrimative.f64: {
                return mem.getFloat64(offset, true);
            }
        }
    }

    get memory(): ArrayBuffer {
        return (this.instance.exports.memory as any).buffer;
    }
}
