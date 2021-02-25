export type CanvasSettings = {
    width: number;
    height: number;
    background_radius: number;
    zoom_factor: number;
    drag_speed: number;
    fov: number;
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

    private program: WebGLProgram | null = null;
    private vao: WebGLVertexArrayObject | null = null;

    private position_buffer: WebGLBuffer | null = null;
    private matrix_buffer: WebGLBuffer | null = null;
    private index_buffer: WebGLBuffer | null = null;
    private color_buffer: WebGLBuffer | null = null;

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
            fov: 40 * (Math.PI / 180),
            draw_north_up: true,
            draw_constellation_grid: false,
            draw_asterisms: false,
        };

        const vertex_shader_source = `#version 300 es
        in vec4 a_position;
        in vec4 a_color;
        // uniform mat4 u_matrix;
        in mat4 a_matrix;

        out vec4 v_color;

        void main() {
            gl_Position = a_matrix * a_position;
            v_color = a_color;
        }
        `;

        const fragment_shader_source = `#version 300 es
        precision highp float;

        in vec4 v_color;

        out vec4 outColor;

        void main() {
            outColor = v_color;
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

        this.program = program;

        const position_attrib_location = this.gl.getAttribLocation(program, 'a_position');
        const color_attrib_location = this.gl.getAttribLocation(program, 'a_color');
        const matrix_attrib_location = this.gl.getAttribLocation(program, 'a_matrix');

        this.position_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.position_buffer);

        this.vao = this.gl.createVertexArray();
        this.gl.bindVertexArray(this.vao);
        this.gl.enableVertexAttribArray(position_attrib_location);
        this.gl.vertexAttribPointer(position_attrib_location, 3, this.gl.FLOAT, false, 0, 0);

        this.index_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ELEMENT_ARRAY_BUFFER, this.index_buffer);

        this.color_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.color_buffer);
        this.gl.enableVertexAttribArray(color_attrib_location);
        this.gl.vertexAttribPointer(color_attrib_location, 3, this.gl.UNSIGNED_BYTE, true, 0, 0);

        this.matrix_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.matrix_buffer);
        const bytes_per_matrix = 4 * 16;
        for (let i = 0; i < 4; i += 1) {
            const location = matrix_attrib_location + i;
            this.gl.enableVertexAttribArray(location);
            const offset = i * 16;
            this.gl.vertexAttribPointer(location, 4, this.gl.FLOAT, false, bytes_per_matrix, offset);
            this.gl.vertexAttribDivisor(location, 1);
        }

        this.gl.enable(this.gl.CULL_FACE);
        this.gl.enable(this.gl.DEPTH_TEST);
    }

    drawScene(vertices: Float32Array, indices: Uint32Array, matrices: Float32Array): void {
        const repeat = <T>(items: T[], times: number): T[] => {
            let result: T[] = [];
            for (let i = 0; i < times; i += 1) {
                result = result.concat(items);
            }

            return result;
        };

        this.gl.viewport(0, 0, this.gl.canvas.width, this.gl.canvas.height);

        this.gl.clearColor(0, 0, 0, 0);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

        this.gl.useProgram(this.program);
        this.gl.bindVertexArray(this.vao);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.position_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, vertices, this.gl.STATIC_DRAW);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.matrix_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, matrices.byteLength, this.gl.DYNAMIC_DRAW);
        this.gl.bufferSubData(this.gl.ARRAY_BUFFER, 0, matrices);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.color_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, new Uint8Array(repeat([255, 255, 255], vertices.length)), this.gl.STATIC_DRAW);

        this.gl.bufferData(this.gl.ELEMENT_ARRAY_BUFFER, indices, this.gl.STATIC_DRAW);

        this.gl.drawElementsInstanced(this.gl.TRIANGLES, indices.length, this.gl.UNSIGNED_INT, 0, matrices.length / 16);
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
