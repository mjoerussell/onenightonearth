import { Renderer } from './render';
import { Coord } from './wasm/size';

export class Controls {
    private date_input: HTMLInputElement | null;
    private lat_input: HTMLInputElement | null;
    private long_input: HTMLInputElement | null;
    private time_travel_button: HTMLButtonElement | null;
    private update_location_button: HTMLButtonElement | null;

    public renderer: Renderer;

    private current_latitude = 0;
    private current_longitude = 0;
    private user_changed_latitude = false;
    private user_changed_longitude = false;

    /** Determine if the current device is a mobile device in portrait mode */
    private is_mobile = false;

    constructor() {
        this.date_input = document.getElementById('dateInput') as HTMLInputElement;
        this.lat_input = document.getElementById('latInput') as HTMLInputElement;
        this.long_input = document.getElementById('longInput') as HTMLInputElement;
        this.time_travel_button = document.getElementById('timelapse') as HTMLButtonElement;
        this.update_location_button = document.getElementById('locationUpdate') as HTMLButtonElement;
        this.renderer = new Renderer('star-canvas');

        const mql = window.matchMedia('only screen and (max-width: 760px)');
        this.is_mobile = mql.matches;
        // Listen for future changes
        mql.addEventListener('change', this.handleOrientationChange.bind(this));
        this.lat_input?.addEventListener('change', () => {
            console.log('user changed latitude');
            this.user_changed_latitude = true;
            // try {
            //     this.current_latitude = parseFloat(this.lat_input!.value);
            // } catch (err) {
            //     this.current_latitude = 0;
            // }
        });
        this.long_input?.addEventListener('change', () => {
            console.log('user changed longitude');
            this.user_changed_longitude = true;
            // try {
            //     this.current_longitude = parseFloat(this.long_input!.value);
            // } catch (err) {
            //     this.current_longitude = 0;
            // }
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

                this.current_latitude = new_latitude;
                this.current_longitude = new_longitude;
                this.user_changed_latitude = false;
                this.user_changed_longitude = false;
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
