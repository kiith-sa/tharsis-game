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


    // Initialize the SDL window.
    import platform.sdl2;
    const width        = 800;
    const height       = 600;
    const fullscreen   = No.fullscreen;
    SDL_Window* window = createGLWindow(width, height, fullscreen);
    // Exit if window creation fails.
    if(null is window)
    {
        log.fatal("Failed to create the application window");
        return 1;
    }
    log.infof("Created a%s window with dimensions %s x %s",
              fullscreen ? " fullscreen" : "", width, height);
    // Destroy the window at exit.
    scope(exit) { SDL_DestroyWindow(window); }


    // Initialize OpenGL.
    import gfmod.opengl.opengl;
    OpenGL GL;
    SDL_GLContext context;
    scope(exit)
    {
        if(GL !is null)                   { destroy(GL); }
        if(context != SDL_GLContext.init) { SDL_GL_DeleteContext(context); }
    }
    try
    {
        GL      = new OpenGL(log);
        context = SDL_GL_CreateContext(window);
        if(GL.reload() < GLVersion.GL30)
        {
            log.fatal("Required OpenGL version 3.0 could not be loaded.");
            return 1;
        }
    }
    catch(OpenGLException e)
    {
        log.fatal("Failed to initialize OpenGL: ", e);
        return 1;
    }

    return 0;
}
