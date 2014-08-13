import std.stdio;
import std.typecons;

import derelict.sdl2.sdl;
import derelict.opengl3.gl3;

import derelict.util.exception;


int main(string[] args)
{
    import std.logger;
    // For now. Should log to an in-memory buffer later.
    auto log = defaultLogger;


    // Load SDL2.
    try
    {
        DerelictSDL2.load();
    }
    catch(SharedLibLoadException e)
    {
        log.critical("SDL2 not found: " ~ e.msg);
        return 1;
    }
    catch(SymbolLoadException e)
    {
        log.critical("Missing SDL2 symbol (old version installed?): " ~ e.msg);
        return 1;
    }
    scope(exit) { DerelictSDL2.unload(); }

    // Initialize SDL Video subsystem.
    if(SDL_Init(SDL_INIT_VIDEO) < 0)
    {
        // SDL_Init returns a negative number on error.
        log.critical("SDL Video subsystem failed to initialize");
        return 1;
    }
    // Deinitialize SDL at exit.
    scope(exit) { SDL_Quit(); }


    // Initialize the video device.
    const width        = 800;
    const height       = 600;
    const fullscreen   = No.fullscreen;

    import platform.inputdevice;
    import platform.videodevice;
    auto video = scoped!VideoDevice(log);
    auto input = scoped!InputDevice(log);
    if(!video.initWindow(width, height, fullscreen)) { return 1; }
    if(!video.initGL()) { return 1; }


    import entity.entitysystem;
    import game.mainloop;
    EntitySystem entitySystem = EntitySystem(video, log);
    scope(failure) { log.critical("Unexpected failure in the main loop"); }
    try if(!mainLoop(entitySystem, video, input, log))
    {
        log.critical("Main loop exited with error");
        return 1;
    }
    catch(Throwable e)
    {
        log.critical(e);
    }

    return 0;
}
