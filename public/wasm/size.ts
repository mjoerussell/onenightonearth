import { CanvasSettings } from '../renderer';

/**
 * Simple primative types that can be passed to WASM functions directly, and whose sizes
 * can be known trivially.
 */
export enum WasmPrimative {
    bool,
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

export type pointer = number;

/**
 * An Earth coordinate, used to determine the location of an observer.
 */
export type Coord = {
    latitude: number;
    longitude: number;
};

export const sizedCoord: Sized<Coord> = {
    latitude: WasmPrimative.f32,
    longitude: WasmPrimative.f32,
};

export type Constellation = {
    name: string;
    /**
     * This is roughly and English translation of the constellation name. For example, the epithet for
     * Aries is "The Ram".
     */
    epithet: string;
};

/**
 * A `SkyCoord` is the star equivalent of an Earth coord. Locations in space are noted using
 * right ascension and declination, a system roughly corresponding to longitude and latitude, respectively.
 */
export type SkyCoord = {
    right_ascension: number;
    declination: number;
};

export const sizedSkyCoord: Sized<SkyCoord> = {
    right_ascension: WasmPrimative.f32,
    declination: WasmPrimative.f32,
};

/**
 * A location on the drawing canvas. (0, 0) is the top-left corner.
 */
export type CanvasPoint = {
    x: number;
    y: number;
};

export const sizedCanvasPoint: Sized<CanvasPoint> = {
    x: WasmPrimative.f32,
    y: WasmPrimative.f32,
};

export const sizedCanvasSettings: Sized<CanvasSettings> = {
    width: WasmPrimative.u32,
    height: WasmPrimative.u32,
    background_radius: WasmPrimative.f32,
    zoom_factor: WasmPrimative.f32,
    drag_speed: WasmPrimative.f32,
    draw_north_up: WasmPrimative.bool,
    draw_constellation_grid: WasmPrimative.bool,
    draw_asterisms: WasmPrimative.bool,
    zodiac_only: WasmPrimative.bool,
};

/**
 * A `SimpleAlloc` is a struct whose fields are just numbers. This means that it can
 * be allocated and read just using `getPrimative` and `setPrimative`.
 */
export type Allocatable = {
    [key: string]: number | boolean;
};

/**
 * `Sized` types are companions to `Allocatable` types. For every type `T` that extends `Allocatable`, there must be an implementation
 * of `Sized<T>` which defines the size in bytes of every field on `T`.
 */
export type Sized<T extends Allocatable> = {
    [K in keyof T]: WasmPrimative;
};

/**
 * Get the number of bytes needed to store a given `WasmPrimative`.
 * @param data The primative type being checked.
 */
export const sizeOfPrimative = (data: WasmPrimative): number => {
    switch (data) {
        case WasmPrimative.bool:
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
    for (const key in type) {
        if (type.hasOwnProperty(key)) {
            size += sizeOfPrimative(type[key] as WasmPrimative);
        }
    }
    return size;
};
