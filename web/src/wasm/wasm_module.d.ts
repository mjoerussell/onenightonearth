// This file was auto-generated by night-math/generate_interface.zig
export type pointer = number;
export interface WasmModule {
	memory: WebAssembly.Memory;
	initialize: (arg_0: pointer, arg_1: number, arg_2: pointer, arg_3: pointer) => void;
	updateCanvasSettings: (arg_0: pointer) => pointer;
	initializeResultData: () => pointer;
	getImageData: () => pointer;
	resetImageData: () => void;
	projectStarsAndConstellations: (arg_0: number, arg_1: number, arg_2: BigInt) => void;
	getConstellationAtPoint: (arg_0: number, arg_1: number, arg_2: number, arg_3: number, arg_4: BigInt) => BigInt;
	dragAndMove: (arg_0: number, arg_1: number, arg_2: number, arg_3: number) => void;
	findWaypoints: (arg_0: number, arg_1: number, arg_2: number, arg_3: number) => pointer;
	getCoordForSkyCoord: (arg_0: number, arg_1: number, arg_2: BigInt) => void;
	getConstellationCentroid: (arg_0: number) => void;
	_wasm_alloc: (arg_0: number) => pointer;
	_wasm_free: (arg_0: pointer, arg_1: number) => void;
};
