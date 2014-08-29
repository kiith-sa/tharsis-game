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
    void collectInput() @trusted nothrow @nogc
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
/** A type-safe key code enum.
 *
 * Enumerates keycodes (e.g. Key.Y refers to where Y is in the current keyboard layout),
 * not scancodes (where Y would refer to a physical key where Y can be found on a
 * US QWERTY keyboard). Scancodes are unsafe because keyboards have various keys and
 * some platforms (e.g. Solaris) report completely different scancodes than others.
 */
enum Key: SDL_Keycode
{
    Unknown            = SDLK_UNKNOWN,
    Return             = SDLK_RETURN,
    Escape             = SDLK_ESCAPE,
    Backspace          = SDLK_BACKSPACE,
    Tab                = SDLK_TAB,
    Space              = SDLK_SPACE,
    Exclaim            = SDLK_EXCLAIM,
    QuoteDbl           = SDLK_QUOTEDBL,
    Hash               = SDLK_HASH,
    Percent            = SDLK_PERCENT,
    Dollar             = SDLK_DOLLAR,
    Ampersand          = SDLK_AMPERSAND,
    Quote              = SDLK_QUOTE,
    Leftparen          = SDLK_LEFTPAREN,
    Rightparen         = SDLK_RIGHTPAREN,
    Asterisk           = SDLK_ASTERISK,
    Plus               = SDLK_PLUS,
    Comma              = SDLK_COMMA,
    Minus              = SDLK_MINUS,
    Period             = SDLK_PERIOD,
    Slash              = SDLK_SLASH,
    Zero               = SDLK_0,
    One                = SDLK_1,
    Two                = SDLK_2,
    Three              = SDLK_3,
    Four               = SDLK_4,
    Five               = SDLK_5,
    Six                = SDLK_6,
    Seven              = SDLK_7,
    Eight              = SDLK_8,
    Nine               = SDLK_9,
    KP_Binary          = SDLK_KP_BINARY,
    Colon              = SDLK_COLON,
    Semicolon          = SDLK_SEMICOLON,
    Less               = SDLK_LESS,
    Equals             = SDLK_EQUALS,
    Greater            = SDLK_GREATER,
    Question           = SDLK_QUESTION,
    At                 = SDLK_AT,

    LeftBracket        = SDLK_LEFTBRACKET,
    Backslash          = SDLK_BACKSLASH,
    RightBracket       = SDLK_RIGHTBRACKET,
    Caret              = SDLK_CARET,
    Underscore         = SDLK_UNDERSCORE,
    Backquote          = SDLK_BACKQUOTE,
    A                  = SDLK_a,
    B                  = SDLK_b,
    C                  = SDLK_c,
    D                  = SDLK_d,
    E                  = SDLK_e,
    F                  = SDLK_f,
    G                  = SDLK_g,
    H                  = SDLK_h,
    I                  = SDLK_i,
    J                  = SDLK_j,
    K                  = SDLK_k,
    L                  = SDLK_l,
    M                  = SDLK_m,
    N                  = SDLK_n,
    O                  = SDLK_o,
    P                  = SDLK_p,
    Q                  = SDLK_q,
    R                  = SDLK_r,
    S                  = SDLK_s,
    T                  = SDLK_t,
    U                  = SDLK_u,
    V                  = SDLK_v,
    W                  = SDLK_w,
    X                  = SDLK_x,
    Y                  = SDLK_y,
    Z                  = SDLK_z,

    CapsLock           = SDLK_CAPSLOCK,

    F1                 = SDLK_F1,
    F2                 = SDLK_F2,
    F3                 = SDLK_F3,
    F4                 = SDLK_F4,
    F5                 = SDLK_F5,
    F6                 = SDLK_F6,
    F7                 = SDLK_F7,
    F8                 = SDLK_F8,
    F9                 = SDLK_F9,
    F10                = SDLK_F10,
    F11                = SDLK_F11,
    F12                = SDLK_F12,

    PrintScreen        = SDLK_PRINTSCREEN,
    ScrollLock         = SDLK_SCROLLLOCK,
    Pause              = SDLK_PAUSE,
    Insert             = SDLK_INSERT,
    Home               = SDLK_HOME,
    PageUp             = SDLK_PAGEUP,
    Delete             = SDLK_DELETE,
    End                = SDLK_END,
    PageDown           = SDLK_PAGEDOWN,
    Right              = SDLK_RIGHT,
    Left               = SDLK_LEFT,
    Down               = SDLK_DOWN,
    Up                 = SDLK_UP,

    NumLockClear       = SDLK_NUMLOCKCLEAR,
    KP_Divide          = SDLK_KP_DIVIDE,
    KP_Multiply        = SDLK_KP_MULTIPLY,
    KP_Minus           = SDLK_KP_MINUS,
    KP_Plus            = SDLK_KP_PLUS,
    KP_Enter           = SDLK_KP_ENTER,
    KP_1               = SDLK_KP_1,
    KP_2               = SDLK_KP_2,
    KP_3               = SDLK_KP_3,
    KP_4               = SDLK_KP_4,
    KP_5               = SDLK_KP_5,
    KP_6               = SDLK_KP_6,
    KP_7               = SDLK_KP_7,
    KP_8               = SDLK_KP_8,
    KP_9               = SDLK_KP_9,
    KP_0               = SDLK_KP_0,
    KP_Period          = SDLK_KP_PERIOD,

    Application        = SDLK_APPLICATION,
    Power              = SDLK_POWER,
    KP_Equals          = SDLK_KP_EQUALS,
    F13                = SDLK_F13,
    F14                = SDLK_F14,
    F15                = SDLK_F15,
    F16                = SDLK_F16,
    F17                = SDLK_F17,
    F18                = SDLK_F18,
    F19                = SDLK_F19,
    F20                = SDLK_F20,
    F21                = SDLK_F21,
    F22                = SDLK_F22,
    F23                = SDLK_F23,
    F24                = SDLK_F24,
    Execute            = SDLK_EXECUTE,
    Help               = SDLK_HELP,
    Menu               = SDLK_MENU,
    Select             = SDLK_SELECT,
    Stop               = SDLK_STOP,
    Again              = SDLK_AGAIN,
    Undo               = SDLK_UNDO,
    Cut                = SDLK_CUT,
    Copy               = SDLK_COPY,
    Paste              = SDLK_PASTE,
    Find               = SDLK_FIND,
    Mute               = SDLK_MUTE,
    VolumeUp           = SDLK_VOLUMEUP,
    VolumeDown         = SDLK_VOLUMEDOWN,
    KP_Comma           = SDLK_KP_COMMA,
    KP_EqualsAS400     = SDLK_KP_EQUALSAS400,

    AltErase           = SDLK_ALTERASE,
    SysReq             = SDLK_SYSREQ,
    Cancel             = SDLK_CANCEL,
    Clear              = SDLK_CLEAR,
    Prior              = SDLK_PRIOR,
    Return2            = SDLK_RETURN2,
    Separator          = SDLK_SEPARATOR,
    Out                = SDLK_OUT,
    Oper               = SDLK_OPER,
    ClearAgain         = SDLK_CLEARAGAIN,
    CrSel              = SDLK_CRSEL,
    ExSel              = SDLK_EXSEL,

    KP_00              = SDLK_KP_00,
    KP_000             = SDLK_KP_000,
    ThousandsSeparator = SDLK_THOUSANDSSEPARATOR,
    DecimalSeparator   = SDLK_DECIMALSEPARATOR,
    CurrencyUnit       = SDLK_CURRENCYUNIT,
    CurrencySubunit    = SDLK_CURRENCYSUBUNIT,
    KP_LeftParen       = SDLK_KP_LEFTPAREN,
    KP_RightParen      = SDLK_KP_RIGHTPAREN,
    KP_LeftBrace       = SDLK_KP_LEFTBRACE,
    KP_RightBrace      = SDLK_KP_RIGHTBRACE,
    KP_Tab             = SDLK_KP_TAB,
    KP_Backspace       = SDLK_KP_BACKSPACE,
    KP_A               = SDLK_KP_A,
    KP_B               = SDLK_KP_B,
    KP_C               = SDLK_KP_C,
    KP_D               = SDLK_KP_D,
    KP_E               = SDLK_KP_E,
    KP_F               = SDLK_KP_F,
    KP_Xor             = SDLK_KP_XOR,
    KP_Power           = SDLK_KP_POWER,
    KP_Percent         = SDLK_KP_PERCENT,
    KP_Less            = SDLK_KP_LESS,
    KP_Greater         = SDLK_KP_GREATER,
    KP_Ampersand       = SDLK_KP_AMPERSAND,
    KP_DblAmpersand    = SDLK_KP_DBLAMPERSAND,
    KP_VerticalBar     = SDLK_KP_VERTICALBAR,
    KP_DblVerticalBar  = SDLK_KP_DBLVERTICALBAR,
    KP_Colon           = SDLK_KP_COLON,
    KP_Hash            = SDLK_KP_HASH,
    KP_Space           = SDLK_KP_SPACE,
    KP_At              = SDLK_KP_AT,
    KP_Exclam          = SDLK_KP_EXCLAM,
    KP_MemStore        = SDLK_KP_MEMSTORE,
    KP_MemRecall       = SDLK_KP_MEMRECALL,
    KP_MemClear        = SDLK_KP_MEMCLEAR,
    KP_MemAdd          = SDLK_KP_MEMADD,
    KP_MemSubtract     = SDLK_KP_MEMSUBTRACT,
    KP_MemMultiply     = SDLK_KP_MEMMULTIPLY,
    KP_MemDivide       = SDLK_KP_MEMDIVIDE,
    KP_Plusminus       = SDLK_KP_PLUSMINUS,
    KP_Clear           = SDLK_KP_CLEAR,
    KP_ClearEntry      = SDLK_KP_CLEARENTRY,
    KP_Octal           = SDLK_KP_OCTAL,
    KP_Decimal         = SDLK_KP_DECIMAL,
    KP_Hexadecimal     = SDLK_KP_HEXADECIMAL,

    LCtrl              = SDLK_LCTRL,
    LShift             = SDLK_LSHIFT,
    LAlt               = SDLK_LALT,
    LGui               = SDLK_LGUI,
    RCtrl              = SDLK_RCTRL,
    RShift             = SDLK_RSHIFT,
    RAlt               = SDLK_RALT,
    RGui               = SDLK_RGUI,

    Mode               = SDLK_MODE,

    AudioNext          = SDLK_AUDIONEXT,
    AudioPrev          = SDLK_AUDIOPREV,
    AudioStop          = SDLK_AUDIOSTOP,
    AudioPlay          = SDLK_AUDIOPLAY,
    AudioMute          = SDLK_AUDIOMUTE,
    MediaSelect        = SDLK_MEDIASELECT,
    WWW                = SDLK_WWW,
    Mail               = SDLK_MAIL,
    Calculator         = SDLK_CALCULATOR,
    Computer           = SDLK_COMPUTER,
    AC_Search          = SDLK_AC_SEARCH,
    AC_Home            = SDLK_AC_HOME,
    AC_Back            = SDLK_AC_BACK,
    AC_Forward         = SDLK_AC_FORWARD,
    AC_Stop            = SDLK_AC_STOP,
    AC_Refresh         = SDLK_AC_REFRESH,
    AC_Bookmarks       = SDLK_AC_BOOKMARKS,

    BrightnessDown     = SDLK_BRIGHTNESSDOWN,
    BrightnessUp       = SDLK_BRIGHTNESSUP,
    DisplaySwitch      = SDLK_DISPLAYSWITCH,
    KBDillumToggle     = SDLK_KBDILLUMTOGGLE,
    KBDillumDown       = SDLK_KBDILLUMDOWN,
    KBDillumUp         = SDLK_KBDILLUMUP,
    Eject              = SDLK_EJECT,
    Sleep              = SDLK_SLEEP
}

/// Keeps track of which keys are pressed on the keyboard.
final class Keyboard
{
private:
    import std.container;
    // Unlikely to have more than 256 keys pressed at any one time (we ignore any more).
    SDL_Keycode[256] pressedKeys_;
    // pressedKeys_ from the last update, to detect that a key has just been pressed/released.
    SDL_Keycode[256] pressedKeysLastUpdate_;
    // The number of values used in pressedKeys_.
    size_t pressedKeyCount_;
    // The number of values used in pressedKeysLastUpdate_.
    size_t pressedKeyCountLastUpdate_;


public:
    /// Get the state of specified keyboard key.
    Flag!"pressed" key(const Key isPressed) @safe pure nothrow const @nogc 
    {
        import std.algorithm;
        auto keys = pressedKeys_[0 .. pressedKeyCount_];
        return keys.canFind(cast(SDL_Keycode)isPressed) ? Yes.pressed : No.pressed;
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
private:
    // X coordinate of mouse position.
    int x_;
    // Y coordinate of mouse position.
    int y_;

    // Y movement of mouse since the last update.
    int xMovement_;
    // Y movement of mouse since the last update.
    int yMovement_;

    // X coordinate of the mouse wheel (if the wheel supports horizontal scrolling).
    int wheelX_;
    // Y coordinate of the mouse wheel (aka scrolling with a normal wheel).
    int wheelY_;

    // X movement of the wheel since the last update.
    int wheelYMovement_;
    // Y movement of the wheel since the last update.
    int wheelXMovement_;

    import gl3n_extra.linalg;
    // Did the user finish a click with a button during this update?
    Flag!"click"[Button.max + 1] click_;

    // Did the user finish a doubleclick with a button during this update?
    Flag!"doubleClick"[Button.max + 1] doubleClick_;

    // State of all (well, at most 5) mouse buttons.
    Flag!"pressed"[Button.max + 1] buttons_;

    // Coordinates where each button was last pressed (for dragging).
    vec2i[Button.max + 1] pressedCoords_;

    // Gets the current window height.
    long delegate() @safe pure nothrow @nogc getHeight_;

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
        Unknown = ubyte.max
    }

    /** Construct a Mouse and initialize button states.
     *
     * Params:
     *
     * getHeight = Delegate that returns current window height.
     */
    this(long delegate() @safe pure nothrow @nogc getHeight) @trusted
    {
        getHeight_ = getHeight;
        const bits = SDL_GetMouseState(&x_, &y_);
        xMovement_ = yMovement_ = 0;
        y_ = cast(int)(getHeight_() - y_);
        buttons_[0] = bits & SDL_BUTTON_LMASK  ? Yes.pressed : No.pressed;
        buttons_[1] = bits & SDL_BUTTON_MMASK  ? Yes.pressed : No.pressed;
        buttons_[2] = bits & SDL_BUTTON_RMASK  ? Yes.pressed : No.pressed;
        buttons_[3] = bits & SDL_BUTTON_X1MASK ? Yes.pressed : No.pressed;
        buttons_[4] = bits & SDL_BUTTON_X2MASK ? Yes.pressed : No.pressed;
    }

    /// Get X coordinate of mouse position.
    int x() @safe pure const { return x_; }

    /// Get Y coordinate of mouse position.
    int y() @safe pure const { return y_; }

    /// Get X movement of mouse since the last update.
    int xMovement() @safe pure const { return xMovement_; }

    /// Get Y movement of mouse since the last update.
    int yMovement() @safe pure const { return yMovement_; }

    /// Get X coordinate of the mouse wheel (if it supports horizontal scrolling).
    int wheelX() @safe pure const { return wheelX_; }

    /// Get Y coordinate of the mouse wheel.
    int wheelY() @safe pure const { return wheelY_; }

    /// Get the X movement of the wheel since the last update.
    int wheelXMovement() @safe pure const { return wheelXMovement_; }

    /// Get the Y movement of the wheel since the last update.
    int wheelYMovement() @safe pure const { return wheelYMovement_; }

    /// Did the user finish a double click during this update?
    Flag!"doubleClick" doubleClicked(Button button) @safe pure const
    {
        return doubleClick_[button];
    }

    /// Did the user finish a click during this update?
    Flag!"click" clicked(Button button) @safe pure const
    {
        return click_[button];
    }

    /// Get the state of specified mouse button.
    Flag!"pressed" button(Button button) @safe pure const
    {
        return buttons_[button];
    }

    /// Get the coordinates at which button was last pressed. Useful for dragging.
    vec2i pressedCoords(Button button) @safe pure const
    {
        return pressedCoords_[button];
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
                wheelXMovement_ = e.wheel.x;
                wheelYMovement_ = e.wheel.y;
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
    void update() @system
    {
        wheelXMovement_ = 0;
        wheelYMovement_ = 0;
        click_[]       = No.click;
        doubleClick_[] = No.doubleClick;
        const oldX = x_;
        const oldY = y_;
        SDL_GetMouseState(&x_, &y_);
        y_ = cast(int)(getHeight_() - y_);
        xMovement_ = x_ - oldX;
        yMovement_ = y_ - oldY;
    }
}
