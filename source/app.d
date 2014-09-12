import std.algorithm;
import std.array;
import std.stdio;
import std.typecons;

import derelict.sdl2.sdl;
import derelict.opengl3.gl3;

import derelict.util.exception;

// Testing note: to run a program with llvmpipe on Mesa drivers, use:
//    LIBGL_ALWAYS_SOFTWARE=1 ./program_binary

int main(string[] args)
{
    import std.logger;
    // For now. Should log to an in-memory buffer later.
    auto log = defaultLogger;




/// Exception thrown at CLI errors.
class CLIException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/** Process a command line option (argument starting with --).
 *
 * Params:  arg     = Argument to process.
 *          process = Function to process the option. Takes
 *                    the option and its arguments.
 * Throws:  CLIException if arg is not an option, and anything process() throws.
 *
 */
void processOption(string arg, void delegate(string, string[]) process)
{
    enforce(arg.startsWith("--"), new CLIException("Unknown argument: " ~ arg));
    auto argParts = arg[2 .. $].split("=");
    process(argParts[0], argParts[1 .. $]);
}

/// Print help information.
void help()
{
    string[] help = [
        "-------------------------------------------------------------------------------",
        "Tharsis-game",
        "Benchmark game for Tharsis",
        "Copyright (C) 2014 Ferdinand Majerech",
        "",
        "Usage: memprof [--help] <command> [local-options ...]",
        "",
        "Global options:",
        "  --help                     Print this help information.",
        "",
        "",
        "Commands:",
        "  demo                       Play a pre-recorded demo, executing tharsis-game",
        "                             with recorded keyboard/mouse input. Exactly one",
        "                             local argument (demo file name) must be specified.",
        "    Local arguments:",
        "      <filename>             Name of the recorded input file to execute.",
        "-------------------------------------------------------------------------------"
        ];
    foreach(line; help) { writeln(line); }
}


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

    import platform.videodevice;
    auto video = scoped!VideoDevice(log);
    if(!video.initWindow(width, height, fullscreen)) { return 1; }
    if(!video.initGL()) { return 1; }

    import platform.inputdevice;
    auto input = scoped!InputDevice(&video.height, log);

    import time.gametime;
    // Good for printf debugging:
    // auto gameTime = scoped!GameTime(1 / 3.0);
    auto gameTime = scoped!GameTime(1 / 60.0);

    import game.camera;
    auto camera        = new Camera(video.width, video.height);
    auto cameraControl = new CameraControl(gameTime, video, input, camera, log);

    import entity.entitysystem;
    auto entitySystem = EntitySystem(video, input, gameTime, camera, log);
    scope(failure) { log.critical("Unexpected failure in the main loop"); }

    import game.mainloop;
    try if(!mainLoop(entitySystem, video, input, gameTime, cameraControl, log))
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
