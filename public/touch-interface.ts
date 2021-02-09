interface Touch {
    id: number;
    client_x: number;
    client_y: number;
}

export class TouchInterface {
    private current_touches: Touch[] = [];

    constructor(private el: HTMLElement) {
        this.el.addEventListener('touchstart', event => {
            // event.preventDefault();
            for (let i = 0; i < event.changedTouches.length; i += 1) {
                this.current_touches.push({
                    id: event.changedTouches[i].identifier,
                    client_x: event.changedTouches[i].clientX,
                    client_y: event.changedTouches[i].clientY,
                });
            }
        });

        this.el.addEventListener('touchend', event => {
            event.preventDefault();
            for (let i = 0; i < event.changedTouches.length; i += 1) {
                const index = this.getIndexOfTouchById(event.changedTouches[i].identifier);
                if (index > 0) {
                    this.current_touches.splice(index, 1);
                }
            }
        });

        this.el.addEventListener('touchcancel', event => {
            event.preventDefault();
            for (let i = 0; i < event.changedTouches.length; i += 1) {
                const index = this.getIndexOfTouchById(event.changedTouches[i].identifier);
                if (index > 0) {
                    this.current_touches.splice(index, 1);
                }
            }
        });
    }

    private getIndexOfTouchById(id: number): number {
        for (let i = 0; i < this.current_touches.length; i += 1) {
            if (this.current_touches[i].id === id) {
                return i;
            }
        }
        return -1;
    }

    private getTouchById(id: number): Touch | null {
        const index = this.getIndexOfTouchById(id);
        return index > 0 ? this.current_touches[index] : null;
    }
}
