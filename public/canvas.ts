type CanvasId = 'alpha' | 'beta';

interface CanvasOptions {
    width?: number;
    height?: number;
}

export class MultiCanvas {
    private active_ctx: CanvasId = 'alpha';

    private alpha_ctx: CanvasRenderingContext2D;
    private beta_ctx: CanvasRenderingContext2D;

    constructor(alpha_id: string, beta_id: string, options?: CanvasOptions) {
        const star_canvas_alpha = document.getElementById('star-canvas-alpha') as HTMLCanvasElement;
        this.alpha_ctx = star_canvas_alpha.getContext('2d')!;

        this.alpha_ctx.canvas.width = options?.width ?? 800;
        this.alpha_ctx.canvas.height = options?.height ?? 800;

        const star_canvas_beta = document.getElementById('star-canvas-beta') as HTMLCanvasElement;
        this.beta_ctx = star_canvas_beta.getContext('2d')!;

        this.beta_ctx.canvas.width = options?.width ?? 800;
        this.beta_ctx.canvas.height = options?.height ?? 800;

        this.setActive('alpha');
    }

    private setActive(new_active: CanvasId) {
        this.active_ctx = new_active;
        this.alpha_ctx.canvas.style.display = new_active === 'alpha' ? 'inline' : 'none';
        this.beta_ctx.canvas.style.display = new_active === 'beta' ? 'inline' : 'none';
    }

    swapBuffers(): void {
        const next_active: CanvasId = this.active_ctx === 'alpha' ? 'beta' : 'alpha';
        this.setActive(next_active);
    }

    run(draw_commands: (ctx: CanvasRenderingContext2D) => void): void {
        if (this.active_ctx === 'alpha') {
            draw_commands(this.beta_ctx);
        } else if (this.active_ctx === 'beta') {
            draw_commands(this.alpha_ctx);
        }
    }

    addEventListener<K extends keyof DocumentEventMap>(event_name: K, event_handler: (e: DocumentEventMap[K]) => void): void {
        this.alpha_ctx.canvas.addEventListener(event_name, (event: any) => {
            if (this.active_ctx === 'alpha') {
                event_handler(event);
            }
        });
        this.beta_ctx.canvas.addEventListener(event_name, (event: any) => {
            if (this.active_ctx === 'beta') {
                event_handler(event);
            }
        });
    }

    get canvas() {
        return this.active_ctx === 'alpha' ? this.alpha_ctx.canvas : this.beta_ctx.canvas;
    }
}
