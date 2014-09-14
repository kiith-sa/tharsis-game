import std.algorithm;
import std.array;
import std.exception;
import std.logger;
import std.stdio;
import std.typecons;

import derelict.sdl2.sdl;
import derelict.opengl3.gl3;

import derelict.util.exception;

import entity.entitysystem;
import game.camera;
import game.mainloop;
import platform.inputdevice;
import platform.videodevice;
import time.gametime;


// Testing note: to run a program with llvmpipe on Mesa drivers, use:
//    LIBGL_ALWAYS_SOFTWARE=1 ./program_binary


// TODO: Move fixedFPS to YAML 2014-09-12
/** We use fixed effective FPS and time step to make game updates more 'discrete'.
 *
 * If we can't maintain the FPS, the game slows down (hence we need to do everything to 
 * keep overhead low enough to keep this FPS).
 */
enum fixedFPS = 60.0f;
// Good for printf debugging:
// enum fixedFPS = 3.0f;



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
        "    Local options:",
        "      --direct               Allow direct mouse/keyboard input to pass through",
        "                             along with the recorded demo input (allowing the ",
        "                             user to affect the demo as it runs)",
        "                             ",
        "    Local arguments:",
        "      <filename>             Name of the recorded input file to execute.",
        "-------------------------------------------------------------------------------"
        ];
    foreach(line; help) { writeln(line); }
}


/** Command-line interface.
 *
 * Works with git-style commands (currently only 'demo', which runs the game with input
 * from an input record file).
 *
 * If there is no command, the game is launched normally.
 */
struct CLI
{
private:
    /* Current command line argument processing function.
     *
     * In the beginning, this is the function to process global arguments. When a command
     * is encountered, it is set to that command's local arguments parser function.
     */
    void delegate(string) processArg_;
    // Action to execute (determined by command line arguments)
    int delegate() action_;

    // Options/arguments for the 'demo' command.
    struct Demo
    {
        // Name of the recorded input filename for the 'demo' command.
        string inputName_;

        // Should direct mouse/keyboard input be blocked when replaying the demo?
        Flag!"block" blockInput_ = Yes.block;
    }

    // Options/arguments for the 'demo' command.
    Demo demo_;


public:
    /// Construct a CLI with specified command-line arguments and parse them.
    this(string[] cliArgs)
    {
        // The 'default command' - run the game.
        action_ = ()
        {
            // For now. Should log to an in-memory buffer later.
            auto log = defaultLogger;

            if(!loadDerelict(log)) { return 1; }
            scope(exit)            { unloadDerelict(); }
            if(!initSDL(log)) { return 1; }
            scope(exit)       { SDL_Quit(); }

            auto video = scoped!VideoDevice(log);
            if(!initVideo(video, log)) { return 1; }

            auto input    = scoped!InputDevice(&video.height, log);
            auto gameTime = scoped!GameTime(1 / fixedFPS);

            runGame(video, input, gameTime, log);

            return 0;
        };
        // We start parsing global options/commands.
        processArg_ = &globalOrCommand;
        foreach(arg; cliArgs[1 .. $]) { processArg_(arg); }
    }

    /// Execute the action specified by command line arguments.
    int execute()
    {
        // Execute the command.
        try
        {
            return action_();
        }
        catch(CLIException e) { writeln("Command-line error: ", e.msg); help(); }
        catch(Throwable e)    { writeln("Unhandled error: ", e.msg); }
        return 1;
    }

private:
    // Parses local options for the "top" command.
    void localDemo(string arg)
    {
        if(!arg.startsWith("--"))
        {
            enforce(demo_.inputName_ is null,
                    new CLIException("`demo` can have only one argument: input file name"));
            demo_.inputName_ = arg;
            return;
        }

        processOption(arg, (opt, args) {

        switch(opt)
        {
            case "direct": demo_.blockInput_ = No.block; break;
            default: throw new CLIException("Unrecorgnized demo option: --" ~ opt);
        }

        });
    }

    // Parse a command. Sets up command state and switches to its option parser function.
    void command(string arg)
    {
        switch(arg)
        {
            // The 'demo' command: run the game, replaying input from a file.
            //
            // Filename is specified by an argument (see localDemo()).
            case "demo": 
                processArg_ = &localDemo; 
                action_ = ()
                {
                    enforce(demo_.inputName_ !is null,
                            new CLIException("Demo file name not specified"));

                    // For now. Should log to an in-memory buffer later.
                    auto log = defaultLogger;

                    if(!loadDerelict(log)) { return 1; }
                    scope(exit)            { unloadDerelict(); }
                    if(!initSDL(log)) { return 1; }
                    scope(exit)       { SDL_Quit(); }

                    auto video = scoped!VideoDevice(log);
                    if(!initVideo(video, log)) { return 1; }

                    auto input    = scoped!InputDevice(&video.height, log);
                    auto gameTime = scoped!GameTime(1 / fixedFPS);

                    // Load recorded input.
                    import io.yaml;
                    try
                    {
                        auto replay = Loader(demo_.inputName_).load();
                        input.replayFromYAML(replay, demo_.blockInput_);
                    }
                    catch(Exception e)
                    {
                        log.warning("Failed to load input recording").assumeWontThrow;
                    }

                    runGame(video, input, gameTime, log);

                    return 0;
                };
                break;
            default: throw new CLIException("Unknown command: " ~ arg);
        }
    }

    /// Parse a global option or command.
    void globalOrCommand(string arg)
    {
        // Command
        if(!arg.startsWith("-")) 
        {
            command(arg);
            return;
        }

        // Global option
        processOption(arg, (opt, args){
        switch(opt)
        {
            case "help": 
                help();
                action_ = () { return 0; };
                return;
            default: throw new CLIException("Unrecognized global option: " ~ opt);
        }
        });
    }
}


/// Load libraries using through Derelict (currently, this is SDL2).
bool loadDerelict(Logger log)
{
    // Load SDL2.
    try
    {
        DerelictSDL2.load();
        return true;
    }
    catch(SharedLibLoadException e) { log.critical("SDL2 not found: ", e.msg); }
    catch(SymbolLoadException e)
    {
        log.critical("Missing SDL2 symbol (old SDL2 version?): ", e.msg);
    }

    return false;
}

/// Unload Derelict libraries.
void unloadDerelict()
{
    DerelictSDL2.unload();
}

/// Initialize the SDL library.
bool initSDL(Logger log)
{
    // Initialize SDL Video subsystem.
    if(SDL_Init(SDL_INIT_VIDEO) < 0)
    {
        // SDL_Init returns a negative number on error.
        log.critical("SDL Video subsystem failed to initialize");
        return false;
    }
    return true;
}

/// Deinitialize the SDL library.
void deinitSDL()
{
    SDL_Quit();
}

/// Initialize the video device (setting video mode and initializing OpenGL).
bool initVideo(VideoDevice video, Logger log)
{
    // Initialize the video device.
    const width        = 800;
    const height       = 600;
    const fullscreen   = No.fullscreen;

    if(!video.initWindow(width, height, fullscreen)) { return false; }
    if(!video.initGL()) { return false; }
    return true;
}

/** Run the game (called from the CLI action_)
 *
 * Params:
 *
 * video    = Video device to draw with.
 * input    = Input device to use.
 * gameTime = Game time subsystem (time steps, etc.).
 * log      = Game log.
 */
int runGame(VideoDevice video, InputDevice input, GameTime gameTime, Logger log)
{
    // TODO: We should use D:GameVFS to access files, with a custom YAML source reading
    //       files through D:GameVFS. 2014-08-27

    auto camera        = new Camera(video.width, video.height);
    auto cameraControl = new CameraControl(gameTime, video, input, camera, log);

    auto entitySystem = EntitySystem(video, input, gameTime, camera, log);

    // Initialize the main profiler (used to profile both the game and Tharsis).
    import tharsis.prof;
    import std.allocator;
    enum profSpace = 1024 * 1024 * 64;
    auto profBuffer = AlignedMallocator.it.alignedAllocate(profSpace, 64);
    scope(exit) { AlignedMallocator.it.deallocate(profBuffer); }

    auto profiler = new Profiler(cast(ubyte[])profBuffer);
    scope(failure) { log.critical("Unexpected failure in the main loop"); }

    try if(!mainLoop(entitySystem, video, input, gameTime, cameraControl, log))
    {
        log.critical("Main loop exited with error");
        return 1;
    }
    catch(Throwable e)
    {
        log.critical(e);
        return 1;
    }
    return 0;
}



/** Program entry point.
 *
 * Rus the CLI and catches any uncaught throwables.
 */
int main(string[] args)
{
    import std.conv;
    try { return CLI(args).execute(); }
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a command-line has incorrect format?\n",
                "error: ", e.msg);
    }
    catch(CLIException e)
    {
        writeln("Command-line error: ", e.msg);
    }
    catch(Throwable e)
    {
        writeln("Unhandlet Throwable at top level: ", e);
    }
    return 1;
}
