interface Touch {
    id: number;
    client_x: number;
    client_y: number;
}

type TouchChange = [old_touch: Touch, new_touch: Touch];

type Fn<T> = (_: T) => void;
type Fn2<T, U> = (t: T, u: U) => void;

export class TouchInterface {
    /**
     * The touches that are currently active.
     */
    private current_touches: Touch[] = [];
    /**
     * The touch that most recently ended.
     */
    private last_completed_touch: Touch | null = null;

    /**
     * Used to count the number of touches that have completed in a certain amount of time.
     * This is then used to determine if the user singe or double clicked.
     */
    private touches_completed: number = 0;
    /**
     * When `true`, the app will count all the touches that complete. Used to prevent this class from
     * starting another countdown while one is already going.
     */
    private counting_touches = false;
    /**
     * `True` if the user starts holding a touch. If that happens, then we don't want to start counting
     * for single/double click.
     */
    private was_moving_touches = false;

    private single_click_handlers: Fn<Touch>[] = [];
    private double_click_handlers: Fn<Touch>[] = [];
    private touch_hold_handlers: Fn<Touch>[] = [];
    private drag_handlers: Fn<TouchChange>[] = [];
    private pinch_handlers: Fn2<TouchChange, TouchChange>[] = [];

    constructor(private el: HTMLElement) {
        this.el.addEventListener('touchstart', event => this.handleTouchStart(event));
        this.el.addEventListener('touchmove', event => this.handleTouchMove(event));
        this.el.addEventListener('touchend', event => this.handleTouchEnd(event));
        this.el.addEventListener('touchcancel', event => this.handleTouchEnd(event));
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

    /**
     * Handle new touch events. The goal here is to start tracking the new touches and determining
     * what gestures they represent. The basic idea is:
     * - If the user starts and ends multiple touches in a short amount of time, consider those "taps"
     * and dispatch the appropriate action based on how many taps were made.
     * - If the user starts a touch and holds it, then dispatch an event for the start of a hold and
     * start tracking for future movement.
     * - If the user starts multiple touches and holds them, then track all of the touches.
     * @param event The new touch event.
     */
    private handleTouchStart(event: TouchEvent): void {
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
            // If we're not already counting touches, start.
            this.counting_touches = true;
            setTimeout(() => {
                // After a short amount of time, see how many touches were made
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
                // Reset counter
                this.touches_completed = 0;
                this.counting_touches = false;
            }, 300);
        }
    }

    /**
     * Handle movement events. Currently there are two types of movement events:
     * - Drag: This event is dispatched only if the following conditions are met:
     *   a) Only 1 touch was changed in this event
     *   b) There is only 1 active touch
     * - Pinch: Pinch is used for zooming. This is dispatched if 2 touches are changed
     * in one event.
     * @param event The new touch event.
     */
    private handleTouchMove(event: TouchEvent): void {
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
            const changed_touches: TouchChange[] = [];
            for (let i = 0; i < event.changedTouches.length; i += 1) {
                const old_touch_index = this.getIndexOfTouchById(event.changedTouches[i].identifier);
                if (old_touch_index >= 0) {
                    const old_touch = this.current_touches[old_touch_index];
                    const new_touch: Touch = {
                        id: event.changedTouches[i].identifier,
                        client_x: event.changedTouches[i].clientX,
                        client_y: event.changedTouches[i].clientY,
                    };
                    changed_touches.push([old_touch, new_touch]);
                    this.current_touches.splice(old_touch_index, 1, new_touch);
                }
            }

            for (const handler of this.pinch_handlers) {
                handler(changed_touches[0], changed_touches[1]);
            }
        }
    }

    /**
     * Handle the end of a touch. We want to do the following things when a touch finishes:
     * - If we're counting completed touches, increment the counter
     * - Update `last_completed_touch`
     * - Remove this touch from `current_touches`
     * - If `current_touches` is now empty, set `was_moving_touches` to false (the user is definitely done
     * moving a touch at this point);
     * @param event The new touch event.
     */
    private handleTouchEnd(event: TouchEvent): void {
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
