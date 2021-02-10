interface Touch {
    id: number;
    client_x: number;
    client_y: number;
}

type TouchChange = [old_touch: Touch, new_touch: Touch];

type Fn<T> = (_: T) => void;
type Fn2<T, U> = (t: T, u: U) => void;

export class TouchInterface {
    private current_touches: Touch[] = [];
    private last_completed_touch: Touch | null = null;

    private touches_completed: number = 0;
    private counting_touches = false;
    private was_moving_touches = false;

    private single_click_handlers: Fn<Touch>[] = [];
    private double_click_handlers: Fn<Touch>[] = [];
    private touch_hold_handlers: Fn<Touch>[] = [];
    private drag_handlers: Fn<TouchChange>[] = [];
    private pinch_handlers: Fn2<TouchChange, TouchChange>[] = [];

    constructor(private el: HTMLElement) {
        this.el.addEventListener('touchstart', event => {
            event.preventDefault();
            for (let i = 0; i < event.changedTouches.length; i += 1) {
                const new_touch: Touch = {
                    id: event.changedTouches[i].identifier,
                    client_x: event.changedTouches[i].clientX,
                    client_y: event.changedTouches[i].clientY,
                };
                this.current_touches.push(new_touch);
                setTimeout(() => {
                    const touch = this.getTouchById(new_touch.id);
                    if (touch) {
                        this.was_moving_touches = true;
                        for (const handler of this.touch_hold_handlers) {
                            handler(touch);
                        }
                    }
                }, 150);
            }
            if (!this.counting_touches) {
                this.counting_touches = true;
                setTimeout(() => {
                    if (!this.was_moving_touches && this.last_completed_touch != null) {
                        if (this.touches_completed === 1) {
                            for (const handler of this.single_click_handlers) {
                                handler(this.last_completed_touch);
                            }
                        } else if (this.touches_completed === 2) {
                            for (const handler of this.double_click_handlers) {
                                handler(this.last_completed_touch);
                            }
                        }
                    }
                    this.touches_completed = 0;
                    this.counting_touches = false;
                }, 300);
            }
        });

        this.el.addEventListener('touchmove', event => {
            event.preventDefault();
            if (event.changedTouches.length === 1 && this.current_touches.length === 1) {
                const old_touch_index = this.getIndexOfTouchById(event.changedTouches[0].identifier);
                if (old_touch_index >= 0) {
                    const new_touch: Touch = {
                        id: event.changedTouches[0].identifier,
                        client_x: event.changedTouches[0].clientX,
                        client_y: event.changedTouches[0].clientY,
                    };
                    for (const handler of this.drag_handlers) {
                        handler([this.current_touches[old_touch_index], new_touch]);
                    }
                    this.current_touches.splice(old_touch_index, 1, new_touch);
                }
            } else if (event.changedTouches.length === 2) {
                const old_touch_index_a = this.getIndexOfTouchById(event.changedTouches[0].identifier);
                const old_touch_index_b = this.getIndexOfTouchById(event.changedTouches[1].identifier);
                if (old_touch_index_a >= 0 && old_touch_index_b >= 0) {
                    const old_touch_a = this.current_touches[old_touch_index_a];
                    const old_touch_b = this.current_touches[old_touch_index_b];
                    const new_touch_a: Touch = {
                        id: event.changedTouches[0].identifier,
                        client_x: event.changedTouches[0].clientX,
                        client_y: event.changedTouches[0].clientY,
                    };
                    const new_touch_b: Touch = {
                        id: event.changedTouches[1].identifier,
                        client_x: event.changedTouches[1].clientX,
                        client_y: event.changedTouches[1].clientY,
                    };
                    for (const handler of this.pinch_handlers) {
                        handler([old_touch_a, new_touch_a], [old_touch_b, new_touch_b]);
                    }
                    this.current_touches.splice(old_touch_index_a, 1, new_touch_a);
                    this.current_touches.splice(old_touch_index_b, 1, new_touch_b);
                }
            }
        });

        const handleTouchEnd = (event: TouchEvent): void => {
            event.preventDefault();
            for (let i = 0; i < event.changedTouches.length; i += 1) {
                const index = this.getIndexOfTouchById(event.changedTouches[i].identifier);
                if (index >= 0) {
                    if (!this.was_moving_touches) {
                        this.touches_completed += 1;
                        this.last_completed_touch = this.current_touches[index];
                    }
                    this.current_touches.splice(index, 1);
                }
            }
            if (this.current_touches.length === 0) {
                this.was_moving_touches = false;
            }
        };

        this.el.addEventListener('touchend', handleTouchEnd);

        this.el.addEventListener('touchcancel', handleTouchEnd);
    }

    onSingleClick(handler: Fn<Touch>): void {
        this.single_click_handlers.push(handler);
    }

    onDoubleClick(handler: Fn<Touch>): void {
        this.double_click_handlers.push(handler);
    }

    onTouchHold(handler: Fn<Touch>): void {
        this.touch_hold_handlers.push(handler);
    }

    onTouchDrag(handler: Fn<TouchChange>): void {
        this.drag_handlers.push(handler);
    }

    onPinch(handler: Fn2<TouchChange, TouchChange>): void {
        this.pinch_handlers.push(handler);
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
        return index >= 0 ? this.current_touches[index] : null;
    }
}
