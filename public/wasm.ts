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

export type Coord = {
    latitude: number;
    longitude: number;
};

const sizedCoord: Sized<Coord> = {
    latitude: f32,
    longitude: f32,
};

export type CanvasPoint = {
    x: number;
    y: number;
    brightness: number;
};

const sizedCanvasPoint: Sized<CanvasPoint> = {
    x: f32,
    y: f32,
    brightness: f32,
};

export type Star = {
    rightAscension: number;
    declination: number;
    brightness: number;
};

const sizedStar: Sized<Star> = {
    rightAscension: f32,
    declination: f32,
    brightness: f32,
};

export type StarCoord = {
    rightAscension: number;
    declination: number;
};

const sizedStarCoord: Sized<StarCoord> = {
    rightAscension: f32,
    declination: f32,
};

export type ConstellationBranch = {
    a: StarCoord;
    b: StarCoord;
};

const sizedConstellationBranch: Sized<ConstellationBranch> = {
    a: sizedStarCoord,
    b: sizedStarCoord,
};

/**
 * A `SimpleAlloc` is a struct whose fields are just numbers. This means that it can
 * be allocated and read just using `getPrimative` and `setPrimative`.
 */
type SimpleAlloc = {
    [key: string]: number;
};

/**
 * A `SimpleSize` is a size definition for `SimpleAlloc`.
 */
type SimpleSize<T extends SimpleAlloc> = {
    [K in keyof T]: WasmPrimative;
};

/**
 * `ComplexAlloc` is a struct whose fields are structs. The fields can either be more `ComplexAlloc`'s, or
 * just `SimpleAlloc`'s.
 */
type ComplexAlloc = {
    [key: string]: Allocatable;
};

/**
 * `ComplexSize` is a size definition for `ComplexAlloc`.
 */
type ComplexSize<T extends ComplexAlloc> = {
    [K in keyof T]: Sized<T[K]>;
};

/**
 * `Allocatable` types are data types that can be automatically allocated regardless of their complexity.
 */
type Allocatable = SimpleAlloc | ComplexAlloc;
/**
 * `Sized` types are companions to `Allocatable` types. For every type `T` that extends `Allocatable`, there must be an implementation
 * of `Sized<T>` which defines the size in bytes of every field on `T`.
 */
type Sized<T extends Allocatable> = T extends SimpleAlloc ? SimpleSize<T> : T extends ComplexAlloc ? ComplexSize<T> : never;

const isSimpleAlloc = (data: Allocatable): data is SimpleAlloc => {
    for (const key in data) {
        if (data.hasOwnProperty(key)) {
            if (typeof data[key] !== 'number') {
                return false;
            }
        }
    }
    return true;
};

const isSimpleSize = (type: Sized<any>): type is SimpleSize<any> => {
    for (const key in type) {
        if (type.hasOwnProperty(key)) {
            if (typeof type[key] !== 'number') {
                return false;
            }
        }
    }
    return true;
};

const isComplexSize = (type: Sized<any>): type is ComplexSize<any> => {
    return !isSimpleSize(type);
};

type pointer = number;

export class WasmInterface {
    constructor(private instance: WebAssembly.Instance) {}

    init() {
        (this.instance.exports.initialize as any)();
    }

    // projectStars(stars: Star[], location: Coord, timestamp: number) {
    projectStars(location: Coord, timestamp: number) {
        // const star_ptr = this.allocArray(stars, sizedStar);
        const location_ptr = this.allocObject(location, sizedCoord);
        // (this.instance.exports.projectStarsWasm as any)(star_ptr, stars.length, location_ptr, BigInt(timestamp));
        (this.instance.exports.projectStarsWasm as any)(location_ptr, BigInt(timestamp));
    }

    projectConstellationBranch(branches: ConstellationBranch[], location: Coord, timestamp: number) {
        // const branches_ptr = this.allocArray(branches, sizedConstellationBranch);
        // const location_ptr = this.allocObject(location, sizedCoord);
        // (this.instance.exports.projectConstellation as any)(branches_ptr, branches.length, location_ptr, BigInt(timestamp));
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

    dragAndMove(drag_start_x: number, drag_start_y: number, drag_end_x: number, drag_end_y: number): Coord {
        const res_ptr = (this.instance.exports.dragAndMoveWasm as any)(drag_start_x, drag_start_y, drag_end_x, drag_end_y);
        const result = this.readObject(res_ptr, sizedCoord);
        this.freeBytes(res_ptr, sizeOf(sizedCanvasPoint));

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

    private allocObject<T extends Allocatable>(data: T, size: Sized<T>): pointer {
        const total_bytes = sizeOf(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        this.setObject(data_mem, data, size);
        return ptr;
    }

    private readObject<T extends Allocatable>(ptr: pointer, size: Sized<T>): T {
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

    private allocArray<T extends Allocatable>(data: T[], size: Sized<T>): pointer {
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

    private readArray<T extends Allocatable>(ptr: pointer, num_items: number, size: Sized<T>): T[] {
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

    private allocBytes(num_bytes: number): pointer {
        return (this.instance.exports as any)._wasm_alloc(num_bytes);
    }

    private freeBytes(location: pointer, num_bytes: number): void {
        (this.instance.exports as any)._wasm_free(location, num_bytes);
    }

    private setObject<T extends Allocatable>(mem: DataView, data: T, type: Sized<T>, offset = 0): number {
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

    private getObject<T extends Allocatable>(mem: DataView, type: Sized<T>, offset = 0): T {
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

const sizeOf = <T extends Allocatable>(type: Sized<T>): number => {
    let size = 0;
    if (isSimpleSize(type)) {
        for (const key in type) {
            if (type.hasOwnProperty(key)) {
                size += sizeOfPrimative(type[key]);
            }
        }
    } else if (isComplexSize(type)) {
        for (const key in type) {
            if (type.hasOwnProperty(key)) {
                size += sizeOf(type[key]);
            }
        }
    }
    return size;
};
