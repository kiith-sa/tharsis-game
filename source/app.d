import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.experimental.logger;
import std.getopt;
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
// enum fixedFPS = 50.0f;
// Good for printf debugging:
// enum fixedFPS = 3.0f;

/// Enable GC profiling.
extern(C) __gshared string[] rt_options = [ "gcopt=profile:1" ];


/// Print help information.
void help()
{
    string[] help = [
        "-------------------------------------------------------------------------------",
        "Tharsis-game",
        "Benchmark game for Tharsis",
        "Copyright (C) 2014 Ferdinand Majerech",
        "",
        "Usage: tharsis-game [command] [options ...]",
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
        "  --target-fps=<fps>         FPS the game should run at.",
        "                             FPS is fixed to this value and, if the actual FPS",
        "                             gets any lower, the game will slow down.",
        "                             Default: 50",
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


/** Raw configuration data from the command-line and YAML.
 *
 * Note that the GeneralConfig constructor removes the command-line arguments it parses.
 */
struct ConfigData
{
    /** CLI arguments passed to the program.
     *
     * Note: GeneralConfig constructor removes 'general config' arguments from here.
     */
    string[] cliArgs;

    import io.yaml;

    /// YAML data loaded from config.yaml.
    YAMLNode yaml;
    
    /// File name to load ConfigData.yaml from.
    string yamlFileName = "config.yaml";

    /** Construct ConfigData from specified CLI arguments (and by loading config.yaml)
     *
     * Params:
     *
     * cliArgs = Command-line arguments passed to the program.
     * log     = The game log.
     */
    this(string[] cliArgs, Logger log) @safe
    {
        this.cliArgs = cliArgs;
        try
        {
            yaml = Loader(yamlFileName).load();
        }
        catch(YAMLException e)
        {
            log.warningf("Failed to load '%s'.", yamlFileName);
        }
    }
}


// Main pattern for Tharsis configs: a struct with a ctor to initialize it from
// ConfigData

/// Options/arguments common for all commands.
struct GeneralConfig
{
    // The number of threads for Tharsis to use. If 0, the number will be autodetected.
    uint threadCount = 0;

    // Are we running headless (without video output) ?
    bool headless;

    // Scheduling algorithm to use (in Tharsis) from start (.init is intentionally LPT).
    SchedulingAlgorithmType schedAlgo = SchedulingAlgorithmType.init;

    // Window/camera width to start with (affects even headless runs).
    uint width = 1024;

    // Window/camera height to start with (affects even headless runs).
    uint height = 768;

    /** FPS the game should run at.
     *
     * FPS will be at most this value and if it dips below it, the game will slow down.
     */
    uint targetFPS = 50;

    // "game", "demo" or "help"
    string command = "game";

    /** Parse GeneralConfig data from a ConfigData.
     *
     * Note: removes 'general config' arguments from ConfigData.cliArgs.
     */
    this(ref ConfigData data, Logger log)
    {
        import io.yaml;
        try foreach(string key, YAMLNode node; data.yaml)
        {
            try switch(key)
            {
                case "threads":   threadCount = node.as!uint; break;
                case "headless":  headless    = node.as!bool; break;
                case "schedAlgo": schedAlgo   = node.as!string.to!SchedulingAlgorithmType; break;
                case "width":     width       = node.as!uint; break;
                case "height":    height      = node.as!uint; break;
                case "targetFPS": targetFPS   = node.as!uint; break;
                case "command":   command     = node.as!string; break;
                default: break;
            }
            catch(Exception e)
            {
                log.warningf("Error reading '%s' from %s: %s", key, data.yamlFileName, e.msg);
            }
        }
        catch(YAMLException e)
        {
            log.warningf("Error reading data from %s: %s", data.yamlFileName, e.msg);
        }

        try
        {
            auto cliArgs = data.cliArgs[];
            if(cliArgs.length >= 2 && !cliArgs[1].startsWith("-"))
            {
                command = data.cliArgs[1];
                cliArgs = cliArgs[0] ~ cliArgs[2 .. $];
            }

            bool help;
            getopt(cliArgs, std.getopt.config.passThrough, std.getopt.config.bundling,
                   "help", &help, "headless", &headless, "sched-algo", &schedAlgo,
                   "width", &width, "height", &height, "threads", &threadCount,
                   "target-fps", &targetFPS);
            data.cliArgs = cliArgs;

            if(help) { command = "help"; }
        }
        catch(Exception e)
        {
            log.warning("Failed to parse CLI args in GeneralConfig constructor: ", e.msg);
        }
    }
}

/// Options/arguments for the 'demo' command.
struct DemoConfig
{
    // Name of the recorded input filename for the 'demo' command.
    string inputName_;

    // Should direct mouse/keyboard input be blocked when replaying the demo?
    Flag!"block" blockInput_ = Yes.block;

    // Should the game quit when the the replay is finished?
    Flag!"quitWhenDone" quitWhenDone_ = No.quitWhenDone;

    this(ref ConfigData data, Logger log)
    {
        import io.yaml;
        try foreach(string key, YAMLNode node; data.yaml["demo"])
        {
            try switch(key)
            {
                case "inputName":    inputName_    = node.as!string; break;
                case "blockInput":   blockInput_   = node.as!bool.to!(Flag!"block"); break;
                case "quitWhenDone": quitWhenDone_ = node.as!bool.to!(Flag!"quitWhenDone"); break;
                default: break;
            }
            catch(Exception e)
            {
                log.warningf("Error reading '%s' from %s: %s", key, data.yamlFileName, e.msg);
            }
        }
        catch(YAMLException e)
        {
            log.warningf("Error reading data from %s: %s", data.yamlFileName, e.msg);
        }

        bool directInput;
        string[] cliArgs = data.cliArgs;
        try
        {
            getopt(cliArgs,
                   std.getopt.config.passThrough,
                   std.getopt.config.bundling,
                   "direct", &directInput, "quitWhenDone", &quitWhenDone_);
        }
        catch(Exception e)
        {
            log.warning("Failed to parse CLI args in DemoConfig constructor");
        }

        blockInput_ = directInput ? No.block : Yes.block;

        // the [1 .. $] skips the binary name
        foreach(arg; cliArgs[1 .. $].filter!(arg => !arg.startsWith("-")))
        {
            if(inputName_ !is null)
            {
                inputName_ = null;
                log.error("ERROR: `demo` can have only one argument: input file name");
                return;
            }
            inputName_ = arg;
        }
        if(inputName_ is null)
        {
            log.error("ERROR: Demo file name not specified");
        }
    }
}

/// Execute the game. This is the 'real main()'.
int execute(string[] cliArgs)
{
    // For now. Should log to an in-memory buffer later.
    auto log = stdlog;
    scope(exit) { log.info("execute() exit"); }

    auto cfgData = ConfigData(cliArgs, log);
    const cfg = GeneralConfig(cfgData, log);

    switch(cfg.command)
    {
        case "game":
            if(!loadDerelict(log))          { return 1; }
            scope(exit)                     { unloadDerelict(); }
            if(!initSDL(log, cfg.headless)) { return 1; }
            scope(exit)                     { SDL_Quit(); }

            auto video = cfg.headless ? null : new VideoDevice(log);
            scope(exit) if(!cfg.headless) { video.destroy(); }
            if(!cfg.headless && !initVideo(cfg, video, log)) { return 1; }

            auto input = scoped!InputDevice(() => cfg.headless ? cfg.height : video.height, log);
            auto gameTime = scoped!GameTime(1.0 / cfg.targetFPS);

            runGame(video, input, gameTime, cfg, log);
            return 0;

        case "demo":
            const democfg = DemoConfig(cfgData, log);
            if(democfg.inputName_ is null)
            {
                return 1;
            }

            if(!loadDerelict(log))          { return 1; }
            scope(exit)                     { unloadDerelict(); }
            if(!initSDL(log, cfg.headless)) { return 1; }
            scope(exit)                     { SDL_Quit(); }

            auto video = cfg.headless ? null : new VideoDevice(log);
            scope(exit) if(!cfg.headless) { video.destroy(); }
            if(!cfg.headless && !initVideo(cfg, video, log)) { return 1; }

            auto input = scoped!InputDevice(() => cfg.headless ? cfg.height : video.height, log);
            auto gameTime = scoped!GameTime(1.0 / cfg.targetFPS);

            // Load recorded input.
            import io.yaml;
            try
            {
                auto replay = Loader(democfg.inputName_).load();
                input.replayFromYAML(replay, democfg.blockInput_, democfg.quitWhenDone_);
            }
            catch(Exception e)
            {
                log.warning("Failed to load input recording").assumeWontThrow;
            }

            runGame(video, input, gameTime, cfg, log);
            return 0;
        case "help":
            help();
            return 0;
        default:
            log.error("unknown command '", cfg.command, "'");
            return 1;
    }
}


/// Initialize the video device (setting video mode and initializing OpenGL).
bool initVideo(ref const GeneralConfig cfg, VideoDevice video, Logger log)
{
    // Initialize the video device.
    const width        = cfg.width;
    const height       = cfg.height;
    const fullscreen   = No.fullscreen;

    if(!video.initWindow(width, height, fullscreen)) { return false; }
    if(!video.initGL()) { return false; }
    return true;
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

/** Initialize the SDL library.
 *
 * Params:
 *
 * log      = Game log.
 * headless = Are we running without video output? (If so, don't init the video subsystem).
 */
bool initSDL(Logger log, bool headless)
{
    // Initialize SDL Video subsystem.
    if(SDL_Init(headless ? 0 : SDL_INIT_VIDEO) < 0)
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
            ref const GeneralConfig cfg, Logger log)
{
    scope(exit) { log.info("runGame() exit"); }
    // TODO: We should use D:GameVFS to access files, with a custom YAML source reading
    //       files through D:GameVFS. 2014-08-27
    auto camera        = new Camera(cast(size_t)cfg.width, cast(size_t)cfg.height);
    auto cameraControl = new CameraControl(gameTime, input, camera, log);

    // Initialize the main profiler (used to profile both the game and Tharsis).
    import tharsis.prof;
    import std.allocator;

    enum profSpaceMainThread = 1024 * 1024 * 512;
    enum profSpaceOtherThreads = 1024 * 1024 * 512;

    import tharsis.entity.entitymanager;
    import tharsis.entity.scheduler;

    // One profiler per thread.
    const threadCount = cfg.threadCount == 0 ? autodetectThreadCount()
                                             : cfg.threadCount;
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

    import game.map;
    // auto map = scoped!Map(64, 64, 32);
    auto map = scoped!Map(log, 256, 256, 32);

    map.generatePlainMap();

    map.commandRaiseTerrain(7, 25, 0);
    map.commandRaiseTerrain(7, 23, 0);


    map.commandRaiseTerrain(7, 14, 0);
    // map.commandRaiseTerrain(9, 14, 0);

    // map.commandRaiseTerrain(7, 15, 0);
    // map.commandRaiseTerrain(7, 13, 0);
    // map.commandRaiseTerrain(6, 13, 0);
    // map.commandRaiseTerrain(6, 15, 0);
    // map.commandRaiseTerrain(8, 15, 0);
    // map.commandRaiseTerrain(7, 12, 0);
    // map.commandRaiseTerrain(6, 14, 0);
    // map.commandRaiseTerrain(7, 16, 0);
    // map.commandRaiseTerrain(8, 14, 0);

    map.commandRaiseTerrain(7, 14, 1);
    map.commandRaiseTerrain(7, 14, 2);
    map.commandRaiseTerrain(7, 14, 3);

    map.commandRaiseTerrain(12, 14, 0);
    map.commandRaiseTerrain(12, 14, 1);
    map.commandRaiseTerrain(12, 14, 2);
    map.commandRaiseTerrain(12, 14, 3);
    map.commandRaiseTerrain(12, 14, 4);
    map.applyCommands();
    
    auto entitySystem = EntitySystem(video, 
                                     input,
                                     gameTime,
                                     camera,
                                     map,
                                     cfg.threadCount,
                                     profilers, 
                                     log);
    entitySystem.schedulingAlgorithm = cfg.schedAlgo;
    scope(failure) { log.critical("Unexpected failure in the main loop"); }

    // Run the game itself.
    try if(!mainLoop(entitySystem, map, video, input, gameTime, cameraControl, profilers, log))
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
            log.warningf("Profiler for thread %s ran out of memory while "
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
 * Catches any uncaught throwables.
 */
int main(string[] args)
{
    scope(exit) { writeln("main() exit"); }
    try
    {
        return execute(args);
    }
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a command-line has incorrect format?\n",
                "error: ", e.msg);
    }
    catch(Throwable e)
    {
        writeln("Unhandled Throwable at top level: ", e);
    }
    return 1;
}
