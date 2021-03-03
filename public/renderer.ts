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

    private star_program: WebGLProgram | null = null;
    private stencil_program: WebGLProgram | null = null;

    private star_vao: WebGLVertexArrayObject | null = null;
    private stencil_vao: WebGLVertexArrayObject | null = null;

    private uniforms: Record<string, WebGLUniformLocation> = {};

    private position_buffer: WebGLBuffer | null = null;
    private normal_buffer: WebGLBuffer | null = null;
    private matrix_buffer: WebGLBuffer | null = null;
    private index_buffer: WebGLBuffer | null = null;
    private color_buffer: WebGLBuffer | null = null;

    private stencil_position_buffer: WebGLBuffer | null = null;

    private stencil_vertices: Float32Array;

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

        const triangle_count = 100;
        const two_pi = Math.PI * 2;
        const stencil_vertices: number[] = [0, 0];
        for (let i = 0; i <= triangle_count; i += 1) {
            const angle = i * (two_pi / triangle_count);
            stencil_vertices.push(0.9 * Math.cos(angle));
            stencil_vertices.push(0.9 * Math.sin(angle));
        }
        this.stencil_vertices = new Float32Array(stencil_vertices);

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

        this.gl.enable(this.gl.CULL_FACE);
        this.gl.enable(this.gl.DEPTH_TEST);
        this.gl.enable(this.gl.STENCIL_TEST);
        this.gl.viewport(0, 0, this.gl.canvas.width, this.gl.canvas.height);
        this.gl.clearColor(0, 0, 0, 0);
        this.gl.clearStencil(0);

        this.star_program = this.createProgram(vertex_shader_source, fragment_shader_source);
        if (this.star_program == null) {
            return;
        }

        this.assignUniform(this.star_program, 'u_view_projection');

        this.star_vao = this.gl.createVertexArray();
        this.gl.bindVertexArray(this.star_vao);

        this.position_buffer = this.getAttributef(this.star_program, 'a_position', 3);
        this.normal_buffer = this.getAttributef(this.star_program, 'a_normal', 3);
        this.color_buffer = this.getAttributef(this.star_program, 'a_color', 4, 1);
        this.matrix_buffer = this.getAttributeMatNNf(this.star_program, 'a_matrix', 4, 1);
        this.index_buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ELEMENT_ARRAY_BUFFER, this.index_buffer);

        this.stencil_program = this.createProgram(stencil_vertex_shader_source, stencil_fragment_shader_source);
        if (this.stencil_program == null) {
            return;
        }
        this.stencil_vao = this.gl.createVertexArray();
        this.gl.bindVertexArray(this.stencil_vao);

        this.stencil_position_buffer = this.getAttributef(this.stencil_program, 'a_position', 2);
    }

    drawScene(
        vertices: Float32Array,
        normals: Float32Array,
        indices: Uint32Array,
        view_projection: number[],
        matrices: Float32Array,
        colors: Float32Array
    ): void {
        this.gl.stencilMask(0xff);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT | this.gl.STENCIL_BUFFER_BIT);

        this.gl.depthMask(false);

        this.gl.useProgram(this.stencil_program);
        this.gl.bindVertexArray(this.stencil_vao);
        this.gl.colorMask(false, false, false, false);
        this.gl.stencilFunc(this.gl.ALWAYS, 1, 0xff);
        this.gl.stencilOp(this.gl.KEEP, this.gl.KEEP, this.gl.REPLACE);

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.stencil_position_buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, this.stencil_vertices, this.gl.STATIC_DRAW);

        this.gl.drawArrays(this.gl.TRIANGLE_FAN, 0, this.stencil_vertices.length / 2);

        this.gl.colorMask(true, true, true, true);
        this.gl.stencilFunc(this.gl.EQUAL, 1, 0xff);
        this.gl.stencilMask(0);
        this.gl.stencilOp(this.gl.KEEP, this.gl.KEEP, this.gl.KEEP);
        // End stencil drawing...

        this.gl.depthMask(true);

        this.gl.useProgram(this.star_program);
        this.gl.bindVertexArray(this.star_vao);

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

    private createProgram(vertex_source: string, fragment_source: string): WebGLProgram | null {
        const vertex_shader = this.createShader(this.gl.VERTEX_SHADER, vertex_source);
        const fragment_shader = this.createShader(this.gl.FRAGMENT_SHADER, fragment_source);
        if (vertex_shader == null || fragment_shader == null) {
            return null;
        }
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

    private assignUniform(program: WebGLProgram, uniform_name: string): void {
        const location = this.gl.getUniformLocation(program, uniform_name);
        if (location) {
            this.uniforms[uniform_name] = location;
        } else {
            console.warn(`Tried to get location of invalid uniform '${uniform_name}'`);
        }
    }

    private getAttributef(program: WebGLProgram, attribute_name: string, size: number, divisor: number = 0): WebGLBuffer | null {
        const attrib_location = this.gl.getAttribLocation(program, attribute_name);
        const buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, buffer);
        this.gl.enableVertexAttribArray(attrib_location);
        this.gl.vertexAttribPointer(attrib_location, size, this.gl.FLOAT, false, 0, 0);
        this.gl.vertexAttribDivisor(attrib_location, divisor);

        return buffer;
    }

    private getAttributeMatNNf(program: WebGLProgram, attribute_name: string, n: number, divisor: number = 0): WebGLBuffer | null {
        const attrib_location = this.gl.getAttribLocation(program, attribute_name);
        const buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, buffer);

        const num_elems = n * n;
        const bytes_per_matrix = 4 * num_elems;
        for (let i = 0; i < n; i += 1) {
            const location = attrib_location + i;
            this.gl.enableVertexAttribArray(location);
            const offset = i * num_elems;
            this.gl.vertexAttribPointer(location, n, this.gl.FLOAT, false, bytes_per_matrix, offset);
            this.gl.vertexAttribDivisor(location, divisor);
        }

        return buffer;
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
