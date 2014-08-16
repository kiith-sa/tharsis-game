//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Main event loop of the game.
module game.mainloop;

import std.logger;

import entity.entitysystem;
import platform.inputdevice;
import platform.videodevice;
import time.gametime;


/// Main event loop of the game.
///
/// Params:
///
/// entitySystem = EntitySystem holding all the Processes in the game.
/// videoDevice  = The video device used for graphics and windowing operations.
/// inputDevice  = Device used for user input.
/// time         = Game time subsystem.
/// log          = Log to write... log messages to.
bool mainLoop(ref EntitySystem entitySystem, VideoDevice video, InputDevice input,
              GameTime time, Logger log) @trusted nothrow
{
    entitySystem.spawnEntityASAP("game_data/level1.yaml");

    for(;;)
    {
        // TODO: measure time taken by an update (iteration of this while loop) 
        // Instead of an FPS display, have a 'Load' display, where 100% is timeStep
        // and 0% is 0. 2014-08-16
        while(time.timeToUpdate())
        {
            input.collectInput();
            if(input.quit) { return true; }

            import derelict.opengl3.gl3;
            // Clear the back buffer with a red background (parameters are R, G, B, A)
            glClearColor(0.01, 0.01, 0.04, 1.0);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

            entitySystem.frame();
            // Log GL errors, if any.
            video.gl.runtimeCheck();

            // Swap the back buffer to the front, showing it in the window.
            video.swapBuffers();

            time.finishedUpdate();
        }
    }

    assert(false, "This should never be reached");
}
