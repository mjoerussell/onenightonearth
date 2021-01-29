import { Renderer } from './render';

export class Controls {
    private date_input: HTMLInputElement | null;
    private lat_input: HTMLInputElement | null;
    private long_input: HTMLInputElement | null;
    private time_travel_button: HTMLButtonElement | null;
    private update_location_button: HTMLButtonElement | null;

    public renderer: Renderer;

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

    get date(): Date {
        const current_date = this.date_input?.valueAsDate;
        return current_date ?? new Date();
    }

    set date(new_date: Date) {
        if (this.date_input) {
            this.date_input.valueAsDate = new_date;
        }
    }

    private handleOrientationChange(event: MediaQueryListEvent): void {
        if (event.isTrusted) {
            this.is_mobile = event.matches;
        }
    }
}
