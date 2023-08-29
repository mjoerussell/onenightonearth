import { Renderer } from './renderer';
import { TouchInterface } from './touch-interface';
import { Point, Coord } from './wasm/wasm_module';
import { Constellation } from './index';

interface DragState {
    is_dragging: boolean;
    x: number;
    y: number;
}

interface PinchState {
    previous_distance: number;
    is_zooming: boolean;
}

/**
 * A wrapper class for the many different view controls and page buttons available. This class handles binding event listeners to
 * specific HTML elements, as well as abstracting over the difference between mouse & touch controls, so that the main function has
 * a simple interface for handling higher-level types of events, such as "map drag" or "timelapse".
 */
export class Controls {
    private _constellation_name: string | null = null;

    public renderer: Renderer;

    private current_latitude = 0;
    private current_longitude = 0;

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
        this.renderer = new Renderer('star-canvas');

        const settings_box = document.getElementById('settings');
        const toggleSettingsVisibility = () => settings_box?.classList.toggle('hidden');
        const settings_toggles = document.getElementsByClassName('settings-toggle');
        for (let i = 0; i < settings_toggles.length; i += 1) {
            const toggle = settings_toggles.item(i);
            toggle?.addEventListener('click', toggleSettingsVisibility);
        }

        document.addEventListener('keyup', event => {
            if (event.key === ' ' || event.code === 'Space') {
                toggleSettingsVisibility();
            }
        })

        const extraContellationControlsContainer = document.getElementById('extraConstellationControls') as HTMLDivElement;
        if (extraContellationControlsContainer) {
            extraContellationControlsContainer.style.display =
                this.renderer.draw_asterisms || this.renderer.draw_constellation_grid ? 'block' : 'none';
        }

        this.touch_handler = new TouchInterface(this.renderer.canvas);

        const mql = window.matchMedia('only screen and (max-width: 1000px)');
        if (mql.matches) {
            this.renderer.drag_speed = Renderer.DefaultMobileDragSpeed;
        }
        // Listen for future changes
        mql.addEventListener('change', _ => {
            if (mql.matches) {
                this.renderer.drag_speed = Renderer.DefaultMobileDragSpeed;
            } else {
                this.renderer.drag_speed = Renderer.DefaultDragSpeed;
            }
        });

    }

    /**
     * Listen for changes in the current date. This is just for direct updates through the date field,
     * not timelapses.
     * @param handler The new date will be passed to this function.
     */
    onDateChange(handler: (_: Date) => void): void {
        const date_input = document.getElementById('dateInput') as HTMLInputElement;
        date_input?.addEventListener('change', () => {
            const new_date = date_input?.valueAsDate;
            if (new_date == null) {
                return;
            }
            handler(new_date);
        });
    }

    /**
     * Listen for the user to set the 'Today' button.
     * @param handler The original date, then the current date ('Today') will be passed to this function.
     * @deprecated Currently the 'Today' button is not shown because the resulting render is flipped for
     * some reason.
     */
    onSetToday(handler: (current: Date, target: Date) => Date): void {
        const today_button = document.getElementById('today') as HTMLButtonElement;
        today_button?.addEventListener('click', () => {
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

    /**
     * Listen for manual changes in the user's location, via the location input
     * element.
     * @param handler Passes the new coordinate to the callback.
     */
    onLocationUpdate(handler: (_: Coord) => void): void {
        const updateCoord = (latitude: number, longitude: number) => {
            const new_lat_rad = latitude * (Math.PI / 180);
            const new_long_rad = longitude < 0 ? (longitude + 360) * (Math.PI / 180) : longitude * (Math.PI / 180);

            handler({ latitude: new_lat_rad, longitude: new_long_rad });
        };
        
        const latitude_input = document.getElementById('latitudeInput') as HTMLInputElement;
        latitude_input?.addEventListener('change', () => {
            let new_latitude: number;
            try {
                new_latitude = parseFloat(latitude_input.value);
            } catch (err) {
                new_latitude = 0;
            }
            updateCoord(new_latitude, this.longitude * (180 / Math.PI));
        });
        
        const longitude_input = document.getElementById('longitudeInput') as HTMLInputElement;
        longitude_input?.addEventListener('change', () => {
            let new_longitude: number;
            try {
                new_longitude = parseFloat(longitude_input.value);
            } catch (err) {
                new_longitude = 0;
            }
            updateCoord(this.latitude * (180 / Math.PI), new_longitude);
        });
    }

    /**
     * Listen for the user to click the "Use my Location" button.
     * @param handler Passes the user's current position to this callback.
     */
    onUseCurrentPosition(handler: (_: Coord) => void): void {
        const current_position_button = document.getElementById('currentPosition');
        current_position_button?.addEventListener('click', () => {
            if ('geolocation' in navigator) {
                navigator.geolocation.getCurrentPosition(position => {
                    const lat_rad = position.coords.latitude * (Math.PI / 180);
                    const long_rad =
                        position.coords.longitude < 0
                            ? (position.coords.longitude + 360) * (Math.PI / 180)
                            : position.coords.longitude * (Math.PI / 180);
                    handler({ latitude: lat_rad, longitude: long_rad });
                });
            }
        });
    }

    /**
     * Listen for the user to click the "Timelapse" button.
     * @param handler This function will be called repeatedly, as long as
     * the timelapse feature is turned on. Each time, the new date will be
     * passed in.
     */
    onTimelapse(handler: (next_date: Date) => Date): void {
        const time_travel_button = document.getElementById('timelapse');
        time_travel_button?.addEventListener('click', event => {
            event.stopImmediatePropagation();
            time_travel_button!.innerText = this.timelapse_is_on ? 'Timelapse' : 'Stop';
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

    /**
     * Listens for the user to click-and-drag on the star map. Handles mouse movement and touch-drags.
     * @param handler This function will be called each time the user's mouse moves. The first
     * argument is the original mouse location, and the second argument is the new mouse location.
     */
    onMapDrag(handler: (current_state: DragState, new_state: DragState) => void): void {
        /**
         * Initializes the drag state.
         */
        const handleDragStart = (x: number, y: number) => {
            const center_x = this.renderer.width / 2;
            const center_y = this.renderer.height / 2;
            this.drag_state.x = (x - center_x) / this.renderer.canvas.width;
            this.drag_state.y = (y - center_y) / this.renderer.canvas.height;

            this.renderer.canvas.classList.add('moving');

            this.drag_state.is_dragging = true;
        };

        /**
         * Update the drag state and call the drag handler.
         */
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

        const handleDragEnd = () => {
            this.renderer.canvas.classList.remove('moving');
            this.drag_state.is_dragging = false;
        };

        this.renderer.addEventListener('mousedown', event => handleDragStart(event.offsetX, event.offsetY));

        this.touch_handler.onTouchHold(touch => {
            const canvas_rect = this.renderer.canvas.getBoundingClientRect();
            const offset_x = touch.client_x - canvas_rect.x;
            const offset_y = touch.client_y - canvas_rect.y;
            handleDragStart(offset_x, offset_y);
        });

        this.touch_handler.onTouchDrag(([_, new_touch]) => {
            const canvas_rect = this.renderer.canvas.getBoundingClientRect();
            const offset_x = new_touch.client_x - canvas_rect.x;
            const offset_y = new_touch.client_y - canvas_rect.y;
            handleDragMove(offset_x, offset_y);
        });

        this.renderer.addEventListener('mousemove', event => handleDragMove(event.offsetX, event.offsetY));

        this.renderer.addEventListener('mouseup', () => handleDragEnd());
        this.renderer.addEventListener('mouseleave', () => handleDragEnd());
        this.renderer.addEventListener('touchend', () => handleDragEnd());
    }

    onMapZoom(handler: (zoom_factor: number) => void): void {
        const handleZoom = (current_zoom: number, previous_zoom: number) => {
            // Zoom out faster than zooming in, because usually when you zoom out you just want
            // to go all the way out and it's annoying to have to do a ton of scrolling
            const delta_amount = current_zoom >= previous_zoom ? -0.05 : 0.15;
            let zoom_factor = this.renderer.zoom_factor - this.renderer.zoom_factor * delta_amount;
            if (zoom_factor < 1) {
                zoom_factor = 1;
            }
            handler(zoom_factor);
        };

        this.touch_handler.onPinch((change_a, change_b) => {
            const new_a = change_a[1];
            const new_b = change_b[1];
            const current_touch_distance = Math.sqrt(
                Math.pow(new_b.client_x - new_a.client_x, 2) + Math.pow(new_b.client_y - new_a.client_y, 2)
            );
            handleZoom(current_touch_distance, this.pinch_state.previous_distance);
            this.pinch_state.previous_distance = current_touch_distance;
        });

        this.renderer.addEventListener('wheel', event => {
            event.preventDefault();
            handleZoom(-event.deltaY, 0);
        });
    }

    onMapHover(handler: (_: Point) => void): void {
        this.touch_handler.onSingleClick(touch => {
            if (!this.drag_state.is_dragging) {
                const canvas_rect = this.renderer.canvas.getBoundingClientRect();
                const offset_x = touch.client_x - canvas_rect.x;
                const offset_y = touch.client_y - canvas_rect.y;
                handler({
                    x: offset_x,
                    y: offset_y,
                });
            }
        });

        this.renderer.addEventListener('mousemove', event => {
            if (!this.drag_state.is_dragging) {
                handler({
                    x: event.offsetX,
                    y: event.offsetY,
                });
            }
        });
    }

    onChangeConstellationView(handler: () => void): void {
        const show_asterism_input = document.getElementById('showAsterism') as HTMLInputElement;
        const show_constellation_grid_input = document.getElementById('showGrid') as HTMLInputElement;
        const show_only_zodiac_input = document.getElementById('onlyZodiac') as HTMLInputElement;
        const extraContellationControlsContainer = document.getElementById('extraConstellationControls') as HTMLDivElement;

        const handleAllInputs = () => {
            this.renderer.draw_asterisms = show_asterism_input?.checked ?? false;
            this.renderer.draw_constellation_grid = show_constellation_grid_input?.checked ?? false;
            this.renderer.zodiac_only = show_only_zodiac_input?.checked ?? false;

            if (!this.renderer.draw_asterisms && !this.renderer.draw_constellation_grid) {
                this.constellation_name = '';
            }

            if (extraContellationControlsContainer) {
                extraContellationControlsContainer.style.display =
                    this.renderer.draw_asterisms || this.renderer.draw_constellation_grid ? 'block' : 'none';
            }

            handler();
        };

        show_constellation_grid_input?.addEventListener('change', () => handleAllInputs());
        show_asterism_input?.addEventListener('change', () => handleAllInputs());
        show_only_zodiac_input?.addEventListener('change', () => handleAllInputs());
    }

    setConstellations(constellations: Constellation[]): void {
        const select_constellation = document.getElementById('selectConstellation') as HTMLSelectElement;
        if (select_constellation) {
            for (const [index, c] of constellations.entries()) {
                const c_option: HTMLOptionElement = document.createElement('option');
                c_option.value = index.toString();
                c_option.innerText = c.name;
                select_constellation.appendChild(c_option);
            }
        }
    }

    onSelectConstellation(handler: (_: number) => void): void {
        const select_constellation = document.getElementById('selectConstellation') as HTMLSelectElement;
        select_constellation?.addEventListener('change', _ => {
            const index = parseInt(select_constellation!.value, 10);
            if (index >= 0) {
                handler(index);
            }
        });
    }

    get date(): Date {
        const date_input = document.getElementById('dateInput') as HTMLInputElement;
        const current_date = date_input?.valueAsDate;
        return current_date ?? new Date();
    }

    set date(new_date: Date) {
        const date_input = document.getElementById('dateInput') as HTMLInputElement;
        if (date_input) {
            date_input.valueAsDate = new_date;
        }
    }

    get latitude(): number {
        return this.current_latitude;
    }

    set latitude(value: number) {
        const location_input = document.getElementById('latitudeInput') as HTMLInputElement;
        this.current_latitude = value;
        if (location_input) {
            const lat_degrees = value * (180 / Math.PI);
            location_input.value = lat_degrees.toPrecision(6);
        }
    }

    get longitude(): number {
        return this.current_longitude;
    }

    set longitude(value: number) {
        const location_input = document.getElementById('longitudeInput') as HTMLInputElement;
        this.current_longitude = value;
        if (location_input) {
            const long_degrees = value > Math.PI ? (value - 2 * Math.PI) * (180 / Math.PI) : value * (180 / Math.PI);
            location_input.value = long_degrees.toPrecision(6);
        }
    }

    get constellation_name(): string {
        return this._constellation_name ?? '';
    }

    set constellation_name(value: string) {
        const constellation_info_displays = document.getElementsByClassName('constellation-info') as HTMLCollectionOf<HTMLDivElement>;
        this._constellation_name = value;
        if (constellation_info_displays) {
            for (let i = 0; i < constellation_info_displays.length; i += 1) {
                const name_display = constellation_info_displays[i].getElementsByClassName('constellation-name')[0] as HTMLSpanElement;
                if (name_display != null) {
                    name_display.innerText = value;
                }
            }
        }
    }
}
