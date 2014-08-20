//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Handles user input (keyboard, windowing input such as closing the window, etc.).
module platform.inputdevice;


import std.exception;
import std.logger;

import derelict.sdl2.sdl;


/// Handles user input (keyboard, windowing input such as closing the window, etc.).
final class InputDevice
{
private:
    // Game log.
    Logger log_;

    // Keeps track of mouse input.
    Mouse mouse_;

    // Does the user want to quit the program?
    bool quit_;

public:
    /** Construct an InputDevice.
     *
     * Params:
     *
     * getHeight = Delegate that returns window height.
     * log       = Game log.
     */
    this(long delegate() @safe pure nothrow @nogc getHeight, Logger log) @safe nothrow
    {
        log_   = log;
        mouse_ = new Mouse(getHeight);
    }

    /// Collect user input.
    void collectInput() @trusted nothrow @nogc 
    {
        mouse_.update();
        SDL_Event e;
        while(SDL_PollEvent(&e) != 0)
        {
            mouse_.handleEvent(e);
            // Quit if the user closes the window or presses Escape.
            if(e.type == SDL_QUIT) { quit_ = true; }
            if(e.type == SDL_KEYDOWN) switch(e.key.keysym.sym)
            {
                case SDLK_ESCAPE: quit_ = true; break;
                default:          break;
            }
        }
    }

    /// Get access to mouse input.
    const(Mouse) mouse() @safe pure nothrow @nogc { return mouse_; }

    /// Does the user want to quit the program?
    bool quit() @safe pure nothrow const @nogc { return quit_; }
}

/// Keeps track of mouse position, buttons, dragging, etc.
final class Mouse
{
private:
    // X coordinate of mouse position.
    int x_;
    // Y coordinate of mouse position.
    int y_;

    // X coordinate of the mouse wheel (if the wheel supports horizontal scrolling).
    int wheelX_;
    // Y coordinate of the mouse wheel (aka scrolling with a normal wheel).
    int wheelY_;

    import std.typecons;
    import gl3n_extra.linalg;
    // Did the user finish a click with a button during this update?
    Flag!"click"[5] click_;

    // Did the user finish a doubleclick with a button during this update?
    Flag!"doubleClick"[5] doubleClick_;

    // State of all (well, at most 5) mouse buttons.
    Flag!"pressed"[5] buttons_;

    // Coordinates where each button was last pressed (for dragging).
    vec2i[5] pressedCoords_;

    // Gets the current window height.
    long delegate() @safe pure nothrow @nogc getHeight_;

public:
    /// Enumerates mouse buttons.
    enum Button
    {
        Left   = 0,
        Middle = 1,
        Right  = 2,
        X1     = 3,
        X2     = 4
    }

    /** Construct a Mouse and initialize button states.
     *
     * Params:
     *
     * getHeight = Delegate that returns current window height.
     */
    this(long delegate() @safe pure nothrow @nogc getHeight) @trusted nothrow @nogc
    {
        getHeight_ = getHeight;
        const bits = SDL_GetMouseState(&x_, &y_);
        y_ = cast(int)(getHeight_() - y_);
        buttons_[0] = bits & SDL_BUTTON_LMASK  ? Yes.pressed : No.pressed;
        buttons_[1] = bits & SDL_BUTTON_MMASK  ? Yes.pressed : No.pressed;
        buttons_[2] = bits & SDL_BUTTON_RMASK  ? Yes.pressed : No.pressed;
        buttons_[3] = bits & SDL_BUTTON_X1MASK ? Yes.pressed : No.pressed;
        buttons_[4] = bits & SDL_BUTTON_X2MASK ? Yes.pressed : No.pressed;
    }

    /// Get X coordinate of mouse position.
    int x() @safe pure nothrow const @nogc { return x_; }

    /// Get Y coordinate of mouse position.
    int y() @safe pure nothrow const @nogc { return y_; }

    /// Get X coordinate of the mouse wheel (if it supports horizontal scrolling).
    int wheelX() @safe pure nothrow const @nogc { return wheelX_; }

    /// Get Y coordinate of the mouse wheel.
    int wheelY() @safe pure nothrow const @nogc { return wheelY_; }

    /// Did the user finish a double click during this update?
    Flag!"doubleClick" doubleClicked(Button button) @safe pure nothrow const @nogc
    {
        return doubleClick_[button];
    }

    /// Did the user finish a click during this update?
    Flag!"click" clicked(Button button) @safe pure nothrow const @nogc
    {
        return click_[button];
    }

    /// Get the state of specified mouse button.
    Flag!"pressed" button(Button button) @safe pure nothrow const @nogc
    {
        return buttons_[button];
    }

    /// Get the coordinates at which button was last pressed. Useful for dragging.
    vec2i pressedCoords(Button button) @safe pure nothrow const @nogc
    {
        return pressedCoords_[button];
    }

private:
    /// Handle an SDL event (which may be a mouse event).
    void handleEvent(ref const SDL_Event e) @system nothrow @nogc
    {
        static Button button(Uint8 sdlButton) @safe pure nothrow @nogc
        {
            switch(sdlButton)
            {
                case SDL_BUTTON_LEFT:   return Button.Left;
                case SDL_BUTTON_MIDDLE: return Button.Middle;
                case SDL_BUTTON_RIGHT:  return Button.Right;
                case SDL_BUTTON_X1:     return Button.X1;
                case SDL_BUTTON_X2:     return Button.X2;
                // SDL should not report events even if there are other buttons
                default: assert(false, "Unknown mouse button");
            }
        }
        switch(e.type)
        {
            case SDL_MOUSEMOTION: break;
            case SDL_MOUSEWHEEL:
                wheelX_ += e.wheel.x;
                wheelY_ += e.wheel.y;
                break;
            case SDL_MOUSEBUTTONUP:
                const b = button(e.button.button);
                click_[b]       = e.button.clicks > 0 ? Yes.click : No.click;
                doubleClick_[b] = (e.button.clicks % 2 == 0) ? Yes.doubleClick : No.doubleClick;
                buttons_[b] = No.pressed;
                break;
            case SDL_MOUSEBUTTONDOWN:
                // Save the coords where the button was pressed (for dragging).
                buttons_[button(e.button.button)]       = Yes.pressed;
                pressedCoords_[button(e.button.button)] = vec2i(x_, y_);
                break;
            default: break;
        }
    }

    /// Update any mouse state that must be updated every frame.
    void update() @system nothrow @nogc
    {
        click_[]       = No.click;
        doubleClick_[] = No.doubleClick;
        SDL_GetMouseState(&x_, &y_);
        y_ = cast(int)(getHeight_() - y_);
    }
}
