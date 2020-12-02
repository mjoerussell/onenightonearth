interface CanvasOptions {
    width?: number;
    height?: number;
}

export class Renderer {
    /**
     * The main canvas is the one that's shown to the user. It's only drawn to in single batches, once the workers
     * have finished drawing everything to the offscreen buffer.
     */
    private main_canvas: HTMLCanvasElement;
    private main_ctx: CanvasRenderingContext2D;

    /**
     * The offscreen canvas gets drawn to continuously by each worker. Once all the workers are done, then the
     * content of this canvas is copied onto the main canvas so that the user can see it.
     */
    private offscreen_canvas: HTMLCanvasElement;
    private offscreen_ctx: CanvasRenderingContext2D;

    private readonly default_width = 700;
    private readonly default_height = 700;

    background_radius: number;
    zoom_factor: number = 1.0;
    draw_north_up: boolean = true;

    constructor(canvas_id: string, options?: CanvasOptions) {
        this.main_canvas = document.getElementById(canvas_id) as HTMLCanvasElement;
        this.main_ctx = this.main_canvas.getContext('2d')!;

        this.main_canvas.width = options?.width ?? this.default_width;
        this.main_canvas.height = options?.height ?? this.default_height;

        this.background_radius = 0.45 * Math.min(this.width, this.height);

        this.offscreen_canvas = document.createElement('canvas');
        this.offscreen_ctx = this.offscreen_canvas.getContext('2d')!;

        this.offscreen_canvas.width = this.width;
        this.offscreen_canvas.height = this.height;
    }

    /**
     * Push the offscreen canvas buffer to the main buffer, then clear the offscreen buffer.
     */
    pushBuffer(): void {
        this.main_ctx.clearRect(0, 0, this.width, this.height);
        this.main_ctx.drawImage(this.offscreen_canvas, 0, 0);
        this.offscreen_ctx.clearRect(0, 0, this.width, this.height);
    }

    /**
     * Add an event listener to the main canvas.
     * @param event_name
     * @param event_handler
     */
    addEventListener<K extends keyof DocumentEventMap>(event_name: K, event_handler: (e: DocumentEventMap[K]) => void): void {
        this.main_canvas.addEventListener(event_name, (event: any) => {
            event_handler(event);
        });
    }

    /**
     * The width of the canvas.
     */
    get width(): number {
        return this.main_canvas.width;
    }

    /**
     * The height of the canvas.
     */
    get height(): number {
        return this.main_canvas.height;
    }

    /**
     * The user-facing canvas.
     */
    get canvas() {
        return this.main_canvas;
    }

    get context() {
        return this.offscreen_ctx;
    }
}
