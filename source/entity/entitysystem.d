//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Manages Tharsis and all Processes used by the game.
module entity.entitysystem;


import std.exception;
import std.logger;

import tharsis.entity.componenttypemanager;
import tharsis.entity.entitymanager;
import tharsis.entity.entitypolicy;
import tharsis.entity.lifecomponent;
import tharsis.entity.prototypemanager;

import entity.components;
import entity.processes;
import platform.inputdevice;
import platform.videodevice;


/// Manages Tharsis and all Processes used by the game.
struct EntitySystem
{
private:
    // Game log.
    Logger log_;

    import tharsis.entity.entityprototype;
    import tharsis.defaults.yamlsource;
    import tharsis.prof;

    // Resource handles of prototypes of entities that should be spawned ASAP.
    PrototypeManager.Handle[] prototypesToSpawn_;

    // Component types are registered here.
    ComponentTypeManager!YAMLSource componentTypeMgr_;

    // Stores entities and their components.
    DefaultEntityManager entityMgr_;

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

    import tharsis.defaults.components;
    import tharsis.defaults.processes;

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

        componentTypeMgr_.lock();

        entityMgr_      = new DefaultEntityManager(componentTypeMgr_, threadCount);
        entityMgr_.attachPerThreadProfilers(threadProfilers_);
        entityMgr_.startThreads().assumeWontThrow();

        import entity.resources;
        prototypeMgr_   = new PrototypeManager(componentTypeMgr_, entityMgr_);
        auto weaponMgr_ = new WeaponManager(entityMgr_, componentTypeMgr_.sourceLoader,
                                            componentTypeMgr_);

        import tharsis.defaults.copyprocess;
        auto dummyVisual   = new CopyProcess!VisualComponent();
        auto dummyLife     = new CopyProcess!LifeComponent();
        renderer_          = new RenderProcess(video, input.keyboard, input.mouse, camera, log);
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
        entityMgr_.registerProcess(dummyLife);
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
        entityMgr_.registerProcess(renderer_);

        entityMgr_.registerResourceManager(prototypeMgr_);
        entityMgr_.registerResourceManager(weaponMgr_);

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
        renderer_.destroy().assumeWontThrow;
        entityMgr_.destroy();
        componentTypeMgr_.destroy();
    }

    /// Get EntityManager diagnostics for the last frame.
    ref auto diagnostics() @safe pure nothrow const @nogc
    {
        return diagnostics_;
    }

    /// Execute one frame (game update) of the entity system.
    void frame() @safe nothrow
    {
        auto zone = Zone(threadProfilers_[0], "EntitySystem.frame");
        size_t handleCount = 0;
        foreach(i, handle; prototypesToSpawn_)
        {
            import tharsis.entity.resourcemanager;
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
            import tharsis.defaults.diagnostics;
            import io.yaml;

            log_.info(diagnostics_.toYAML.dumpToString).assumeWontThrow;
        }
    }
}
