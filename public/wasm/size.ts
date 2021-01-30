import { CanvasSettings } from '../renderer';

export enum WasmPrimative {
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

export type Coord = {
    latitude: number;
    longitude: number;
};

export const sizedCoord: Sized<Coord> = {
    latitude: WasmPrimative.f32,
    longitude: WasmPrimative.f32,
};

export type Star = {
    name: string;
    right_ascension: number;
    declination: number;
    brightness: number;
};

export type WasmStar = {
    right_ascension: number;
    declination: number;
    brightness: number;
};

export const sizedWasmStar: Sized<WasmStar> = {
    right_ascension: WasmPrimative.f32,
    declination: WasmPrimative.f32,
    brightness: WasmPrimative.f32,
};

export type StarCoord = {
    rightAscension: number;
    declination: number;
};

const sizedStarCoord: Sized<StarCoord> = {
    rightAscension: WasmPrimative.f32,
    declination: WasmPrimative.f32,
};

export type ConstellationBranch = {
    a: StarCoord;
    b: StarCoord;
};

export const sizedConstellationBranch: Sized<ConstellationBranch> = {
    a: sizedStarCoord,
    b: sizedStarCoord,
};

export const sizedCanvasSettings: Sized<CanvasSettings> = {
    width: WasmPrimative.u32,
    height: WasmPrimative.u32,
    background_radius: WasmPrimative.f32,
    zoom_factor: WasmPrimative.f32,
    draw_north_up: WasmPrimative.u8,
};

/**
 * A `SimpleAlloc` is a struct whose fields are just numbers. This means that it can
 * be allocated and read just using `getPrimative` and `setPrimative`.
 */
export type SimpleAlloc = {
    [key: string]: number | boolean;
};

/**
 * A `SimpleSize` is a size definition for `SimpleAlloc`.
 */
export type SimpleSize<T extends SimpleAlloc> = {
    [K in keyof T]: WasmPrimative;
};

/**
 * `ComplexAlloc` is a struct whose fields are structs. The fields can either be more `ComplexAlloc`'s, or
 * just `SimpleAlloc`'s.
 */
export type ComplexAlloc = {
    [key: string]: Allocatable;
};

/**
 * `ComplexSize` is a size definition for `ComplexAlloc`.
 */
export type ComplexSize<T extends ComplexAlloc> = {
    [K in keyof T]: Sized<T[K]>;
};

/**
 * `Allocatable` types are data types that can be automatically allocated regardless of their complexity.
 */
export type Allocatable = SimpleAlloc | ComplexAlloc;
/**
 * `Sized` types are companions to `Allocatable` types. For every type `T` that extends `Allocatable`, there must be an implementation
 * of `Sized<T>` which defines the size in bytes of every field on `T`.
 */
export type Sized<T extends Allocatable> = T extends SimpleAlloc ? SimpleSize<T> : T extends ComplexAlloc ? ComplexSize<T> : never;

export const isSimpleAlloc = (data: Allocatable): data is SimpleAlloc => {
    for (const key in data) {
        if (data.hasOwnProperty(key)) {
            if (typeof data[key] !== 'number' && typeof data[key] !== 'boolean') {
                return false;
            }
        }
    }
    return true;
};

export const isSimpleSize = (type: Sized<any>): type is SimpleSize<any> => {
    for (const key in type) {
        if (type.hasOwnProperty(key)) {
            if (typeof type[key] !== 'number' && typeof type[key] !== 'boolean') {
                return false;
            }
        }
    }
    return true;
};

export const isComplexSize = (type: Sized<any>): type is ComplexSize<any> => {
    return !isSimpleSize(type);
};

export type pointer = number;

/**
 * Get the number of bytes needed to store a given `WasmPrimative`.
 * @param data The primative type being checked.
 */
export const sizeOfPrimative = (data: WasmPrimative): number => {
    switch (data) {
        case WasmPrimative.u8:
        case WasmPrimative.i8:
            return 1;
        case WasmPrimative.u16:
        case WasmPrimative.i16:
            return 2;
        case WasmPrimative.u32:
        case WasmPrimative.i32:
        case WasmPrimative.f32:
            return 4;
        case WasmPrimative.u64:
        case WasmPrimative.i64:
        case WasmPrimative.f64:
            return 8;
        default:
            return data;
    }
};

/**
 * Get the total size required of an arbitrary `Allocatable` data type.
 * @param type A `Sized` instance of some data type.
 */
export const sizeOf = <T extends Allocatable>(type: Sized<T>): number => {
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
