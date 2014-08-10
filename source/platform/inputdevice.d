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
class InputDevice
{
private:
    // Game log.
    Logger log_;

    // Does the user want to quit the program?
    bool quit_;

public:
    /**
     * Construct an InputDevice logging to specified log.
     */
    this(Logger log) @safe pure nothrow @nogc
    {
        log_ = log;
    }

    /// Collect user input.
    void collectInput() @trusted nothrow @nogc 
    {
        SDL_Event e;
        while(SDL_PollEvent(&e) != 0)
        {
            // Quit if the user closes the window or presses Escape.
            if(e.type == SDL_QUIT) { quit_ = true; }
            if(e.type == SDL_KEYDOWN) switch(e.key.keysym.sym)
            {
                case SDLK_ESCAPE: quit_ = true; break;
                default:          break;
            }
        }
    }

    /// Does the user want to quit the program?
    bool quit() @safe pure nothrow const @nogc
    {
        return quit_;
    }
}
