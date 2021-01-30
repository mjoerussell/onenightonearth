import { Renderer } from './render';
import { Coord } from './wasm/size';

interface DragState {
    is_dragging: boolean;
    x: number;
    y: number;
}

export class Controls {
    private date_input: HTMLInputElement | null;
    private lat_input: HTMLInputElement | null;
    private long_input: HTMLInputElement | null;
    private time_travel_button: HTMLButtonElement | null;
    private update_location_button: HTMLButtonElement | null;
    private current_position_button: HTMLButtonElement | null;

    public renderer: Renderer;

    private current_latitude = 0;
    private current_longitude = 0;
    private user_changed_latitude = false;
    private user_changed_longitude = false;

    private timelapse_is_on = false;

    private drag_state: DragState = {
        is_dragging: false,
        x: 0,
        y: 0,
    };

    /** Determine if the current device is a mobile device in portrait mode */
    private is_mobile = false;

    constructor() {
        this.date_input = document.getElementById('dateInput') as HTMLInputElement;
        this.lat_input = document.getElementById('latInput') as HTMLInputElement;
        this.long_input = document.getElementById('longInput') as HTMLInputElement;
        this.time_travel_button = document.getElementById('timelapse') as HTMLButtonElement;
        this.update_location_button = document.getElementById('locationUpdate') as HTMLButtonElement;
        this.current_position_button = document.getElementById('currentPosition') as HTMLButtonElement;
        this.renderer = new Renderer('star-canvas');

        const mql = window.matchMedia('only screen and (max-width: 760px)');
        this.is_mobile = mql.matches;
        // Listen for future changes
        mql.addEventListener('change', this.handleOrientationChange.bind(this));
        this.lat_input?.addEventListener('change', () => {
            this.user_changed_latitude = true;
        });
        this.long_input?.addEventListener('change', () => {
            this.user_changed_longitude = true;
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

    onLocationUpdate(handler: (_: Coord) => void): void {
        this.update_location_button?.addEventListener('click', () => {
            if (this.user_changed_latitude || this.user_changed_longitude) {
                let new_latitude: number;
                let new_longitude: number;
                try {
                    new_latitude = parseFloat(this.lat_input?.value ?? '0');
                } catch (err) {
                    new_latitude = 0;
                }
                try {
                    new_longitude = parseFloat(this.long_input?.value ?? '0');
                } catch (err) {
                    new_longitude = 0;
                }

                handler({ latitude: new_latitude, longitude: new_longitude });

                this.user_changed_latitude = false;
                this.user_changed_longitude = false;
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
            this.time_travel_button!.innerText = this.timelapse_is_on ? 'Time Travel' : 'Stop';
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
        this.renderer.addEventListener('mousedown', event => {
            const center_x = this.renderer.width / 2;
            const center_y = this.renderer.height / 2;
            this.drag_state.x = (event.offsetX - center_x) / this.renderer.canvas.width;
            this.drag_state.y = (event.offsetY - center_y) / this.renderer.canvas.height;

            this.renderer.canvas.classList.add('moving');

            this.drag_state.is_dragging = true;
        });

        this.renderer.addEventListener('mousemove', event => {
            if (this.drag_state.is_dragging) {
                const center_x = this.renderer.width / 2;
                const center_y = this.renderer.height / 2;
                const new_drag_state: DragState = {
                    is_dragging: true,
                    x: (event.offsetX - center_x) / this.renderer.width,
                    y: (event.offsetY - center_y) / this.renderer.height,
                };

                handler(this.drag_state, new_drag_state);

                this.drag_state = new_drag_state;
            }
        });

        this.renderer.addEventListener('mouseup', event => {
            this.renderer.canvas.classList.remove('moving');
            this.drag_state.is_dragging = false;
        });

        this.renderer.addEventListener('mouseleave', event => {
            this.renderer.canvas.classList.remove('moving');
            this.drag_state.is_dragging = false;
        });
    }

    onMapZoom(handler: (zoom_factor: number) => void): void {
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
        if (this.lat_input) {
            this.lat_input.value = value.toString();
        }
    }

    get longitude(): number {
        return this.current_longitude;
    }

    set longitude(value: number) {
        this.current_longitude = value;
        if (this.long_input) {
            this.long_input.value = value.toString();
        }
    }

    private handleOrientationChange(event: MediaQueryListEvent): void {
        if (event.isTrusted) {
            this.is_mobile = event.matches;
        }
    }
}
