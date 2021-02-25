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
    SkyCoord,
} from './size';
import { CanvasSettings } from '../renderer';

interface WasmFns {
    initializeStars: (star_data: pointer<WasmStar>, star_len: number) => void;
    initializeCanvas: (settings: pointer<CanvasSettings>) => void;
    initializeConstellations: (
        grid_data: pointer<pointer<SkyCoord>>,
        asterism_data: pointer<pointer<SkyCoord>>,
        grid_coord_lens: pointer<number>,
        asterism_coord_lens: pointer<number>,
        num_constellations: number
    ) => void;
    updateCanvasSettings: (settings: pointer<CanvasSettings>) => void;
    getImageData: (size_in_bytes: pointer<number>) => pointer<number>;
    resetImageData: () => void;
    projectStars: (
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt,
        mat_count: pointer<number>
    ) => pointer<pointer<any>>;
    // projectStars: (observer_latitude: number, observer_longitude: number, observer_timestamp: BigInt) => void;
    projectConstellationGrids: (observer_latitude: number, observer_longitude: number, observer_timestamp: BigInt) => void;
    getConstellationAtPoint: (
        point: pointer<CanvasPoint>,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => number;
    getConstellationCentroid: (constellation_index: number) => pointer<SkyCoord>;
    dragAndMove: (drag_start_x: number, drag_start_y: number, drag_end_x: number, drag_end_y: number) => pointer<Coord>;
    findWaypoints: (start: pointer<Coord>, end: pointer<Coord>, num_waypoints: pointer<number>) => pointer<Coord>;
    getCoordForSkyCoord: (sky_coord: pointer<SkyCoord>, observer_timestamp: BigInt) => pointer<Coord>;
    getSkyCoordForCanvasPoint: (
        point: pointer<CanvasPoint>,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => pointer<SkyCoord>;
    getCoordForCanvasPoint: (
        point: pointer<CanvasPoint>,
        observer_latitude: number,
        observer_longitude: number,
        observer_timestamp: BigInt
    ) => pointer<Coord>;
    getProjectionMatrix2d: (width: number, height: number) => pointer<any>;
    getTranslationMatrix2d: (tx: number, ty: number) => pointer<any>;
    getRotationMatrix2d: (radians: number) => pointer<any>;
    getScalingMatrix2d: (sx: number, sy: number) => pointer<any>;
    matrixMult2d: (a: pointer<any>, b: pointer<any>) => pointer<any>;
    readMatrix2d: (m: pointer<any>) => pointer<number[]>;
    freeMatrix2d: (m: pointer<any>) => void;
    getProjectionMatrix3d: (width: number, height: number, depth: number) => pointer<any>;
    getTranslationMatrix3d: (tx: number, ty: number, tz: number) => pointer<any>;
    getXRotationMatrix3d: (radians: number) => pointer<any>;
    getYRotationMatrix3d: (radians: number) => pointer<any>;
    getZRotationMatrix3d: (radians: number) => pointer<any>;
    getScalingMatrix3d: (sx: number, sy: number, sz: number) => pointer<any>;
    getOrthographicMatrix3d: (left: number, right: number, bottom: number, top: number, near: number, far: number) => pointer<any>;
    getPerspectiveMatrix3d: (fov: number, aspect_ratio: number, near: number, far: number) => pointer<any>;
    matrixMult3d: (a: pointer<any>, b: pointer<any>) => pointer<any>;
    readMatrix3d: (m: pointer<any>) => pointer<number[]>;
    freeMatrix3d: (m: pointer<any>) => void;
    getSphereVertices: (length_ptr: pointer<number>) => pointer<number[]>;
    getSphereIndices: (length_ptr: pointer<number>) => pointer<number[]>;
}

export class WasmInterface {
    private lib: WasmFns;

    constructor(private instance: WebAssembly.Instance) {
        this.lib = this.instance.exports as any;
    }

    initialize(stars: Star[], constellations: Constellation[], canvas_settings: CanvasSettings): void {
        const boundaries: pointer<SkyCoord>[] = [];
        const asterisms: pointer<SkyCoord>[] = [];
        for (const c of constellations) {
            const bound_coords_ptr = this.allocArray(c.boundaries, sizedSkyCoord);
            const aster_coords_ptr = this.allocArray(c.asterism, sizedSkyCoord);
            boundaries.push(bound_coords_ptr);
            asterisms.push(aster_coords_ptr);
        }
        const boundaries_ptr = this.allocPrimativeArray(boundaries, WasmPrimative.u32);
        const asterisms_ptr = this.allocPrimativeArray(asterisms, WasmPrimative.u32);
        const boundary_lengths = constellations.map(c => c.boundaries.length);
        const bound_coord_lens_ptr = this.allocPrimativeArray(boundary_lengths, WasmPrimative.u32);
        const asterism_lengths = constellations.map(c => c.asterism.length);
        const aster_coord_lens_ptr = this.allocPrimativeArray(asterism_lengths, WasmPrimative.u32);
        this.lib.initializeConstellations(boundaries_ptr, asterisms_ptr, bound_coord_lens_ptr, aster_coord_lens_ptr, constellations.length);

        const wasm_stars: WasmStar[] = stars.map(star => {
            return {
                right_ascension: star.right_ascension,
                declination: star.declination,
                brightness: star.brightness,
                spec_type: star.spec_type,
            };
        });
        const star_ptr = this.allocArray(wasm_stars, sizedWasmStar);
        this.lib.initializeStars(star_ptr, wasm_stars.length);
        const settings_ptr = this.allocObject(canvas_settings, sizedCanvasSettings);
        this.lib.initializeCanvas(settings_ptr);
    }

    projectStars(latitude: number, longitude: number, timestamp: BigInt): number[][] {
        const result_len_ptr = this.allocBytes(4);
        const result_ptr = this.lib.projectStars(latitude, longitude, timestamp, result_len_ptr);
        const result_len = this.readPrimative(result_len_ptr, WasmPrimative.u32);
        this.freeBytes(result_len_ptr, 4);
        // return Array.from(new Uint32Array(this.memory, result_ptr, result_len));
        // const result = Array.from(new Uint32Array(this.memory, result_ptr, result_len));
        const result = Array.from(new Float32Array(this.memory, result_ptr, result_len));
        this.freeBytes(result_ptr, sizeOfPrimative(WasmPrimative.u32) * result_len);

        const matrices: number[][] = [];
        for (let i = 0; i < result.length; i += 16) {
            matrices.push(result.slice(i, i + 16));
        }

        return matrices;
        // return result;
    }

    projectConstellationGrids(latitude: number, longitude: number, timestamp: BigInt): void {
        this.lib.projectConstellationGrids(latitude, longitude, timestamp);
    }

    getConstellationAtPoint(point: CanvasPoint, latitude: number, longitude: number, timestamp: BigInt): number {
        const point_ptr = this.allocObject(point, sizedCanvasPoint);
        const constellation_index = this.lib.getConstellationAtPoint(point_ptr, latitude, longitude, timestamp);
        return constellation_index;
    }

    getCosntellationCentroid(index: number): SkyCoord | null {
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

    findWaypoints(start: Coord, end: Coord): Coord[] {
        const num_waypoints_ptr = this.allocBytes(4);
        const start_ptr = this.allocObject(start, sizedCoord);
        const end_ptr = this.allocObject(end, sizedCoord);
        const result_ptr = this.lib.findWaypoints(start_ptr, end_ptr, num_waypoints_ptr);
        const num_waypoints = this.readPrimative(num_waypoints_ptr, WasmPrimative.u32);
        const waypoints = this.readArray(result_ptr, num_waypoints, sizedCoord);
        this.freeBytes(num_waypoints_ptr, 4);
        this.freeBytes(result_ptr, num_waypoints * sizeOf(sizedCoord));
        return waypoints;
    }

    dragAndMove(drag_start: Coord, drag_end: Coord): Coord {
        const result_ptr = this.lib.dragAndMove(drag_start.latitude, drag_start.longitude, drag_end.latitude, drag_end.longitude);
        const result: Coord = this.readObject(result_ptr, sizedCoord);
        this.freeBytes(result_ptr, sizeOf(sizedCoord));
        return result;
    }

    getCoordForSkyCoord(sky_coord: SkyCoord, timestamp: BigInt): Coord {
        const sky_coord_ptr = this.allocObject(sky_coord, sizedSkyCoord);
        const coord_ptr = this.lib.getCoordForSkyCoord(sky_coord_ptr, timestamp);
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
        const point_ptr = this.allocObject(point, sizedCanvasPoint);
        const sky_coord_ptr = this.lib.getSkyCoordForCanvasPoint(point_ptr, observer_latitude, observer_longitude, observer_timestamp);
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
        const point_ptr = this.allocObject(point, sizedCanvasPoint);
        const coord_ptr = this.lib.getCoordForCanvasPoint(point_ptr, observer_latitude, observer_longitude, observer_timestamp);
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

    getProjectionMatrix2d(width: number, height: number): number {
        return this.lib.getProjectionMatrix2d(width, height);
    }

    getProjectionMatrix3d(width: number, height: number, depth: number): number {
        return this.lib.getProjectionMatrix3d(width, height, depth);
    }

    getTranslationMatrix2d(tx: number, ty: number): number {
        return this.lib.getTranslationMatrix2d(tx, ty);
    }

    getTranslationMatrix3d(tx: number, ty: number, tz: number): number {
        return this.lib.getTranslationMatrix3d(tx, ty, tz);
    }

    getRotationMatrix2d(radians: number): number {
        return this.lib.getRotationMatrix2d(radians);
    }

    getXRotationMatrix3d(radians: number): number {
        return this.lib.getXRotationMatrix3d(radians);
    }

    getYRotationMatrix3d(radians: number): number {
        return this.lib.getYRotationMatrix3d(radians);
    }

    getZRotationMatrix3d(radians: number): number {
        return this.lib.getZRotationMatrix3d(radians);
    }

    getScalingMatrix2d(sx: number, sy: number): number {
        return this.lib.getScalingMatrix2d(sx, sy);
    }

    getScalingMatrix3d(sx: number, sy: number, sz: number): number {
        return this.lib.getScalingMatrix3d(sx, sy, sz);
    }

    getOrthographicMatrix3d(left: number, right: number, bottom: number, top: number, near: number, far: number): number {
        return this.lib.getOrthographicMatrix3d(left, right, bottom, top, near, far);
    }

    getPerspectiveMatrix3d(fov: number, aspect_ratio: number, near: number, far: number): number {
        return this.lib.getPerspectiveMatrix3d(fov, aspect_ratio, near, far);
    }

    getSphereVertices(): Float32Array {
        const result_len_ptr = this.allocBytes(4);
        const result_ptr = this.lib.getSphereVertices(result_len_ptr);

        const result_len = this.readPrimative(result_len_ptr, WasmPrimative.u32);
        this.freeBytes(result_len_ptr, 4);

        return new Float32Array(this.memory, result_ptr, result_len);
    }

    getSphereIndices(): Uint32Array {
        const result_len_ptr = this.allocBytes(4);
        const result_ptr = this.lib.getSphereIndices(result_len_ptr);

        const result_len = this.readPrimative(result_len_ptr, WasmPrimative.u32);
        // const result = this.readPrimativeArray(result_ptr, result_len, WasmPrimative.u32);

        return new Uint32Array(this.memory, result_ptr, result_len);
    }

    matrixMult2d(a: number, b: number): number {
        const res = this.lib.matrixMult2d(a, b);
        this.lib.freeMatrix2d(a);
        this.lib.freeMatrix2d(b);
        return res;
    }

    matrixMult3d(a: number, b: number): number {
        const res = this.lib.matrixMult3d(a, b);
        this.lib.freeMatrix3d(a);
        this.lib.freeMatrix3d(b);
        return res;
    }

    readMatrix2d(a: number): Float32Array {
        const data = this.lib.readMatrix2d(a);
        return new Float32Array(this.memory, data, 9);
    }

    readMatrix3d(a: number): Float32Array {
        const data = this.lib.readMatrix3d(a);
        return new Float32Array(this.memory, data, 16);
    }

    freeMatrix2d(a: number): void {
        this.lib.freeMatrix2d(a);
    }

    freeMatrix3d(a: number): void {
        this.lib.freeMatrix3d(a);
    }

    getString(ptr: pointer<string>, len: number): string {
        const message_mem = this.readBytes(ptr, len);
        const decoder = new TextDecoder();
        return decoder.decode(message_mem);
    }

    allocPrimative(data: number, size: WasmPrimative): pointer<number> {
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

    readPrimative(ptr: pointer<number>, size: WasmPrimative): number {
        const total_bytes = sizeOfPrimative(size);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        return this.getPrimative(data_mem, size) as number;
    }

    allocString(data: string): pointer<string> {
        const ptr = this.allocBytes(data.length);
        const encoder = new TextEncoder();
        const data_mem = new DataView(this.memory, ptr, data.length);
        const encoded_data = encoder.encode(data);

        for (const [index, char] of encoded_data.entries()) {
            data_mem.setUint8(index, char);
        }

        return ptr;
    }

    allocObject<T extends Allocatable>(data: T, size: Sized<T>): pointer<T> {
        const total_bytes = sizeOf(size);
        const ptr = this.allocBytes(total_bytes);
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        this.setObject(data_mem, data, size);
        return ptr;
    }

    readObject<T extends Allocatable>(ptr: pointer<T>, size: Sized<T>): T {
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

    allocArray<T extends Allocatable>(data: T[], size: Sized<T>): pointer<T> {
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

    allocPrimativeArray(data: number[], size: WasmPrimative): pointer<number> {
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

    readArray<T extends Allocatable>(ptr: pointer<T>, num_items: number, size: Sized<T>): T[] {
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

    readPrimativeArray(ptr: pointer<number>, num_items: number, type: WasmPrimative): number[] {
        const item_bytes = sizeOfPrimative(type);
        const total_bytes = item_bytes * num_items;
        const data_mem = new DataView(this.memory, ptr, total_bytes);
        const result_array: number[] = new Array(num_items);

        for (let current_offset = 0; current_offset < total_bytes; current_offset += item_bytes) {
            const value = this.getPrimative(data_mem, WasmPrimative.u32, current_offset) as number;
            result_array.push(value);
        }

        return result_array;
    }

    readBytes(location: pointer<any>, num_bytes: number): ArrayBuffer {
        return this.memory.slice(location, location + num_bytes);
    }

    allocBytes(num_bytes: number): pointer<any> {
        return (this.instance.exports as any)._wasm_alloc(num_bytes);
    }

    freeBytes(location: pointer<any>, num_bytes: number): void {
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
            case WasmPrimative.bool: {
                mem.setUint8(offset, val);
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
