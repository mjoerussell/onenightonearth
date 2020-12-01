import { CanvasPoint } from './wasm/size';

type CanvasId = 'alpha' | 'beta';

interface CanvasOptions {
    width?: number;
    height?: number;
}

export interface PixelData {
    x: number;
    y: number;
    color: {
        r: number;
        g: number;
        b: number;
        a: number;
    };
}

export class Renderer {
    private main_canvas: HTMLCanvasElement;
    private main_ctx: CanvasRenderingContext2D;
    private offscreen_canvas: HTMLCanvasElement;
    private offscreen_ctx: CanvasRenderingContext2D;

    private readonly default_width = 700;
    private readonly default_height = 700;

    background_radius: number;
    zoom_factor: number = 1.0;
    draw_north_up: boolean = true;

    constructor(alpha_id: string, beta_id: string, options?: CanvasOptions) {
        this.main_canvas = document.getElementById(alpha_id) as HTMLCanvasElement;
        this.main_ctx = this.main_canvas.getContext('2d')!;

        this.main_canvas.width = options?.width ?? this.default_width;
        this.main_canvas.height = options?.height ?? this.default_height;

        this.background_radius = 0.45 * Math.min(this.width, this.height);

        this.offscreen_canvas = document.createElement('canvas');
        this.offscreen_ctx = this.offscreen_canvas.getContext('2d')!;

        this.offscreen_canvas.width = this.width;
        this.offscreen_canvas.height = this.height;
    }

    swapBuffers(): void {
        this.main_ctx.clearRect(0, 0, this.width, this.height);
        this.main_ctx.drawImage(this.offscreen_canvas, 0, 0);
        this.offscreen_ctx.clearRect(0, 0, this.width, this.height);
    }

    run(draw_commands: (ctx: CanvasRenderingContext2D) => void): void {
        draw_commands(this.offscreen_ctx);
    }

    addEventListener<K extends keyof DocumentEventMap>(event_name: K, event_handler: (e: DocumentEventMap[K]) => void): void {
        this.main_canvas.addEventListener(event_name, (event: any) => {
            event_handler(event);
        });
    }

    get width(): number {
        return this.main_canvas.width;
    }

    get height(): number {
        return this.main_canvas.height;
    }

    get canvas() {
        return this.main_canvas;
    }
}
