import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.experimental.logger;
import std.stdio;
import std.string;
import std.typecons;

import derelict.sdl2.sdl;
import derelict.opengl3.gl3;

import derelict.util.exception;

import entity.entitysystem;
import entity.schedulingalgorithmtype;
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
// Kernel distorts results too much at 60FPS, go with 50 for now.
// enum fixedFPS = 60.0f;
enum fixedFPS = 50.0f;
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
        "Usage: tharsis-game [--help] <command> [local-options ...]",
        "",
        "Global options:",
        "  --help                     Print this help information.",
        "  --sched-algo               Scheduling algorithm to use. Possible values:",
        "                             Dumb      Equal number of Processes per thread",
        "                             LPT       Longest Processing Time (fast, decent)",
        "                             COMBINE   COMBINE (slightly slower, better)",
        "                             BRUTE     Bruteforce backtracking (extremely slow)",
        "                             RBt400r3  Random backtrack, time=400, attempts=3",
        "                             RBt800r6  Random backtrack, time=800, attempts=6",
        "                             RBt1200r9 Random backtrack, time=1200, attempts=9",
        "                             Default: LPT",
        "  --threads=<count>          Number of threads to run Tharsis processes in.",
        "                             If 0, Tharsis automatically determines the number",
        "                             of threads to use.",
        "                             Default: 0",
        "  --headless                 If specified, tharsis-game will run without any",
        "                             graphics (without even opening a window)",
        "  --width=<pixels>           Window width.",
        "                             Default: 1024",
        "  --height=<pixels>          Window height.",
        "                             Default: 768",
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
        "      --quitWhenDone         Quit once the all recorded input is replayed (once",
        "                             the demo ends).",
        "                             By default, the game will continue to run after",
        "                             demo is replayed.",
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

        // Should the game quit when the the replay is finished?
        Flag!"quitWhenDone" quitWhenDone_ = No.quitWhenDone;
    }

    // Options/arguments common for all commands.
    struct Args
    {
        // The number of threads for Tharsis to use. If 0, the number will be autodetected.
        uint threadCount = 0;

        // Are we running headless (without video output) ?
        Flag!"headless" headless;

        // Scheduling algorithm to use (in Tharsis) from start (.init is intentionally LPT).
        SchedulingAlgorithmType schedAlgo = SchedulingAlgorithmType.init;

        // Window/camera width to start with (affects even headless runs).
        uint width = 1024;

        // Window/camera height to start with (affects even headless runs).
        uint height = 768;
    }

    // Options/arguments for the 'demo' command.
    Demo demo_;

    // Options/arguments common for all commands.
    Args args_;

public:
    /// Construct a CLI with specified command-line arguments and parse them.
    this(string[] cliArgs)
    {
        // The 'default command' - run the game.
        action_ = ()
        {
            // For now. Should log to an in-memory buffer later.
            auto log = stdlog;

            if(!loadDerelict(log)) { return 1; }
            scope(exit)            { unloadDerelict(); }
            if(!initSDL(log)) { return 1; }
            scope(exit)       { SDL_Quit(); }


            auto video = args_.headless ? null : new VideoDevice(log);
            scope(exit) if(!args_.headless) { video.destroy(); }
            if(!args_.headless && !initVideo(video, log)) { return 1; }

            auto input = scoped!InputDevice(() => args_.headless ? args_.height : video.height,
                                            log);
            auto gameTime = scoped!GameTime(1 / fixedFPS);

            runGame(video, input, gameTime, args_, log);

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
        catch(Throwable e)    { writeln("Unhandled error: ", e); }
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
            case "direct":       demo_.blockInput_ = No.block;           break;
            case "quitWhenDone": demo_.quitWhenDone_ = Yes.quitWhenDone; break;
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
                    auto log = stdlog;

                    if(!loadDerelict(log)) { return 1; }
                    scope(exit)            { unloadDerelict(); }
                    if(!initSDL(log)) { return 1; }
                    scope(exit)       { SDL_Quit(); }

                    auto video = args_.headless ? null : new VideoDevice(log);
                    scope(exit) if(!args_.headless) { video.destroy(); }
                    if(!args_.headless && !initVideo(video, log)) { return 1; }

                    auto input = scoped!InputDevice(() => args_.headless ? args_.height 
                                                                         : video.height,
                                                    log);
                    auto gameTime = scoped!GameTime(1 / fixedFPS);

                    // Load recorded input.
                    import io.yaml;
                    try
                    {
                        auto replay = Loader(demo_.inputName_).load();
                        input.replayFromYAML(replay, demo_.blockInput_, demo_.quitWhenDone_);
                    }
                    catch(Exception e)
                    {
                        log.warning("Failed to load input recording").assumeWontThrow;
                    }

                    runGame(video, input, gameTime, args_, log);

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
        try switch(opt)
        {
            case "help": 
                help();
                action_ = () { return 0; };
                return;
            case "sched-algo": args_.schedAlgo   = to!SchedulingAlgorithmType(args[0]); break;
            case "headless":   args_.headless    = Yes.headless;                        break;
            case "threads":    args_.threadCount = to!uint(args[0]);                    break;
            case "width":      args_.width       = max(1, to!uint(args[0]));            break;
            case "height":     args_.height      = max(1, to!uint(args[0]));            break;
            default: throw new CLIException("Unrecognized global option: " ~ opt);
        }
        catch(ConvException e)
        {
            writefln("Invalid argument/s for option '--%s': '%s'", opt, args);
            help();
            action_ = () { return 0; };
        }
        });
    }


    /// Initialize the video device (setting video mode and initializing OpenGL).
    bool initVideo(VideoDevice video, Logger log)
    {
        // Initialize the video device.
        const width        = args_.width;
        const height       = args_.height;
        const fullscreen   = No.fullscreen;

        if(!video.initWindow(width, height, fullscreen)) { return false; }
        if(!video.initGL()) { return false; }
        return true;
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

/** Run the game (called from the CLI action_)
 *
 * Params:
 *
 * video    = Video device to draw with. May be NULL if running headless.
 * input    = Input device to use.
 * gameTime = Game time subsystem (time steps, etc.).
 * args     = Settings parsed from command-line arguments.
 * log      = Game log.
 */
int runGame(VideoDevice video, InputDevice input, GameTime gameTime,
            ref const CLI.Args args, Logger log)
{
    // TODO: We should use D:GameVFS to access files, with a custom YAML source reading
    //       files through D:GameVFS. 2014-08-27
    auto camera        = new Camera(cast(size_t)args.width, cast(size_t)args.height);
    auto cameraControl = new CameraControl(gameTime, input, camera, log);

    // Initialize the main profiler (used to profile both the game and Tharsis).
    import tharsis.prof;
    import std.allocator;

    enum profSpaceMainThread = 1024 * 1024 * 512;
    enum profSpaceOtherThreads = 1024 * 1024 * 512;

    import tharsis.entity.entitymanager;
    import tharsis.entity.scheduler;

    // One profiler per thread.
    const threadCount = args.threadCount == 0 ? autodetectThreadCount()
                                              : args.threadCount;
    void[][] profBuffers;
    Profiler[] profilers;
    profBuffers ~= AlignedMallocator.it.alignedAllocate(profSpaceMainThread, 64);
    profilers   ~= new Profiler(cast(ubyte[])profBuffers.back);
    foreach(thread; 1 .. threadCount)
    {
        profBuffers ~= AlignedMallocator.it.alignedAllocate
                      (profSpaceOtherThreads / (threadCount - 1), 64);
        profilers   ~= new Profiler(cast(ubyte[])profBuffers.back);
    }
    scope(exit) foreach(buffer; profBuffers)
    {
        AlignedMallocator.it.deallocate(buffer);
    }
    auto entitySystem = EntitySystem(video, input, gameTime, camera, args.threadCount, 
                                     profilers, log);
    entitySystem.schedulingAlgorithm = args.schedAlgo;
    scope(failure) { log.critical("Unexpected failure in the main loop"); }

    // Run the game itself.
    try if(!mainLoop(entitySystem, video, input, gameTime, cameraControl, profilers, log))
    {
        log.critical("Main loop exited with error");
        return 1;
    }
    catch(Throwable e)
    {
        log.critical(e);
        return 1;
    }

    //TODO make this configurable (config file?)
    enum ProfilerDumpFormat
    {
        None,
        CSV,
        Raw
    }

    const dumpFormat = ProfilerDumpFormat.Raw;

    // Dump profiling results for each thread.
    try foreach(p, profiler; profilers)
    {
        if(profiler.outOfSpace)
        {
            log.infof("WARNING: profiler for thread %s ran out of memory while "
                      "profiling; profiling data is incomplete", p);
        }

        final switch(dumpFormat)
        {
            case ProfilerDumpFormat.None: break;
            case ProfilerDumpFormat.CSV:
                log.infof("Writing profiler output for thread %s to profile%s.csv", p, p);
                const fileName = "profile%s.csv".format(p);
                profiler.profileData.eventRange.writeCSVTo(File(fileName, "wb").lockingTextWriter);
                break;
            case ProfilerDumpFormat.Raw:
                log.infof("Writing profiler output for thread %s to profile%s.raw.prof", p, p);
                auto file = File("profile%s.raw.prof".format(p), "wb");
                file.rawWrite(profiler.profileData);
                break;
        }
    }
    catch(Exception e)
    {
        log.error("Failed to write profiler output: ", e);
    }

    return 0;
}



/** Program entry point.
 *
 * Rus the CLI and catches any uncaught throwables.
 */
int main(string[] args)
{
    try { return CLI(args).execute(); }
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a command-line has incorrect format?\n",
                "error: ", e.msg);
    }
    catch(CLIException e)
    {
        writeln("Command-line error: ", e);
    }
    catch(Throwable e)
    {
        writeln("Unhandled Throwable at top level: ", e);
    }
    return 1;
}
