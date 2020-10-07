var WasmPrimative;
(function (WasmPrimative) {
    WasmPrimative[WasmPrimative["u8"] = 0] = "u8";
    WasmPrimative[WasmPrimative["u16"] = 1] = "u16";
    WasmPrimative[WasmPrimative["u32"] = 2] = "u32";
    WasmPrimative[WasmPrimative["u64"] = 3] = "u64";
    WasmPrimative[WasmPrimative["i8"] = 4] = "i8";
    WasmPrimative[WasmPrimative["i16"] = 5] = "i16";
    WasmPrimative[WasmPrimative["i32"] = 6] = "i32";
    WasmPrimative[WasmPrimative["i64"] = 7] = "i64";
    WasmPrimative[WasmPrimative["f32"] = 8] = "f32";
    WasmPrimative[WasmPrimative["f64"] = 9] = "f64";
})(WasmPrimative || (WasmPrimative = {}));
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
const sizedCoord = {
    latitude: f32,
    longitude: f32,
};
const sizedCanvasPoint = {
    x: f32,
    y: f32,
    brightness: f32,
};
const sizedStar = {
    rightAscension: f32,
    declination: f32,
    brightness: f32,
};
export class WasmInterface {
    constructor(instance) {
        this.instance = instance;
    }
    projectStars(stars, location, timestamp) {
        const star_ptr = this.allocArray(stars, sizedStar);
        const location_ptr = this.allocObject(location, sizedCoord);
        this.instance.exports.projectStarsWasm(star_ptr, stars.length, location_ptr, BigInt(timestamp));
    }
    /**
     * Compute waypoints along the great circle between two points. This results in a direct line between
     * the given points along the surface of a sphere.
     * @param starting_location The location to start at.
     * @param end_location      The location to end up at.
     * @param num_waypoints     The number of waypoints to compute. Defaults to `100`.
     * @return An array of length `num_waypoints` of Coords representing a path between `starting_location` and `end_location`.
     */
    getWaypoints(starting_location, end_location, num_waypoints = 100) {
        const start_ptr = this.allocObject(starting_location, sizedCoord);
        const end_ptr = this.allocObject(end_location, sizedCoord);
        const res_ptr = this.instance.exports.findWaypointsWasm(start_ptr, end_ptr, num_waypoints);
        const result = this.readArray(res_ptr, num_waypoints, sizedCoord);
        this.freeBytes(res_ptr, sizeOf(sizedCoord) * num_waypoints);
        return result;
    }
    dragAndMove(drag_start_x, drag_start_y, drag_end_x, drag_end_y) {
        const res_ptr = this.instance.exports.dragAndMoveWasm(drag_start_x, drag_start_y, drag_end_x, drag_end_y);
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
    projectCoord(altitude, azimuth, brightness = 1.0) {
        const res_ptr = this.instance.exports.getProjectedCoordWasm(altitude, azimuth, brightness);
        const result = this.readObject(res_ptr, sizedCanvasPoint);
        this.freeBytes(res_ptr, sizeOf(sizedCanvasPoint));
        return result;
    }
    getString(ptr, len) {
        const message_mem = this.memory.slice(ptr, ptr + len);
        const decoder = new TextDecoder();
        return decoder.decode(message_mem);
    }
    allocPrimative(data, size) {
        const total_bytes = sizeOfPrimative(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        try {
            this.setPrimative(data_mem, data, size, 0);
        }
        catch (error) {
            if (error instanceof RangeError) {
                console.error(`RangeError: Could not allocate primative (size = ${total_bytes}) for DataView with size ${data_mem.byteLength}`);
            }
            else {
                throw error;
            }
        }
        return ptr;
    }
    readPrimative(ptr, size) {
        const total_bytes = sizeOfPrimative(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        return this.getPrimative(data_mem, size);
    }
    allocString(data) {
        const ptr = this.allocBytes(data.length);
        const encoder = new TextEncoder();
        const data_mem = new DataView(this.memory, ptr, data.length);
        const encoded_data = encoder.encode(data);
        for (const [index, char] of encoded_data.entries()) {
            data_mem.setUint8(index, char);
        }
        return ptr;
    }
    allocObject(data, size) {
        const total_bytes = sizeOf(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        for (const key in data) {
            try {
                this.setPrimative(data_mem, data[key], size[key], current_offset);
            }
            catch (error) {
                if (error instanceof RangeError) {
                    console.error(`RangeError: Index ${current_offset} (size = ${sizeOfPrimative(size[key])}) is out of bounds of DataView [total_bytes = ${data_mem.byteLength}] for type`);
                }
            }
            current_offset += sizeOfPrimative(size[key]);
        }
        return ptr;
    }
    readObject(ptr, size) {
        const total_bytes = sizeOf(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        const result = {};
        let current_offset = 0;
        for (const key in size) {
            const value = this.getPrimative(data_mem, size[key], current_offset);
            result[key] = value;
            current_offset += sizeOfPrimative(size[key]);
        }
        return result;
    }
    allocArray(data, size) {
        const item_bytes = sizeOf(size);
        const total_bytes = item_bytes * data.length;
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        for (const item of data) {
            for (const key in item) {
                try {
                    this.setPrimative(data_mem, item[key], size[key], current_offset);
                }
                catch (error) {
                    if (error instanceof RangeError) {
                        console.error(`RangeError: Index ${current_offset} (size = ${sizeOfPrimative(size[key])}) is out of bounds of DataView [total_bytes = ${data_mem.byteLength}] for type`);
                    }
                }
                current_offset += sizeOfPrimative(size[key]);
            }
        }
        return ptr;
    }
    readArray(ptr, num_items, size) {
        const total_bytes = sizeOf(size) * num_items;
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        let current_offset = 0;
        const result_array = new Array(num_items);
        for (let index = 0; index < num_items; index += 1) {
            const result = {};
            for (const key in size) {
                const value = this.getPrimative(data_mem, size[key], current_offset);
                result[key] = value;
                current_offset += sizeOfPrimative(size[key]);
            }
            result_array[index] = result;
        }
        return result_array;
    }
    allocBytes(num_bytes) {
        return this.instance.exports._wasm_alloc(num_bytes);
    }
    freeBytes(location, num_bytes) {
        this.instance.exports._wasm_free(location, num_bytes);
    }
    setPrimative(mem, value, type, offset = 0) {
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
    getPrimative(mem, type, offset = 0) {
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
    get memory() {
        return this.instance.exports.memory.buffer;
    }
}
const sizeOfPrimative = (data) => {
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
const sizeOf = (data) => {
    let size = 0;
    for (const key in data) {
        if (data.hasOwnProperty(key)) {
            size += sizeOfPrimative(data[key]);
        }
    }
    return size;
};
//# sourceMappingURL=wasm.js.map