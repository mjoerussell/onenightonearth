enum WasmPrimative {
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
}

const u8 = WasmPrimative.u8;
const u16 = WasmPrimative.u16;
const u32 = WasmPrimative.u32;
const u64 = WasmPrimative.u64;
const i8 = WasmPrimative.i8;
const i16 = WasmPrimative.i16;
const i32 = WasmPrimative.i32;
const i64 = WasmPrimative.i64;
const f32 = WasmPrimative.f32;
const f64 = WasmPrimative.f64;

type Sized<T> = {
    [P in keyof T]: WasmPrimative;
};

export interface Coord extends NumberStruct {
    latitude: number;
    longitude: number;
}

const sizedCoord: Sized<Coord> = {
    latitude: f32,
    longitude: f32,
};

export interface CanvasPoint extends NumberStruct {
    x: number;
    y: number;
    brightness: number;
}

const sizedCanvasPoint: Sized<CanvasPoint> = {
    x: f32,
    y: f32,
    brightness: f32,
};

export interface Star extends NumberStruct {
    rightAscension: number;
    declination: number;
    brightness: number;
}

const sizedStar: Sized<Star> = {
    rightAscension: f32,
    declination: f32,
    brightness: f32,
};

interface NumberStruct {
    [key: string]: number;
}

type pointer = number;

export class WasmInterface {
    constructor(private instance: WebAssembly.Instance) {}

    projectStars(stars: Star[], location: Coord, timestamp: number): CanvasPoint[] {
        const star_ptr = this.allocArray(stars, sizedStar);
        const location_ptr = this.allocObject(location, sizedCoord);
        (this.instance.exports.projectStarsWasm as any)(star_ptr, stars.length, location_ptr, BigInt(timestamp));
    }

    /**
     * Compute waypoints along the great circle between two points. This results in a direct line between
     * the given points along the surface of a sphere.
     * @param starting_location The location to start at.
     * @param end_location      The location to end up at.
     * @param num_waypoints     The number of waypoints to compute. Defaults to `100`.
     * @return An array of length `num_waypoints` of Coords representing a path between `starting_location` and `end_location`.
     */
    getWaypoints(starting_location: Coord, end_location: Coord, num_waypoints = 100): Coord[] {
        const start_ptr = this.allocObject(starting_location, sizedCoord);
        const end_ptr = this.allocObject(end_location, sizedCoord);
        const res_ptr = (this.instance.exports.findWaypointsWasm as any)(start_ptr, end_ptr, num_waypoints);

        const result: Coord[] = this.readArray(res_ptr, num_waypoints, sizedCoord);
        this.freeBytes(res_ptr, sizeOf(sizedCoord) * num_waypoints);

        return result;
    }

    /**
     * Given the altitude and azimuth of a star, compute it's location on the unit circle using the custom
     * projection method.
     * @param altitude      The altitude of the star being projected.
     * @param azimuth       The azimuth of the star being projected.
     * @param brightness
     */
    projectCoord(altitude: number, azimuth: number, brightness: number = 1.0): CanvasPoint {
        const res_ptr = (this.instance.exports.getProjectedCoordWasm as any)(altitude, azimuth, brightness);
        const result = this.readObject(res_ptr, sizedCanvasPoint);
        this.freeBytes(res_ptr, sizeOf(sizedCanvasPoint));

        return result;
    }

    getString(ptr: pointer, len: number): string {
        const message_mem = this.memory.slice(ptr, ptr + len);
        const decoder = new TextDecoder();
        return decoder.decode(message_mem);
    }

    private allocPrimative(data: number, size: WasmPrimative): pointer {
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

    private readPrimative(ptr: pointer, size: WasmPrimative): number {
        const total_bytes = sizeOfPrimative(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        return this.getPrimative(data_mem, size) as number;
    }

    private allocString(data: string): pointer {
        const ptr = this.allocBytes(data.length);
        const encoder = new TextEncoder();
        const data_mem = new DataView(this.memory, ptr, data.length);
        const encoded_data = encoder.encode(data);

        for (const [index, char] of encoded_data.entries()) {
            data_mem.setUint8(index, char);
        }

        return ptr;
    }

    private allocObject<T extends NumberStruct>(data: T, size: Sized<T>): pointer {
        const total_bytes = sizeOf(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        for (const key in data) {
            try {
                this.setPrimative(data_mem, data[key], size[key], current_offset);
            } catch (error) {
                if (error instanceof RangeError) {
                    console.error(
                        `RangeError: Index ${current_offset} (size = ${sizeOfPrimative(
                            size[key]
                        )}) is out of bounds of DataView [total_bytes = ${data_mem.byteLength}] for type`
                    );
                }
            }
            current_offset += sizeOfPrimative(size[key]);
        }

        return ptr;
    }

    private readObject<T extends NumberStruct>(ptr: pointer, size: Sized<T>): T {
        const total_bytes = sizeOf(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        const result: any = {};
        let current_offset = 0;
        for (const key in size) {
            const value = this.getPrimative(data_mem, size[key], current_offset);
            result[key] = value;
            current_offset += sizeOfPrimative(size[key]);
        }

        return result;
    }

    private allocArray<T extends NumberStruct>(data: T[], size: Sized<T>): pointer {
        const item_bytes = sizeOf(size);
        const total_bytes = item_bytes * data.length;
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        for (const item of data) {
            for (const key in item) {
                try {
                    this.setPrimative(data_mem, item[key], size[key], current_offset);
                } catch (error) {
                    if (error instanceof RangeError) {
                        console.error(
                            `RangeError: Index ${current_offset} (size = ${sizeOfPrimative(
                                size[key]
                            )}) is out of bounds of DataView [total_bytes = ${data_mem.byteLength}] for type`
                        );
                    }
                }
                current_offset += sizeOfPrimative(size[key]);
            }
        }

        return ptr;
    }

    private readArray<T extends NumberStruct>(ptr: pointer, num_items: number, size: Sized<T>): T[] {
        const total_bytes = sizeOf(size) * num_items;
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        const result_array: T[] = new Array(num_items);
        for (let index = 0; index < num_items; index += 1) {
            const result: any = {};
            for (const key in size) {
                const value = this.getPrimative(data_mem, size[key], current_offset);
                result[key] = value;
                current_offset += sizeOfPrimative(size[key]);
            }
            result_array[index] = result;
        }

        return result_array;
    }

    private allocBytes(num_bytes: number): pointer {
        return (this.instance.exports as any)._wasm_alloc(num_bytes);
    }

    private freeBytes(location: pointer, num_bytes: number): void {
        (this.instance.exports as any)._wasm_free(location, num_bytes);
    }

    private setPrimative(mem: DataView, value: number, type: WasmPrimative, offset = 0) {
        switch (type) {
            case u8: {
                mem.setUint8(offset, value);
                break;
            }
            case u16: {
                mem.setUint16(offset, value, true);
                break;
            }
            case u32: {
                mem.setUint32(offset, value, true);
                break;
            }
            case u64: {
                mem.setBigUint64(offset, BigInt(value), true);
                break;
            }
            case i8: {
                mem.setInt8(offset, value);
                break;
            }
            case i16: {
                mem.setInt16(offset, value, true);
                break;
            }
            case i32: {
                mem.setInt32(offset, value, true);
                break;
            }
            case i64: {
                mem.setBigInt64(offset, BigInt(value), true);
                break;
            }
            case f32: {
                mem.setFloat32(offset, value, true);
                break;
            }
            case f64: {
                mem.setFloat64(offset, value, true);
                break;
            }
        }
    }

    private getPrimative(mem: DataView, type: WasmPrimative, offset = 0): number | BigInt {
        switch (type) {
            case u8: {
                return mem.getUint8(offset);
            }
            case u16: {
                return mem.getUint16(offset, true);
            }
            case u32: {
                return mem.getUint32(offset, true);
            }
            case u64: {
                return mem.getBigUint64(offset, true);
            }
            case i8: {
                return mem.getInt8(offset);
            }
            case i16: {
                return mem.getInt16(offset, true);
            }
            case i32: {
                return mem.getInt32(offset, true);
            }
            case i64: {
                return mem.getBigInt64(offset, true);
            }
            case f32: {
                return mem.getFloat32(offset, true);
            }
            case f64: {
                return mem.getFloat64(offset, true);
            }
        }
    }

    get memory(): ArrayBuffer {
        return (this.instance.exports.memory as any).buffer;
    }
}

const sizeOfPrimative = (data: WasmPrimative): number => {
    switch (data) {
        case u8:
        case i8:
            return 1;
        case u16:
        case i16:
            return 2;
        case u32:
        case i32:
        case f32:
            return 4;
        case u64:
        case i64:
        case f64:
            return 8;
        default:
            return data;
    }
};

const sizeOf = <T>(data: Sized<T>): number => {
    let size = 0;
    for (const key in data) {
        if (data.hasOwnProperty(key)) {
            size += sizeOfPrimative(data[key]);
        }
    }

    return size;
};
