//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Manages Tharsis and all Processes used by the game.
module entity.entitysystem;


import std.logger;

import tharsis.entity.componenttypemanager;
import tharsis.entity.entitymanager;
import tharsis.entity.entitypolicy;
import tharsis.entity.lifecomponent;
import tharsis.entity.prototypemanager;


import entity.components;

/// Manages Tharsis and all Processes used by the game.
struct EntitySystem
{
private:
    // Game log.
    Logger log_;

    import tharsis.defaults.yamlsource;

    // Component types are registered here.
    ComponentTypeManager!YAMLSource componentTypeMgr_;

    // Stores entities and their components.
    DefaultEntityManager entityMgr_;

    // Resource manager handling entity prototypes.
    PrototypeManager prototypeMgr_;

public:
    /// Construct an EntitySystem, initializing Tharsis.
    this(Logger log) @safe nothrow //!@nogc
    {
        log_ = log;
        componentTypeMgr_ = new ComponentTypeManager!YAMLSource(YAMLSource.Loader());
        componentTypeMgr_.registerComponentTypes!(PositionComponent,
                                                  VisualComponent);
        componentTypeMgr_.lock();

        entityMgr_ = new DefaultEntityManager(componentTypeMgr_);

        prototypeMgr_ = new PrototypeManager(componentTypeMgr_, entityMgr_);

        import tharsis.defaults.copyprocess;
        auto dummyPosition = new CopyProcess!PositionComponent();
        auto dummyVisual   = new CopyProcess!VisualComponent();
        auto dummyLife     = new CopyProcess!LifeComponent();

        entityMgr_.registerProcess(dummyPosition);
        entityMgr_.registerProcess(dummyVisual);
        entityMgr_.registerProcess(dummyLife);
        entityMgr_.registerResourceManager(prototypeMgr_);
    }

    /// Destroy the entity system along with all entities, components and resource managers.
    ~this()
    {
        entityMgr_.destroy();
        componentTypeMgr_.destroy();
    }

    /// Execute one frame (game update) of the entity system.
    void frame() @safe nothrow
    {
        entityMgr_.executeFrame();
    }
}
