import { Renderer } from './renderer';
import { TouchInterface } from './touch-interface';
import { CanvasPoint, Constellation, Coord } from './wasm/size';

interface DragState {
    is_dragging: boolean;
    x: number;
    y: number;
}

interface PinchState {
    previous_distance: number;
    is_zooming: boolean;
}

export class Controls {
    private date_input: HTMLInputElement | null;
    private location_input: HTMLInputElement | null;

    private time_travel_button: HTMLButtonElement | null;
    private today_button: HTMLButtonElement | null;

    private update_location_button: HTMLButtonElement | null;
    private current_position_button: HTMLButtonElement | null;

    private show_constellations_input: HTMLInputElement | null;
    private show_constellation_grid_input: HTMLInputElement | null;
    private show_asterism_input: HTMLInputElement | null;
    private constellation_name_display: HTMLSpanElement | null;
    private select_constellation: HTMLSelectElement | null;

    public renderer: Renderer;

    private current_latitude = 0;
    private current_longitude = 0;

    private user_changed_location = false;

    private timelapse_is_on = false;

    private touch_handler: TouchInterface;

    private drag_state: DragState = {
        is_dragging: false,
        x: 0,
        y: 0,
    };

    private pinch_state: PinchState = {
        is_zooming: false,
        previous_distance: 0,
    };

    constructor() {
        this.date_input = document.getElementById('dateInput') as HTMLInputElement;
        this.location_input = document.getElementById('locationInput') as HTMLInputElement;

        this.time_travel_button = document.getElementById('timelapse') as HTMLButtonElement;
        this.today_button = document.getElementById('today') as HTMLButtonElement;

        this.update_location_button = document.getElementById('locationUpdate') as HTMLButtonElement;
        this.current_position_button = document.getElementById('currentPosition') as HTMLButtonElement;

        this.show_constellations_input = document.getElementById('showConstellations') as HTMLInputElement;
        this.show_asterism_input = document.getElementById('showAsterism') as HTMLInputElement;
        this.show_constellation_grid_input = document.getElementById('showGrid') as HTMLInputElement;
        this.constellation_name_display = document.getElementById('constellationName') as HTMLSpanElement;

        this.select_constellation = document.getElementById('selectConstellation') as HTMLSelectElement;

        this.renderer = new Renderer('star-canvas');

        this.renderer.draw_constellation_grid = this.show_constellation_grid_input?.checked ?? false;
        this.renderer.draw_asterisms = this.show_asterism_input?.checked ?? false;

        if (this.select_constellation) {
            this.select_constellation.style.display =
                this.renderer.draw_asterisms || this.renderer.draw_constellation_grid ? 'block' : 'none';
        }

        this.touch_handler = new TouchInterface(this.renderer.canvas);

        const mql = window.matchMedia('only screen and (max-width: 1000px)');
        if (mql.matches) {
            this.renderer.drag_speed = Renderer.DefaultMobileDragSpeed;
        }
        // Listen for future changes
        mql.addEventListener('change', event => {
            if (mql.matches) {
                this.renderer.drag_speed = Renderer.DefaultMobileDragSpeed;
            } else {
                this.renderer.drag_speed = Renderer.DefaultDragSpeed;
            }
        });

        this.location_input?.addEventListener('change', () => {
            this.user_changed_location = true;
        });
    }

    onDateChange(handler: (_: Date) => void): void {
        this.date_input?.addEventListener('change', () => {
            const new_date = this.date_input?.valueAsDate;
            if (new_date == null) {
                return;
            }
            handler(new_date);
        });
    }

    onSetToday(handler: (current: Date, target: Date) => Date): void {
        this.today_button?.addEventListener('click', () => {
            let current = this.date;
            let target = new Date();

            const moving_backwards = current.valueOf() > target.valueOf();

            const run = () => {
                current = handler(current, target);
                this.date = current;
                if (
                    (moving_backwards && current.valueOf() > target.valueOf()) ||
                    (!moving_backwards && current.valueOf() < target.valueOf())
                ) {
                    window.requestAnimationFrame(run);
                }
            };

            window.requestAnimationFrame(run);
        });
    }

    onLocationUpdate(handler: (_: Coord) => void): void {
        this.update_location_button?.addEventListener('click', () => {
            if (this.user_changed_location) {
                let new_latitude: number;
                let new_longitude: number;
                const input_value = this.location_input?.value ?? '0, 0';
                let coords = input_value.split(',');
                if (coords.length === 1) {
                    coords = input_value.split(' ');
                    if (coords.length === 1) {
                        coords = [coords[0], '0'];
                    }
                }
                try {
                    new_latitude = parseFloat(coords[0]);
                } catch (err) {
                    new_latitude = 0;
                }
                try {
                    new_longitude = parseFloat(coords[1]);
                } catch (err) {
                    new_longitude = 0;
                }

                handler({ latitude: new_latitude, longitude: new_longitude });

                this.user_changed_location = false;
            }
        });
    }

    onUseCurrentPosition(handler: (_: Coord) => void): void {
        this.current_position_button?.addEventListener('click', () => {
            if ('geolocation' in navigator) {
                navigator.geolocation.getCurrentPosition(position => {
                    handler({ latitude: position.coords.latitude, longitude: position.coords.longitude });
                });
            }
        });
    }

    onTimelapse(handler: (next_date: Date) => Date): void {
        this.time_travel_button?.addEventListener('click', () => {
            this.time_travel_button!.innerText = this.timelapse_is_on ? 'Timelapse' : 'Stop';
            if (this.timelapse_is_on) {
                this.timelapse_is_on = false;
                return;
            }

            let date = this.date;

            const run = () => {
                date = handler(date);
                this.date = date;
                if (this.timelapse_is_on) {
                    window.requestAnimationFrame(run);
                }
            };

            window.requestAnimationFrame(run);
            this.timelapse_is_on = true;
        });
    }

    onMapDrag(handler: (current_state: DragState, new_state: DragState) => void): void {
        const handleDragStart = (x: number, y: number) => {
            const center_x = this.renderer.width / 2;
            const center_y = this.renderer.height / 2;
            this.drag_state.x = (x - center_x) / this.renderer.canvas.width;
            this.drag_state.y = (y - center_y) / this.renderer.canvas.height;

            this.renderer.canvas.classList.add('moving');

            this.drag_state.is_dragging = true;
        };

        const handleDragMove = (x: number, y: number, drag_scale: number = 1) => {
            if (this.drag_state.is_dragging) {
                const center_x = this.renderer.width / 2;
                const center_y = this.renderer.height / 2;
                const new_drag_state: DragState = {
                    is_dragging: true,
                    x: ((x - center_x) / this.renderer.width) * drag_scale,
                    y: ((y - center_y) / this.renderer.height) * drag_scale,
                };

                handler(this.drag_state, new_drag_state);

                this.drag_state = new_drag_state;
            }
        };

        this.renderer.addEventListener('mousedown', event => handleDragStart(event.offsetX, event.offsetY));

        this.renderer.addEventListener('touchstart', event => {
            if (event.changedTouches.length !== 1 || this.pinch_state.is_zooming) {
                return;
            }
            event.preventDefault();
            const canvas_rect = this.renderer.canvas.getBoundingClientRect();
            const touch = event.changedTouches[0];
            const offset_x = touch.clientX - canvas_rect.x;
            const offset_y = touch.clientY - canvas_rect.y;
            handleDragStart(offset_x, offset_y);
        });

        this.renderer.addEventListener('mousemove', event => handleDragMove(event.offsetX, event.offsetY));

        this.renderer.addEventListener('touchmove', event => {
            event.preventDefault();
            const canvas_rect = this.renderer.canvas.getBoundingClientRect();
            const touch = event.changedTouches[0];
            const offset_x = touch.clientX - canvas_rect.x;
            const offset_y = touch.clientY - canvas_rect.y;
            handleDragMove(offset_x, offset_y, 2);
        });

        this.renderer.addEventListener('mouseup', event => {
            this.renderer.canvas.classList.remove('moving');
            this.drag_state.is_dragging = false;
        });

        this.renderer.addEventListener('mouseleave', event => {
            this.renderer.canvas.classList.remove('moving');
            this.drag_state.is_dragging = false;
        });

        this.renderer.addEventListener('touchend', event => {
            this.renderer.canvas.classList.remove('moving');
            this.drag_state.is_dragging = false;
        });
    }

    onMapZoom(handler: (zoom_factor: number) => void): void {
        this.renderer.addEventListener('touchstart', event => {
            if (event.changedTouches.length === 2) {
                event.preventDefault();
                this.pinch_state.is_zooming = true;
            }
        });
        this.renderer.addEventListener('touchmove', event => {
            if (this.pinch_state.is_zooming) {
                event.preventDefault();
                if (event.changedTouches.length !== 2 || this.drag_state.is_dragging) {
                    return;
                }
                const touch_a = event.changedTouches[0];
                const touch_b = event.changedTouches[1];
                const current_touch_distance = Math.sqrt(
                    Math.pow(touch_b.pageX - touch_a.pageX, 2) + Math.pow(touch_b.pageY - touch_a.pageY, 2)
                );
                const delta_amount = current_touch_distance < this.pinch_state.previous_distance ? -0.05 : 0.15;
                this.pinch_state.previous_distance = current_touch_distance;
                let zoom_factor = this.renderer.zoom_factor - this.renderer.zoom_factor * delta_amount;
                if (zoom_factor < 1) {
                    zoom_factor = 1;
                }
                handler(zoom_factor);
            }
        });

        this.renderer.addEventListener('touchend', event => {
            this.pinch_state.is_zooming = false;
        });

        this.renderer.addEventListener('wheel', event => {
            event.preventDefault();
            // Zoom out faster than zooming in, because usually when you zoom out you just want
            // to go all the way out and it's annoying to have to do a ton of scrolling
            const delta_amount = event.deltaY < 0 ? -0.05 : 0.15;
            let zoom_factor = this.renderer.zoom_factor - this.renderer.zoom_factor * delta_amount;
            if (zoom_factor < 1) {
                zoom_factor = 1;
            }
            handler(zoom_factor);
        });
    }

    onMapHover(handler: (_: CanvasPoint) => void): void {
        this.renderer.addEventListener('mousemove', event => {
            if (!this.drag_state.is_dragging) {
                const mouse_point: CanvasPoint = {
                    x: event.offsetX,
                    y: event.offsetY,
                };
                handler(mouse_point);
            }
        });
    }

    onMapDoubleClick(handler: (_: CanvasPoint) => void): void {
        this.renderer.addEventListener('dblclick', event => {
            event.preventDefault();
            handler({
                x: event.offsetX,
                y: event.offsetY,
            });
        });
    }

    onChangeConstellationView(handler: () => void): void {
        const handleAllInputs = () => {
            this.renderer.draw_asterisms = this.show_asterism_input?.checked ?? false;
            this.renderer.draw_constellation_grid = this.show_constellation_grid_input?.checked ?? false;

            if (!this.renderer.draw_asterisms && !this.renderer.draw_constellation_grid) {
                this.constellation_name = '';
            }

            if (this.select_constellation) {
                this.select_constellation.style.display =
                    this.renderer.draw_asterisms || this.renderer.draw_constellation_grid ? 'block' : 'none';
            }

            handler();
        };
        this.show_constellations_input?.addEventListener('change', () => handleAllInputs());
        this.show_asterism_input?.addEventListener('change', () => handleAllInputs());
        this.show_constellation_grid_input?.addEventListener('change', () => handleAllInputs());
    }

    setConstellations(constellations: Constellation[]): void {
        if (this.select_constellation) {
            for (const [index, c] of constellations.entries()) {
                const c_option: HTMLOptionElement = document.createElement('option');
                c_option.value = index.toString();
                c_option.innerText = c.name;
                this.select_constellation.appendChild(c_option);
            }
        }
    }

    onSelectConstellation(handler: (_: number) => void): void {
        this.select_constellation?.addEventListener('change', event => {
            const index = parseInt(this.select_constellation!.value, 10);
            if (index >= 0) {
                handler(index);
            }
        });
    }

    get date(): Date {
        const current_date = this.date_input?.valueAsDate;
        return current_date ?? new Date();
    }

    set date(new_date: Date) {
        if (this.date_input) {
            this.date_input.valueAsDate = new_date;
        }
    }

    get latitude(): number {
        return this.current_latitude;
    }

    set latitude(value: number) {
        this.current_latitude = value;
        if (this.location_input) {
            const [_, longitude] = this.location_input.value.split(',');
            this.location_input.value = `${value.toPrecision(6)}, ${longitude}`;
        }
    }

    get longitude(): number {
        return this.current_longitude;
    }

    set longitude(value: number) {
        this.current_longitude = value;
        if (this.location_input) {
            const [latitude, _] = this.location_input.value.split(',');
            this.location_input.value = `${latitude}, ${value.toPrecision(6)}`;
        }
    }

    get show_constellations(): boolean {
        return this.show_constellations_input?.checked ?? false;
    }

    set show_constellations(should_show: boolean) {
        if (this.show_constellations_input) {
            this.show_constellations_input.checked = should_show;
        }
    }

    get constellation_name(): string {
        return this.constellation_name_display?.innerText ?? '';
    }

    set constellation_name(value: string) {
        if (this.constellation_name_display) {
            this.constellation_name_display.innerText = value;
        }
    }
}
