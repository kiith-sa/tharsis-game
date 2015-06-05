//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Manages Tharsis and all Processes used by the game.
module entity.entitysystem;


import std.exception;
import std.experimental.logger;

import tharsis.entity;

import entity.components;
import entity.processes;
import entity.schedulingalgorithmtype;
import platform.inputdevice;
import platform.videodevice;

/// The entity manager we're using.
alias EntityMgr = DefaultEntityManager;

/// Entity context we're using (passed to some Processes).
alias EntityContext = EntityMgr.Context;

/// Manages Tharsis and all Processes used by the game.
struct EntitySystem
{
private:
    // Game log.
    Logger log_;

    import tharsis.prof;

    // Resource handles of prototypes of entities that should be spawned ASAP.
    PrototypeManager.Handle[] prototypesToSpawn_;

    // Component types are registered here.
    ComponentTypeManager!YAMLSource componentTypeMgr_;

    // Tharsis scheduler used by entityMgr_.
    Scheduler scheduler_;

    // Currently used scheduling algorithm.
    SchedulingAlgorithmType schedulingAlgorithm_;

    // Stores entities and their components.
    EntityMgr entityMgr_;

    // EntityManager diagnostics like entity counts, process execution times, etc.
    entityMgr_.Diagnostics diagnostics_;

    // Resource manager handling entity prototypes.
    PrototypeManager prototypeMgr_;

    // Keyboard and mouse input.
    const InputDevice input_;

    // Frame profilers used to profile the game and Tharsis. One profiler per thread.
    Profiler[] threadProfilers_;

    // Process used to render entities' graphics.
    RenderProcess renderer_;

    import tharsis.defaults;

    import game.camera;
    import time.gametime;

public:
    /** Construct an EntitySystem, initializing Tharsis.
     *
     * Params:
     *
     * video           = VideoDevice for any processes that need to draw.
     * input           = User input device.
     * time            = Keeps track of game time.
     * camera          = Isometric amera.
     * threadCount     = Number of threads for Tharsis to use. 0 is autodetect.
     * threadProfilers = Profilers profiling both the game and Tharsis execution in the
     *                   main thread as well as any extra threads used by Tharsis. One
     *                   profiler per thread.
     * log             = Game log.
     */
    this(VideoDevice video, InputDevice input, GameTime time, Camera camera,
         uint threadCount, Profiler[] threadProfilers, Logger log)
        @safe nothrow //!@nogc
    {
        auto zone = Zone(threadProfilers[0], "EntitySystem.this");

        log_             = log;
        input_           = input;
        threadProfilers_ = threadProfilers;
        componentTypeMgr_ = new ComponentTypeManager!YAMLSource(YAMLSource.Loader());
        componentTypeMgr_.registerComponentTypes!(PositionComponent,
                                                  VisualComponent,
                                                  PickingComponent,
                                                  SelectionComponent,
                                                  CommandComponent,
                                                  EngineComponent,
                                                  DynamicComponent,
                                                  WeaponMultiComponent,
                                                  SpawnerMultiComponent,
                                                  TimedTriggerMultiComponent);

        // Data of a dummy (performance testing) component.
        static struct DummyData(ushort DummyID)
        {
            float[4] someFloats;
            uint aUint;
            bool[2 + DummyID % 8] someBools;

            int opCmp(ref DummyData rhs) @trusted pure nothrow const
            {
                import core.stdc.string;
                return memcmp(&this, &rhs, DummyData.sizeof);
            }
        }

        import std.typetuple;
        // Generates dummy component types recursively.
        template GenDummyComponents(ushort dummyID)
        {
            static if(dummyID > 0)
            {
                alias Dummy = dummyComponent!(userComponentTypeID!(dummyID + 32),
                                              DummyData!dummyID);
                alias GenDummyComponents = TypeTuple!(Dummy, GenDummyComponents!(dummyID - 1));
            }
            else
            {
                alias GenDummyComponents = TypeTuple!();
            }
        }

        // Number of dummy component types.
        enum dummyComponentCount = 64;
        alias DummyComponents = GenDummyComponents!dummyComponentCount;
        // pragma(msg, DummyComponents);
        componentTypeMgr_.registerComponentTypes!DummyComponents;

        // Number of past component types read by each dummy process
        const pastComponentCount = 3;

        void registerDummyProcesses(ushort dummyID)()
        {
            static if(dummyID > 0)
            {
                import std.string: format;
                import std.algorithm: join;
                string generateSig()
                {
                    string[] parts;
                    foreach(p; 0 .. pastComponentCount)
                    {
                        parts ~= "ref const DummyComponents[%s] past%s"
                                 .format((dummyID + p) % dummyComponentCount, p);
                    }
                    parts ~= "out DummyComponents[%s] future".format(dummyID - 1);
                    return "(%s) => 0".format(parts.join(", "));
                }
                mixin(q{
                alias Dummy = DummyProcess!(%s);
                }.format(generateSig()));

                // Just a regular overhead pattern for now.
                entityMgr_.registerProcess(new Dummy([1], [1]));
                registerDummyProcesses!(dummyID - 1);
            }
        }

        componentTypeMgr_.lock();

        scheduler_ = new Scheduler(threadCount);
        entityMgr_ = new EntityMgr(componentTypeMgr_, scheduler_);
        schedulingAlgorithm = SchedulingAlgorithmType.init;
        entityMgr_.attachPerThreadProfilers(threadProfilers_);
        entityMgr_.startThreads().assumeWontThrow();

        import entity.resources;
        prototypeMgr_   = new PrototypeManager(componentTypeMgr_, entityMgr_);
        auto weaponMgr_ = new WeaponManager(entityMgr_, componentTypeMgr_.sourceLoader,
                                            componentTypeMgr_);

        import gl3n_extra.linalg;
        auto dummyVisual   = new CopyProcess!VisualComponent();
        auto life          = new LifeProcess();
        auto picking       = new MousePickingProcess(camera, input.mouse, log);
        auto selection     = new SelectionProcess(input.mouse, log);
        auto command       = new CommandProcess(input.mouse, input.keyboard, camera, log);
        auto engine        = new EngineProcess();
        auto dynamic       = new DynamicProcess(time, log);
        auto position      = new PositionProcess(time, log);
        auto weapon        = new WeaponProcess(time, weaponMgr_, log);
        auto spawnerAttach = new SpawnerAttachProcess(time, weaponMgr_, log);
        auto conditionProc = new TimedTriggerProcess(&time.timeStep);
        auto spawner       = new WeaponizedSpawnerProcess(&entityMgr_.addEntity, prototypeMgr_,
                                                          componentTypeMgr_, log);

        entityMgr_.registerProcess(dummyVisual);
        entityMgr_.registerProcess(life);
        entityMgr_.registerProcess(picking);
        entityMgr_.registerProcess(selection);
        entityMgr_.registerProcess(command);
        entityMgr_.registerProcess(engine);
        entityMgr_.registerProcess(dynamic);
        entityMgr_.registerProcess(position);
        entityMgr_.registerProcess(weapon);
        entityMgr_.registerProcess(spawnerAttach);
        entityMgr_.registerProcess(conditionProc);
        entityMgr_.registerProcess(spawner);

        registerDummyProcesses!dummyComponentCount;
        if(video !is null)
        {
            renderer_ = new RenderProcess(video, input.keyboard, input.mouse, camera, log);
            entityMgr_.registerProcess(renderer_);
        }

        entityMgr_.registerResourceManager(prototypeMgr_);
        entityMgr_.registerResourceManager(weaponMgr_);
    }


    /// Spawn entity from specified file as soon as possible.
    ///
    /// Params:
    ///
    /// fileName = Name of the file to load the entity from.
    void spawnEntityASAP(string fileName) @trusted nothrow
    {
        auto zone = Zone(threadProfilers_[0], "EntitySystem.~spawnEntityASAP");
        auto descriptor = EntityPrototypeResource.Descriptor(fileName);
        const handle    = prototypeMgr_.handle(descriptor);
        prototypesToSpawn_.assumeSafeAppend();
        prototypesToSpawn_ ~= handle;
        log_.infof("Will spawn entity from prototype %s ASAP", handle.rawHandle)
            .assumeWontThrow;
        prototypeMgr_.requestLoad(handle);
    }

    /// Destroy the entity system along with all entities, components and resource managers.
    ~this()
    {
        auto zone = Zone(threadProfilers_[0], "EntitySystem.~this");
        if(!headless)
        {
            renderer_.destroy().assumeWontThrow;
        }
        entityMgr_.destroy();
        componentTypeMgr_.destroy();
    }

    /// Get EntityManager diagnostics for the last frame.
    ref auto diagnostics() @safe pure nothrow const @nogc
    {
        return diagnostics_;
    }

    /// Are we headless (no renderer process - no graphics)?
    bool headless() @safe pure nothrow const @nogc
    {
        return renderer_ is null;
    }

    /// Set the scheduling algorithm to use. Must not be called during a frame.
    void schedulingAlgorithm(SchedulingAlgorithmType algorithm) @safe nothrow
    {
        schedulingAlgorithm_ = algorithm;
        const t = scheduler_.threadCount;
        void setSched(SchedulingAlgorithm a) nothrow { scheduler_.schedulingAlgorithm = a; }

        final switch(algorithm) with(SchedulingAlgorithmType)
        {
            case LPT:       setSched(new LPTScheduling(t));                      break;
            case Dumb:      setSched(new DumbScheduling(t));                     break;
            case BRUTE:     setSched(new PlainBacktrackScheduling(t));           break;
            case RBt400r3:  setSched(new RandomBacktrackScheduling(t, 400, 3));  break;
            case RBt800r6:  setSched(new RandomBacktrackScheduling(t, 800, 6));  break;
            case RBt1600r9: setSched(new RandomBacktrackScheduling(t, 1600, 9)); break;
            case COMBINE:   setSched(new COMBINEScheduling(t));                  break;
            case DJMS:      setSched(new DJMSScheduling(t));                     break;
        }
    }

    /// Get the currently used scheduling algorithm.
    SchedulingAlgorithmType schedulingAlgorithm() @safe pure nothrow const @nogc
    {
        return schedulingAlgorithm_;
    }

    /// Execute one frame (game update) of the entity system.
    void frame() @safe nothrow
    {
        auto zone = Zone(threadProfilers_[0], "EntitySystem.frame");
        size_t handleCount = 0;
        
        foreach(i, handle; prototypesToSpawn_)
        {
            if(prototypeMgr_.state(handle) == ResourceState.Loaded)
            {
                log_.infof("Spawned entity from prototype %s", handle.rawHandle)
                    .assumeWontThrow;
                entityMgr_.addEntity(prototypeMgr_.resource(handle).prototype);
                continue;
            }
            // Only keep handles of prototypes we didn't spawn.
            prototypesToSpawn_[handleCount++] = handle;
        }
        prototypesToSpawn_.length = handleCount;

        entityMgr_.executeFrame();

        diagnostics_ = entityMgr_.diagnostics;
        if(input_.keyboard.pressed(Key.F1))
        {
            import io.yaml;

            log_.info(diagnostics_.toYAML.dumpToString).assumeWontThrow;
        }
        if(input_.keyboard.pressed(Key.F5))
        {
            log_.infof(prototypeMgr_.errorLog).assumeWontThrow;
        }
    }
}
