import { ExternCanvasSettings } from './wasm/wasm_module';
export class CanvasSettings {
    width: number;
    height: number;
    background_radius: number;
    zoom_factor: number;
    drag_speed: number;
    draw_north_up: boolean;
    draw_constellation_grid: boolean;
    draw_asterisms: boolean;
    zodiac_only: boolean;

    constructor(width: number, height: number) {
        this.width = width;
        this.height = height;
        this.background_radius = 0.5 * Math.min(width, height);
        this.zoom_factor = 1.0;
        this.drag_speed = Renderer.DefaultDragSpeed;
        this.draw_north_up = true;
        this.draw_constellation_grid = false;
        this.draw_asterisms = false;
        this.zodiac_only = false;
    }

    public toExtern(): ExternCanvasSettings {
        return {
            width: this.width,
            height: this.height,
            background_radius: this.background_radius,
            zoom_factor: this.zoom_factor,
            drag_speed: this.drag_speed,
            draw_north_up: this.draw_north_up ? 1 : 0,
            draw_constellation_grid: this.draw_constellation_grid ? 1 : 0,
            draw_asterisms: this.draw_asterisms ? 1 : 0,
            zodiac_only: this.zodiac_only ? 1 : 0,
        };
    }
}

interface Canvas {
    id: string;
    canvas: HTMLCanvasElement;
    context: CanvasRenderingContext2D;
}

export class Renderer {
    public static readonly DefaultDragSpeed = 1.3;
    public static readonly DefaultMobileDragSpeed = 1;
    /**
     * The main canvas is the one that's shown to the user. It's only drawn to in single batches, once the workers
     * have finished drawing everything to the offscreen buffer.
     */
    private main_canvas: Canvas;

    private settings: CanvasSettings;

    private _settings_did_change = true;

    constructor(main_canvas_id: string) {
        const main_canvas = document.getElementById(main_canvas_id) as HTMLCanvasElement;
        const main_canvas_context = main_canvas.getContext('2d')!;

        this.main_canvas = {
            id: main_canvas_id,
            canvas: main_canvas,
            context: main_canvas_context,
        };

        const canvas_dim = main_canvas.clientWidth < main_canvas.clientHeight ? main_canvas.clientWidth : main_canvas.clientHeight;

        this.main_canvas.canvas.width = canvas_dim;
        this.main_canvas.canvas.height = canvas_dim;

        this.settings = new CanvasSettings(this.main_canvas.canvas.width, this.main_canvas.canvas.height);
    }

    /**
     * Given pixel data as a `Uint8ClampedArray`, put the image onto the canvas using `canvas.putImageData`.
     * @param data The pixel data buffer.
     */
    drawData(data: Uint8ClampedArray): void {
        try {
            const image_data = new ImageData(data, this.main_canvas.canvas.width, this.main_canvas.canvas.height);
            this.main_canvas.context.putImageData(image_data, 0, 0);
        } catch (error) {
            if (error instanceof DOMException) {
                console.error('DOMException in drawPoint: ', error);
            }
        }
    }

    /**
     * Add an event listener to the main canvas.
     * @param event_name
     * @param event_handler
     */
    addEventListener<K extends keyof DocumentEventMap>(event_name: K, event_handler: (e: DocumentEventMap[K]) => void): void {
        this.main_canvas.canvas.addEventListener(event_name, (event: any) => {
            event_handler(event);
        });
    }

    getCanvasSettings(): CanvasSettings {
        this._settings_did_change = false;
        return this.settings;
    }

    /**
     * The width of the canvas.
     */
    get width(): number {
        return this.settings.width;
    }

    set width(value: number) {
        this._settings_did_change = true;
        this.settings.width = value;
        this.main_canvas.canvas.width = value;
        this.settings.background_radius = 0.5 * Math.min(this.width, this.height);
    }

    /**
     * The height of the canvas.
     */
    get height(): number {
        return this.settings.height;
    }

    set height(value: number) {
        this._settings_did_change = true;
        this.settings.height = value;
        this.main_canvas.canvas.height = value;
        this.settings.background_radius = 0.5 * Math.min(this.width, this.height);
    }

    get background_radius() {
        return this.settings.background_radius;
    }

    get zoom_factor() {
        return this.settings.zoom_factor;
    }

    set zoom_factor(f: number) {
        this.settings.zoom_factor = f;
        this._settings_did_change = true;
    }

    get draw_north_up() {
        return this.settings.draw_north_up;
    }

    set draw_north_up(d: boolean) {
        this.settings.draw_north_up = d;
        this._settings_did_change = true;
    }

    get settings_did_change() {
        return this._settings_did_change;
    }

    /**
     * The user-facing canvas.
     */
    get canvas() {
        return this.main_canvas.canvas;
    }

    get context() {
        return this.main_canvas.context;
    }

    set draw_constellation_grid(value: boolean) {
        this._settings_did_change = true;
        this.settings.draw_constellation_grid = value;
    }

    get draw_constellation_grid(): boolean {
        return this.settings.draw_constellation_grid;
    }

    set draw_asterisms(value: boolean) {
        this._settings_did_change = true;
        this.settings.draw_asterisms = value;
    }

    get draw_asterisms(): boolean {
        return this.settings.draw_asterisms;
    }

    set zodiac_only(value: boolean) {
        this._settings_did_change = true;
        this.settings.zodiac_only = value;
    }

    get zodiac_only(): boolean {
        return this.settings.zodiac_only;
    }

    set drag_speed(value: number) {
        this._settings_did_change = true;
        this.settings.drag_speed = value;
    }

    get drag_speed(): number {
        return this.drag_speed;
    }
}
