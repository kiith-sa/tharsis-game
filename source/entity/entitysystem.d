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

    // Resource handles of prototypes of entities that should be spawned ASAP.
    PrototypeManager.Handle[] prototypesToSpawn_;

    // Component types are registered here.
    ComponentTypeManager!YAMLSource componentTypeMgr_;

    // Stores entities and their components.
    DefaultEntityManager entityMgr_;

    // Resource manager handling entity prototypes.
    PrototypeManager prototypeMgr_;




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
     * video  = VideoDevice for any processes that need to draw.
     * input  = User input device.
     * time   = Keeps track of game time.
     * camera = Isometric amera.
     * log    = Game log.
     */
    this(VideoDevice video, InputDevice input, GameTime time, Camera camera, Logger log)
        @safe nothrow //!@nogc
    {
        log_ = log;
        componentTypeMgr_ = new ComponentTypeManager!YAMLSource(YAMLSource.Loader());
        componentTypeMgr_.registerComponentTypes!(PositionComponent,
                                                  VisualComponent,
                                                  PickingComponent,
                                                  SelectionComponent,
                                                  CommandComponent,
                                                  EngineComponent,
                                                  DynamicComponent,
                                                  SpawnerMultiComponent,
                                                  TimedTriggerMultiComponent);

        componentTypeMgr_.lock();

        entityMgr_ = new DefaultEntityManager(componentTypeMgr_);

        prototypeMgr_ = new PrototypeManager(componentTypeMgr_, entityMgr_);
        
        import tharsis.defaults.copyprocess;
        auto dummyVisual   = new CopyProcess!VisualComponent();
        auto dummyLife     = new CopyProcess!LifeComponent();
        renderer_          = new RenderProcess(video, camera, log);
        auto picking       = new MousePickingProcess(camera, input.mouse, log);
        auto selection     = new SelectionProcess(input.mouse, log);
        auto command       = new CommandProcess(input.mouse, camera, log);
        auto engine        = new EngineProcess();
        auto dynamic       = new DynamicProcess(log);
        auto position      = new PositionProcess(time, log);

        auto conditionProc = new TimedTriggerProcess(&time.timeStep);
        auto spawner = new DefaultSpawnerProcess(&entityMgr_.addEntity, prototypeMgr_,
                                                 componentTypeMgr_);

        entityMgr_.registerProcess(dummyVisual);
        entityMgr_.registerProcess(dummyLife);
        entityMgr_.registerProcess(renderer_);
        entityMgr_.registerProcess(picking);
        entityMgr_.registerProcess(selection);
        entityMgr_.registerProcess(command);
        entityMgr_.registerProcess(engine);
        entityMgr_.registerProcess(position);
        entityMgr_.registerProcess(conditionProc);
        entityMgr_.registerProcess(spawner);
        entityMgr_.registerProcess(dynamic);
        entityMgr_.registerProcess(new CopyProcess!SpawnerMultiComponent());

        entityMgr_.registerResourceManager(prototypeMgr_);

    /// Spawn entity from specified file as soon as possible.
    ///
    /// Params:
    ///
    /// fileName = Name of the file to load the entity from.
    void spawnEntityASAP(string fileName) @trusted nothrow
    {
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
        renderer_.destroy().assumeWontThrow;
        entityMgr_.destroy();
        componentTypeMgr_.destroy();
    }

    /// Execute one frame (game update) of the entity system.
    void frame() @safe nothrow
    {
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
    }
}
