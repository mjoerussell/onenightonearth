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

export type CanvasPoint = {
    x: number;
    y: number;
    brightness: number;
};

export const sizedCanvasPoint: Sized<CanvasPoint> = {
    x: WasmPrimative.f32,
    y: WasmPrimative.f32,
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

/**
 * A `SimpleAlloc` is a struct whose fields are just numbers. This means that it can
 * be allocated and read just using `getPrimative` and `setPrimative`.
 */
export type SimpleAlloc = {
    [key: string]: number;
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
            if (typeof data[key] !== 'number') {
                return false;
            }
        }
    }
    return true;
};

export const isSimpleSize = (type: Sized<any>): type is SimpleSize<any> => {
    for (const key in type) {
        if (type.hasOwnProperty(key)) {
            if (typeof type[key] !== 'number') {
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
