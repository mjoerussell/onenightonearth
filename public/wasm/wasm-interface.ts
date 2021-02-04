import {
    WasmPrimative,
    Allocatable,
    Coord,
    sizedCoord,
    pointer,
    Sized,
    isSimpleSize,
    isSimpleAlloc,
    isComplexSize,
    sizeOf,
    sizeOfPrimative,
    sizedCanvasSettings,
    Star,
    WasmStar,
    sizedWasmStar,
    Constellation,
    sizedSkyCoord,
    CanvasPoint,
    sizedCanvasPoint,
} from './size';
import { CanvasSettings } from '../renderer';

export class WasmInterface {
    constructor(private instance: WebAssembly.Instance) {}

    initialize(stars: Star[], constellations: Constellation[], canvas_settings: CanvasSettings): void {
        let wasm_stars: WasmStar[] = stars.map(star => {
            return {
                right_ascension: star.right_ascension,
                declination: star.declination,
                brightness: star.brightness,
                spec_type: star.spec_type,
            };
        });
        const boundaries: pointer[] = [];
        for (const c of constellations) {
            const coords_ptr = this.allocArray(c.boundaries, sizedSkyCoord);
            boundaries.push(coords_ptr);
        }
        const constellation_lengths = constellations.map(c => c.boundaries.length);
        const constellation_ptr = this.allocPrimativeArray(boundaries, WasmPrimative.u32);
        const coord_lens_ptr = this.allocPrimativeArray(constellation_lengths, WasmPrimative.u32);
        const star_ptr = this.allocArray(wasm_stars, sizedWasmStar);
        const settings_ptr = this.allocObject(canvas_settings, sizedCanvasSettings);

        (this.instance.exports.initialize as any)(
            star_ptr,
            wasm_stars.length,
            constellation_ptr,
            coord_lens_ptr,
            constellations.length,
            settings_ptr
        );
    }

    projectStars(latitude: number, longitude: number, timestamp: BigInt): void {
        (this.instance.exports.projectStarsWasm as any)(latitude, longitude, timestamp);
    }

    projectConstellationGrids(latitude: number, longitude: number, timestamp: BigInt): void {
        (this.instance.exports.projectConstellationGrids as any)(latitude, longitude, timestamp);
    }

    getConstellationAtPoint(point: CanvasPoint, latitude: number, longitude: number, timestamp: BigInt): number {
        const point_ptr = this.allocObject(point, sizedCanvasPoint);
        const constellation_index = (this.instance.exports.getConstellationAtPoint as any)(point_ptr, latitude, longitude, timestamp);
        return constellation_index;
    }

    resetImageData(): void {
        (this.instance.exports.resetImageData as any)();
    }

    getImageData(): Uint8ClampedArray {
        const size_ptr = this.allocBytes(4);
        const pixel_data_ptr = (this.instance.exports.getImageData as any)(size_ptr);
        const pixel_data_size = this.readPrimative(size_ptr, WasmPrimative.u32);
        this.freeBytes(size_ptr, 4);
        return new Uint8ClampedArray(this.memory, pixel_data_ptr, pixel_data_size);
    }

    findWaypoints(start: Coord, end: Coord): Coord[] {
        const num_waypoints_ptr = this.allocBytes(4);
        const start_ptr = this.allocObject(start, sizedCoord);
        const end_ptr = this.allocObject(end, sizedCoord);
        const result_ptr = (this.instance.exports.findWaypointsWasm as any)(start_ptr, end_ptr, num_waypoints_ptr);
        const num_waypoints = this.readPrimative(num_waypoints_ptr, WasmPrimative.u32);
        const waypoints = this.readArray(result_ptr, num_waypoints, sizedCoord);
        this.freeBytes(num_waypoints_ptr, 4);
        this.freeBytes(result_ptr, num_waypoints * sizeOf(sizedCoord));
        return waypoints;
    }

    dragAndMove(drag_start: Coord, drag_end: Coord): Coord {
        const result_ptr = (this.instance.exports.dragAndMoveWasm as any)(
            drag_start.latitude,
            drag_start.longitude,
            drag_end.latitude,
            drag_end.longitude
        );
        const result: Coord = this.readObject(result_ptr, sizedCoord);
        this.freeBytes(result_ptr, sizeOf(sizedCoord));
        return result;
    }

    updateSettings(settings: CanvasSettings): void {
        const settings_ptr = this.allocObject(settings, sizedCanvasSettings);
        (this.instance.exports.updateCanvasSettings as any)(settings_ptr);
    }

    getString(ptr: pointer, len: number): string {
        const message_mem = this.readBytes(ptr, len);
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

    allocString(data: string): pointer {
        const ptr = this.allocBytes(data.length);
        const encoder = new TextEncoder();
        const data_mem = new DataView(this.memory, ptr, data.length);
        const encoded_data = encoder.encode(data);

        for (const [index, char] of encoded_data.entries()) {
            data_mem.setUint8(index, char);
        }

        return ptr;
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
        if (isSimpleSize(size)) {
            for (const key in size) {
                const value = this.getPrimative(data_mem, size[key], current_offset);
                result[key] = value;
                current_offset += sizeOfPrimative(size[key]);
            }
        } else if (isComplexSize(size)) {
            for (const key in size) {
                const value = this.getObject(data_mem, size[key], current_offset);
                result[key] = value;
                current_offset += sizeOf(size[key]);
            }
        }

        return result;
    }

    allocArray<T extends Allocatable>(data: T[], size: Sized<T>): pointer {
        const item_bytes = sizeOf(size);
        const total_bytes = item_bytes * data.length;
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        for (const item of data) {
            current_offset = this.setObject(data_mem, item, size, current_offset);
        }

        return ptr;
    }

    allocPrimativeArray(data: number[], size: WasmPrimative): pointer {
        const item_bytes = sizeOfPrimative(size);
        const total_bytes = item_bytes * data.length;
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        for (const item of data) {
            this.setPrimative(data_mem, item, size, current_offset);
            current_offset += item_bytes;
        }
        return ptr;
    }

    readArray<T extends Allocatable>(ptr: pointer, num_items: number, size: Sized<T>): T[] {
        const total_bytes = sizeOf(size) * num_items;
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        const result_array: T[] = new Array(num_items);
        if (isSimpleSize(size)) {
            for (let index = 0; index < num_items; index += 1) {
                const result: any = {};
                for (const key in size) {
                    const value = this.getPrimative(data_mem, size[key], current_offset);
                    result[key] = value;
                    current_offset += sizeOfPrimative(size[key]);
                }
                result_array[index] = result;
            }
        } else if (isComplexSize(size)) {
            for (let index = 0; index < num_items; index += 1) {
                const result: any = {};
                for (const key in size) {
                    const value = this.getObject(data_mem, size[key], current_offset);
                    result[key] = value;
                    current_offset += sizeOf(size[key]);
                }
                result_array[index] = result;
            }
        }

        return result_array;
    }

    readBytes(location: pointer, num_bytes: number): ArrayBuffer {
        return this.memory.slice(location, location + num_bytes);
    }

    allocBytes(num_bytes: number): pointer {
        return (this.instance.exports as any)._wasm_alloc(num_bytes);
    }

    freeBytes(location: pointer, num_bytes: number): void {
        (this.instance.exports as any)._wasm_free(location, num_bytes);
    }

    setObject<T extends Allocatable>(mem: DataView, data: T, type: Sized<T>, offset = 0): number {
        let current_offset = offset;
        if (isSimpleAlloc(data)) {
            if (isSimpleSize(type)) {
                for (const key in data) {
                    this.setPrimative(mem, data[key], type[key], current_offset);
                    current_offset += sizeOfPrimative(type[key]);
                }
            }
        } else {
            if (isComplexSize(type)) {
                for (const key in data) {
                    this.setObject(mem, data[key] as Allocatable, type[key], current_offset);
                    current_offset += sizeOf(type[key]);
                }
            }
        }
        return current_offset;
    }

    getObject<T extends Allocatable>(mem: DataView, type: Sized<T>, offset = 0): T {
        let result: any = {};
        let current_offset = offset;
        if (isSimpleSize(type)) {
            for (const key in type) {
                const val = this.getPrimative(mem, type[key], current_offset);
                result[key] = val;
                current_offset += sizeOfPrimative(type[key]);
            }
        }
        if (isComplexSize(type)) {
            for (const key in type) {
                const val = this.getObject(mem, type[key], current_offset);
                result[key] = val;
                current_offset += sizeOf(type[key]);
            }
        }
        return result;
    }

    private setPrimative(mem: DataView, value: number | boolean, type: WasmPrimative, offset = 0) {
        let val: number;
        if (typeof value === 'boolean') {
            val = value ? 1 : 0;
        } else {
            val = value;
        }
        switch (type) {
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

    private getPrimative(mem: DataView, type: WasmPrimative, offset = 0): number | BigInt {
        switch (type) {
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
