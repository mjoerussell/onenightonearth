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
    private stencil_program: WebGLProgram | null = null;

    private vao: WebGLVertexArrayObject | null = null;
    private stencil_vao: WebGLVertexArrayObject | null = null;

    private uniforms: Record<string, WebGLUniformLocation> = {};

    private position_buffer: WebGLBuffer | null = null;
    private normal_buffer: WebGLBuffer | null = null;
    private matrix_buffer: WebGLBuffer | null = null;
    private index_buffer: WebGLBuffer | null = null;
    private color_buffer: WebGLBuffer | null = null;

    private stencil_position_buffer: WebGLBuffer | null = null;

    constructor(canvas_id: string) {
        this.main_canvas = document.getElementById(canvas_id) as HTMLCanvasElement;
        this.main_canvas.width = this.main_canvas.clientWidth;
        this.main_canvas.height = this.main_canvas.clientHeight;
        this.gl = this.main_canvas.getContext('webgl2', { stencil: true })!;

        this.settings = {
            width: this.main_canvas.width,
            height: this.main_canvas.height,
            background_radius: 0.45 * Math.min(this.main_canvas.width, this.main_canvas.height),
            zoom_factor: 1.0,
            drag_speed: Renderer.DefaultDragSpeed,
            fov: 30 * (Math.PI / 180),
            draw_north_up: true,
            draw_constellation_grid: false,
            draw_asterisms: false,
        };

        const vertex_shader_source = `#version 300 es
        in vec4 a_position;
        in mat4 a_matrix;
        in vec4 a_color;
        in vec3 a_normal;

        uniform mat4 u_view_projection;

        out vec4 v_color;
        out vec3 v_normal;
        out vec3 v_surfaceToLight;

        void main() {
            vec4 worldPosition = a_matrix * a_position;
            vec3 lightWorldPosition = vec3(a_matrix[0][3], a_matrix[1][3], a_matrix[2][3]);

            v_color = a_color;
            v_normal = mat3(a_matrix) * a_normal;
            v_surfaceToLight = abs(lightWorldPosition - worldPosition.xyz);

            gl_Position = u_view_projection * worldPosition;
        }
        `;

        const fragment_shader_source = `#version 300 es
        precision highp float;

        in vec4 v_color;
        in vec3 v_normal;
        in vec3 v_surfaceToLight;

        out vec4 outColor;

        void main() {
            vec3 normal = normalize(v_normal);
            vec3 surfaceToLightDirection = normalize(v_surfaceToLight);
            float light = dot(normal, -surfaceToLightDirection);

            outColor = v_color;
            outColor.rgb *= pow(light, 0.2);
        }
        `;

        const stencil_vertex_shader_source = `#version 300 es
        in vec4 a_position;

        void main() {
            // gl_Position = u_stencil_view_projection * vec4(a_position.yx, 0, 0);
            gl_Position = a_position;
        }
        `;

        const stencil_fragment_shader_source = `#version 300 es
        precision highp float;

        out vec4 outColor;

        void main() {
            outColor = vec4(1, 0, 1, 1);
        }
        `;

        const vertex_shader = this.createShader(this.gl.VERTEX_SHADER, vertex_shader_source);
        const fragment_shader = this.createShader(this.gl.FRAGMENT_SHADER, fragment_shader_source);

        const stencil_vertex_shader = this.createShader(this.gl.VERTEX_SHADER, stencil_vertex_shader_source);
        const stencil_fragment_shader = this.createShader(this.gl.FRAGMENT_SHADER, stencil_fragment_shader_source);

        if (vertex_shader == null || fragment_shader == null || stencil_vertex_shader == null || stencil_fragment_shader == null) {
            return;
        }

        this.program = this.createProgram(vertex_shader, fragment_shader);
        this.stencil_program = this.createProgram(stencil_vertex_shader, stencil_fragment_shader);

        if (this.program == null || this.stencil_program == null) {
            return;
        }

        this.assignUniform(this.program, 'u_view_projection');

        this.vao = this.gl.createVertexArray();
        this.stencil_vao = this.gl.createVertexArray();

        this.gl.bindVertexArray(this.vao);

        const position_attrib_location = this.gl.getAttribLocation(this.program, 'a_position');
        this.position_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.position_buffer);
        this.gl.enableVertexAttribArray(position_attrib_location);
        this.gl.vertexAttribPointer(position_attrib_location, 3, this.gl.FLOAT, false, 0, 0);

        this.index_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ELEMENT_ARRAY_BUFFER, this.index_buffer);

        const normal_attrib_location = this.gl.getAttribLocation(this.program, 'a_normal');
        this.normal_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.normal_buffer);
        this.gl.enableVertexAttribArray(normal_attrib_location);
        this.gl.vertexAttribPointer(normal_attrib_location, 3, this.gl.FLOAT, false, 0, 0);

        const matrix_attrib_location = this.gl.getAttribLocation(this.program, 'a_matrix');
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

        const color_attrib_location = this.gl.getAttribLocation(this.program, 'a_color');
        this.color_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.color_buffer);
        this.gl.enableVertexAttribArray(color_attrib_location);
        this.gl.vertexAttribPointer(color_attrib_location, 4, this.gl.FLOAT, false, 0, 0);
        this.gl.vertexAttribDivisor(color_attrib_location, 1);

        this.gl.bindVertexArray(this.stencil_vao);

        const stencil_position_attrib_location = this.gl.getAttribLocation(this.stencil_program, 'a_position');
        this.stencil_position_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.stencil_position_buffer);
        this.gl.enableVertexAttribArray(stencil_position_attrib_location);
        this.gl.vertexAttribPointer(stencil_position_attrib_location, 2, this.gl.FLOAT, false, 0, 0);

        this.gl.enable(this.gl.CULL_FACE);
        this.gl.enable(this.gl.DEPTH_TEST);
        this.gl.enable(this.gl.STENCIL_TEST);
    }

    drawScene(
        vertices: Float32Array,
        normals: Float32Array,
        indices: Uint32Array,
        view_projection: number[],
        matrices: Float32Array,
        colors: Float32Array
    ): void {
        this.gl.viewport(0, 0, this.gl.canvas.width, this.gl.canvas.height);

        this.gl.clearColor(0, 0, 0, 0);
        this.gl.clearStencil(0);
        this.gl.stencilMask(0xff);
        this.gl.depthMask(false);

        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT | this.gl.STENCIL_BUFFER_BIT);

        this.gl.useProgram(this.stencil_program);
        this.gl.bindVertexArray(this.stencil_vao);
        // Disable drawing to the pixel buffer, prevents the color in the stencil frag shader from being rendered
        this.gl.colorMask(false, false, false, false);
        this.gl.stencilFunc(this.gl.ALWAYS, 1, 0xff);
        // If any tests fail (stencil/depth) don't change the stencil buffer, if both pass then replace the value in the stencil buffer
        // (0, just cleared) with the value set to `ref` in `stencilFunc` (1).
        this.gl.stencilOp(this.gl.KEEP, this.gl.KEEP, this.gl.REPLACE);

        // Draw a circle using a triangle fan
        const triangle_count = 100;
        const two_pi = Math.PI * 2;
        const stencil_vertices: number[] = [0, 0];
        for (let i = 0; i <= triangle_count; i += 1) {
            const angle = i * (two_pi / triangle_count);
            stencil_vertices.push(0.9 * Math.cos(angle));
            stencil_vertices.push(0.9 * Math.sin(angle));
        }

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.stencil_position_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, new Float32Array(stencil_vertices), this.gl.STATIC_DRAW);

        this.gl.drawArrays(this.gl.TRIANGLE_FAN, 0, stencil_vertices.length / 2);

        // Re-enable drawing to the pixel buffer
        this.gl.colorMask(true, true, true, true);
        // Only draw a fragment if the corresponding fragment in the stencil buffer is 1
        this.gl.stencilFunc(this.gl.EQUAL, 1, 0xff);
        // Disable writing to the stencil buffer
        this.gl.stencilMask(0);
        // No matter what tests pass/fail, always keep the current value in the stencil buffer (probably redundant with stencilMask(0x00)).
        this.gl.stencilOp(this.gl.KEEP, this.gl.KEEP, this.gl.KEEP);
        this.gl.depthMask(true);
        // End stencil drawing...

        this.gl.useProgram(this.program);
        this.gl.bindVertexArray(this.vao);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.position_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, vertices, this.gl.STATIC_DRAW);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.normal_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, normals, this.gl.STATIC_DRAW);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.matrix_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, matrices, this.gl.DYNAMIC_DRAW);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.color_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, colors, this.gl.DYNAMIC_DRAW);

        this.gl.bufferData(this.gl.ELEMENT_ARRAY_BUFFER, indices, this.gl.STATIC_DRAW);

        this.gl.uniformMatrix4fv(this.uniforms['u_view_projection'], false, view_projection);

        // TODO: Find out if I need to do cleanup of these buffers after binding them - find the mem leak
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

    private createProgram(vertex_shader: WebGLShader, fragment_shader?: WebGLShader): WebGLProgram | null {
        const program = this.gl.createProgram();
        if (program) {
            this.gl.attachShader(program, vertex_shader);
            if (fragment_shader != null) {
                this.gl.attachShader(program, fragment_shader);
            }
            this.gl.linkProgram(program);
            const success = this.gl.getProgramParameter(program, this.gl.LINK_STATUS);
            if (success) {
                return program;
            }
        }

        return null;
    }

    private assignUniform(program: WebGLProgram, uniform_name: string): void {
        const location = this.gl.getUniformLocation(program, uniform_name);
        if (location) {
            this.uniforms[uniform_name] = location;
        } else {
            console.warn(`Tried to get location of invalid uniform '${uniform_name}'`);
        }
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
