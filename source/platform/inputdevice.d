//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Handles user input (keyboard, windowing input such as closing the window, etc.).
module platform.inputdevice;


import std.algorithm;
import std.exception;
import std.logger;

import derelict.sdl2.sdl;

public import platform.key;


/// Handles user input (keyboard, windowing input such as closing the window, etc.).
final class InputDevice
{
private:
    // Game log.
    Logger log_;

    // Keeps track of keyboard input.
    Keyboard keyboard_;

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
        log_      = log;
        keyboard_ = new Keyboard();
        mouse_    = new Mouse(getHeight);
    }

    /// Collect user input.
    void update() @trusted nothrow // @nogc
    {
        mouse_.update();
        keyboard_.update();
        SDL_Event e;
        while(SDL_PollEvent(&e) != 0)
        {
            mouse_.handleEvent(e);
            // Quit if the user closes the window or presses Escape.
            if(e.type == SDL_QUIT) { quit_ = true; }
        }
    }

    /// Get access to keyboard input.
    const(Keyboard) keyboard() @safe pure nothrow const @nogc { return keyboard_; }

    /// Get access to mouse input.
    const(Mouse) mouse() @safe pure nothrow const @nogc { return mouse_; }

    /// Does the user want to quit the program (e.g. by pressing the close window button).
    bool quit() @safe pure nothrow const @nogc { return quit_; }
}


import std.typecons;

/// Keeps track of which keys are pressed on the keyboard.
final class Keyboard
{
package:
    // Keyboard data members separated into a struct for easy recording.
    //
    // "Base" state because all other state (movement) can be derived from this data
    // (movement - change of BaseState between frames).
    struct BaseState
    {
        // Unlikely to have more than 256 keys pressed at any one time (we ignore any more).
        SDL_Keycode[256] pressedKeys_;
        // The number of values used in pressedKeys_.
        size_t pressedKeyCount_;

    }

    BaseState baseState_;
    alias baseState_ this;

private:
    // pressedKeys_ from the last update, to detect that a key has just been pressed/released.
    SDL_Keycode[256] pressedKeysLastUpdate_;
    // The number of values used in pressedKeysLastUpdate_.
    size_t pressedKeyCountLastUpdate_;

public:
    /// Get the state of specified keyboard key.
    Flag!"isPressed" key(const Key keycode) @safe pure nothrow const @nogc
    {
        auto keys = pressedKeys_[0 .. pressedKeyCount_];
        return keys.canFind(cast(SDL_Keycode)keycode) ? Yes.isPressed : No.isPressed;
    }

    /// Determine if specified key was just pressed.
    Flag!"pressed" pressed(const Key keycode) @safe pure nothrow const @nogc
    {
        // If it is pressed now but wasn't pressed the last frame, it has just been pressed.
        auto keys = pressedKeysLastUpdate_[0 .. pressedKeyCountLastUpdate_];
        const sdlKey = cast(SDL_Keycode)keycode;
        return (key(keycode) && !keys.canFind(sdlKey)) ? Yes.pressed : No.pressed;
    }

private:
    // Get current keyboard state.
    void update() @system nothrow @nogc
    {
        SDL_PumpEvents();

        int numKeys;
        const Uint8* allKeys = SDL_GetKeyboardState(&numKeys);
        pressedKeysLastUpdate_[]   = pressedKeys_[];
        pressedKeyCountLastUpdate_ = pressedKeyCount_;
        pressedKeyCount_ = 0;
        foreach(SDL_Scancode scancode, Uint8 state; allKeys[0 .. numKeys])
        {
            if(!state) { continue; }
            pressedKeys_[pressedKeyCount_++] = SDL_GetKeyFromScancode(scancode);
        }
    }

}

/// Keeps track of mouse position, buttons, dragging, etc.
final class Mouse
{
package:
    // Mouse data members separated into a struct for easy recording.
    //
    // "Base" state because all other state (movement) can be derived from this data
    // (movement - change of BaseState between frames).
    struct BaseState
    {
        // X coordinate of mouse position.
        int x_;
        // Y coordinate of mouse position.
        int y_;

        // X coordinate of the mouse wheel (if the wheel supports horizontal scrolling).
        int wheelX_;
        // Y coordinate of the mouse wheel (aka scrolling with a normal wheel).
        int wheelY_;

        // Did the user finish a click with a button during this update?
        Flag!"click"[Button.max + 1] click_;

        // Did the user finish a doubleclick with a button during this update?
        Flag!"doubleClick"[Button.max + 1] doubleClick_;

        // State of all (well, at most 5) mouse buttons.
        Flag!"pressed"[Button.max + 1] buttons_;

    }

    BaseState baseState_;
    alias baseState_ this;

private:
    // Y movement of mouse since the last update.
    int xMovement_;
    // Y movement of mouse since the last update.
    int yMovement_;

    // X movement of the wheel since the last update.
    int wheelYMovement_;
    // Y movement of the wheel since the last update.
    int wheelXMovement_;

    // State of all (well, at most 5) mouse buttons.
    Flag!"pressed"[Button.max + 1] buttonsLastUpdate_;

    // Coordinates where each button was last pressed (for dragging).
    vec2i[Button.max + 1] pressedCoords_;

    // Gets the current window height.
    long delegate() @safe pure nothrow @nogc getHeight_;

    import gl3n_extra.linalg;

public:
nothrow @nogc:
    /// Enumerates mouse buttons.
    enum Button: ubyte
    {
        Left    = 0,
        Middle  = 1,
        Right   = 2,
        X1      = 3,
        X2      = 4,
        // Using 16 to avoid too big BaseState arrays.
        Unknown = 16
    }

    /** Construct a Mouse and initialize button states.
     *
     * Params:
     *
     * getHeight = Delegate that returns current window height.
     */
    this(long delegate() @safe pure nothrow @nogc getHeight) @safe nothrow
    {
        getHeight_ = getHeight;
        xMovement_ = yMovement_ = 0;
        getMouseState();
    }

@safe pure const
{
    /// Get X coordinate of mouse position.
    int x() { return x_; }
    /// Get Y coordinate of mouse position.
    int y() { return y_; }

    /// Get X movement of mouse since the last update.
    int xMovement() { return xMovement_; }
    /// Get Y movement of mouse since the last update.
    int yMovement() { return yMovement_; }

    /// Get X coordinate of the mouse wheel (if it supports horizontal scrolling).
    int wheelX() { return wheelX_; }
    /// Get Y coordinate of the mouse wheel.
    int wheelY() { return wheelY_; }

    /// Get the X movement of the wheel since the last update.
    int wheelXMovement() { return wheelXMovement_; }
    /// Get the Y movement of the wheel since the last update.
    int wheelYMovement() { return wheelYMovement_; }

    /// Did the user finish a double click during this update?
    Flag!"doubleClick" doubleClicked(Button button) { return doubleClick_[button]; }
    /// Did the user finish a click during this update?
    Flag!"click" clicked(Button button) { return click_[button]; }
    /// Get the state of specified mouse button.
    Flag!"pressed" button(Button button) { return buttons_[button]; }

    /// Get the coordinates at which button was last pressed. Useful for dragging.
    vec2i pressedCoords(Button button) { return pressedCoords_[button]; }
}

private:
    /// Handle an SDL event (which may be a mouse event).
    void handleEvent(ref const SDL_Event e) @system
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
                // SDL should not report any other value for mouse buttons... but it does.
                default: return Button.Unknown; // assert(false, "Unknown mouse button");
            }
        }
        switch(e.type)
        {
            case SDL_MOUSEMOTION: break;
            case SDL_MOUSEWHEEL:
                wheelX_ += e.wheel.x;
                wheelY_ += e.wheel.y;
                // += is needed because there might be multiple wheel events per frame.
                wheelXMovement_ += e.wheel.x;
                wheelYMovement_ += e.wheel.y;
                break;
            case SDL_MOUSEBUTTONUP:
                const b = button(e.button.button);
                // Don't set to No.click so we don't override clicks from any playing recording.
                if(e.button.clicks > 0)      { click_[b]       = Yes.click; }
                if(e.button.clicks % 2 == 0) { doubleClick_[b] = Yes.doubleClick; }
                break;
            case SDL_MOUSEBUTTONDOWN:
                // Save the coords where the button was pressed (for dragging).
                pressedCoords_[button(e.button.button)] = vec2i(x_, y_);
                break;
            default: break;
        }
    }

    /// Update any mouse state that must be updated every frame.
    void update() @safe nothrow
    {
        wheelXMovement_ = 0; wheelYMovement_ = 0;
        click_[]       = No.click;
        doubleClick_[] = No.doubleClick;
        const oldX = x_; const oldY = y_;
        getMouseState();
        xMovement_ = x_ - oldX; yMovement_ = y_ - oldY;
    }


    /// Get mouse position and button state.
    void getMouseState() @trusted nothrow
    {
        const buttons = SDL_GetMouseState(&x_, &y_);
        buttonsLastUpdate_[] = buttons_[];
        buttons_[Button.Left]   = buttons & SDL_BUTTON_LMASK  ? Yes.pressed : No.pressed;
        buttons_[Button.Middle] = buttons & SDL_BUTTON_MMASK  ? Yes.pressed : No.pressed;
        buttons_[Button.Right]  = buttons & SDL_BUTTON_RMASK  ? Yes.pressed : No.pressed;
        buttons_[Button.X1]     = buttons & SDL_BUTTON_X1MASK ? Yes.pressed : No.pressed;
        buttons_[Button.X2]     = buttons & SDL_BUTTON_X2MASK ? Yes.pressed : No.pressed;
        y_ = cast(int)(getHeight_() - y_);
    }
}
