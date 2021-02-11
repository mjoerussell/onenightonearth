import * as m3 from './matrix';

export type CanvasSettings = {
    width: number;
    height: number;
    background_radius: number;
    zoom_factor: number;
    drag_speed: number;
    draw_north_up: boolean;
    draw_constellation_grid: boolean;
    draw_asterisms: boolean;
};

export class Renderer {
    public static readonly DefaultDragSpeed = 1.5;
    public static readonly DefaultMobileDragSpeed = 3;
    /**
     * The main canvas is the one that's shown to the user. It's only drawn to in single batches, once the workers
     * have finished drawing everything to the offscreen buffer.
     */
    private main_canvas: HTMLCanvasElement;
    private gl: WebGL2RenderingContext;

    private settings: CanvasSettings;

    private _settings_did_change = true;

    constructor(canvas_id: string) {
        this.main_canvas = document.getElementById(canvas_id) as HTMLCanvasElement;
        this.main_canvas.width = this.main_canvas.clientWidth;
        this.main_canvas.height = this.main_canvas.clientHeight;
        this.gl = this.main_canvas.getContext('webgl2')!;

        this.settings = {
            width: this.main_canvas.width,
            height: this.main_canvas.height,
            background_radius: 0.45 * Math.min(this.main_canvas.width, this.main_canvas.height),
            zoom_factor: 1.0,
            drag_speed: Renderer.DefaultDragSpeed,
            draw_north_up: true,
            draw_constellation_grid: false,
            draw_asterisms: false,
        };

        const vertex_shader_source = `#version 300 es
        in vec2 a_position;

        // uniform vec2 u_resolution;
        uniform mat3 u_matrix;

        void main() {

            // vec2 position = (u_matrix * vec3(a_position, 1)).xy;

            // vec2 zeroToOne = position / u_resolution;
            // vec2 zeroToTwo = zeroToOne * 2.0;
            // vec2 clipSpace = zeroToTwo - 1.0;

            // gl_Position = vec4(clipSpace * vec2(1, -1), 0, 1);
            gl_Position = vec4((u_matrix * vec3(a_position, 1)).xy, 0, 1);
        }
        `;

        const fragment_shader_source = `#version 300 es
        precision highp float;

        uniform vec4 u_color;

        out vec4 outColor;

        void main() {
            outColor = u_color;
        }
        `;

        const vertex_shader = this.createShader(this.gl.VERTEX_SHADER, vertex_shader_source);
        const fragment_shader = this.createShader(this.gl.FRAGMENT_SHADER, fragment_shader_source);

        if (vertex_shader == null || fragment_shader == null) {
            return;
        }

        const program = this.createProgram(vertex_shader, fragment_shader);

        if (program == null) {
            return;
        }

        const position_attrib_location = this.gl.getAttribLocation(program, 'a_position');
        const matrix_location = this.gl.getUniformLocation(program, 'u_matrix');
        const color_location = this.gl.getUniformLocation(program, 'u_color');

        const position_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, position_buffer);

        const vao = this.gl.createVertexArray();
        this.gl.bindVertexArray(vao);
        this.gl.enableVertexAttribArray(position_attrib_location);
        this.gl.vertexAttribPointer(position_attrib_location, 2, this.gl.FLOAT, false, 0, 0);

        this.gl.viewport(0, 0, this.gl.canvas.width, this.gl.canvas.height);

        this.gl.clearColor(0, 0, 0, 0);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

        this.gl.useProgram(program);
        this.gl.bindVertexArray(vao);

        const translation = [0, 300];
        const rotation_radians = Math.PI / 4;
        const scale = [1, 1];

        const projection_matrix = m3.projection(this.main_canvas.clientWidth, this.main_canvas.clientHeight);
        const translation_matrix = m3.translation(translation[0], translation[1]);
        const rotation_matrix = m3.rotation(rotation_radians);
        const scale_matrix = m3.scaling(scale[0], scale[1]);

        let matrix = m3.multiplyM3(projection_matrix, translation_matrix);
        matrix = m3.multiplyM3(matrix, rotation_matrix);
        matrix = m3.multiplyM3(matrix, scale_matrix);

        this.gl.uniformMatrix3fv(matrix_location, false, matrix);

        const setRect = (x: number, y: number, width: number, height: number): void => {
            const x1 = x;
            const x2 = x + width;
            const y1 = y;
            const y2 = y + height;

            this.gl.bufferData(
                this.gl.ARRAY_BUFFER,
                new Float32Array([x1, y1, x2, y1, x1, y2, x1, y2, x2, y1, x2, y2]),
                this.gl.STATIC_DRAW
            );
        };

        const randomInt = (range: number) => Math.floor(Math.random() * range);

        for (let i = 0; i < 50; i += 1) {
            setRect(randomInt(300), randomInt(300), randomInt(300), randomInt(300));

            this.gl.uniform4f(color_location, Math.random(), Math.random(), Math.random(), 1);

            this.gl.drawArrays(this.gl.TRIANGLES, 0, 6);
        }

        // const positions = [10, 20, 80, 20, 10, 30, 10, 30, 80, 20, 80, 30];
        // this.gl.bufferData(this.gl.ARRAY_BUFFER, new Float32Array(positions), this.gl.STATIC_DRAW);
        // this.gl.drawArrays(this.gl.TRIANGLES, 0, 6);

        // this.main_canvas.addEventListener('resize', event => {
        //     this.width = this.main_canvas.width;
        //     this.height = this.main_canvas.height;
        //     console.log('resize');
        // });
    }

    private createShader(type: number, source: string): WebGLShader | null {
        const shader = this.gl.createShader(type);
        if (shader) {
            this.gl.shaderSource(shader, source);
            this.gl.compileShader(shader);
            const success = this.gl.getShaderParameter(shader, this.gl.COMPILE_STATUS);
            if (success) {
                return shader;
            }
            console.error(`Error creating shader: ${this.gl.getShaderInfoLog(shader)}`);
            this.gl.deleteShader(shader);
        }

        return null;
    }

    private createProgram(vertex_shader: WebGLShader, fragment_shader: WebGLShader): WebGLProgram | null {
        const program = this.gl.createProgram();
        if (program) {
            this.gl.attachShader(program, vertex_shader);
            this.gl.attachShader(program, fragment_shader);
            this.gl.linkProgram(program);
            const success = this.gl.getProgramParameter(program, this.gl.LINK_STATUS);
            if (success) {
                return program;
            }
        }

        return null;
    }

    // drawData(data: Uint8ClampedArray): void {
    //     try {
    //         const image_data = new ImageData(data, this.main_canvas.width, this.main_canvas.height);
    //         this.main_ctx.putImageData(image_data, 0, 0);
    //     } catch (error) {
    //         if (error instanceof DOMException) {
    //             console.error('DOMException in drawPoint: ', error);
    //         }
    //     }
    // }

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
    }

    get background_radius() {
        return this.settings.background_radius;
    }

    set background_radius(r: number) {
        this.settings.background_radius = r;
        this._settings_did_change = true;
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
        return this.main_canvas;
    }

    // get context() {
    //     return this.main_ctx;
    // }

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

    set drag_speed(value: number) {
        this._settings_did_change = true;
        this.settings.drag_speed = value;
    }

    get drag_speed(): number {
        return this.drag_speed;
    }
}
