//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Processes operating on entities in the game.
module entity.processes;


import std.exception;
import std.logger;

import gl3n_extra.linalg;

import entity.components;
import game.camera;

public import entity.renderprocess;





/// Process used to determine which entities are being 'picked' by the mouse.
final class MousePickingProcess
{
private:
    // Game log.
    Logger log_;

    // 2D isometric camera used to get screen coordinates of objects.
    const(Camera) camera_;

    import platform.inputdevice;
    // Used to read mouse state.
    const(Mouse) mouse_;

    import gl3n_extra.box;
    // The area selected by the mouse. Point if clicking, rectangle if dragging.
    box2i selectionBox_;

    // The radius around selectionBox_ where all entities are picked.
    size_t pickingRadius_ = 8;

    alias State = PickingComponent.State;

    // 'State' of picking. Picked if LMB is clicked, MouseOver otherwise.
    State state_ = State.MouseOver;

public:
    alias PickingComponent FutureComponent;

    /** Construct a MousePickingProcess.
     *
     * Params:
     *
     * log    = Game log.
     * mouse  = Provides access to mouse state.
     * camera = 2D isometric camera.
     */
    this(const(Camera) camera, const(Mouse) mouse, Logger log) @safe pure nothrow @nogc
    {
        camera_ = camera;
        mouse_  = mouse;
        log_    = log;
    }

    /// Determine the selection area and whether the mouse is clicked or not.
    void preProcess() @safe pure nothrow @nogc
    {
        state_ = mouse_.clicked(Mouse.Button.Left) ? State.Picked : State.MouseOver;
        vec2i mousePos = vec2i(mouse_.x, mouse_.y);

        selectionBox_ = box2i(mouse_.pressedCoords(Mouse.Button.Left), mousePos);
    }

    /// Determine if an entity is being picked.
    void process(ref const PositionComponent pos, ref PickingComponent* picking)
        nothrow
    {
        const screenCoords = camera_.worldToScreen(vec3(pos.x, pos.y, pos.z));

        // If there is a PickingComponent from the previous frame, remove it.
        if(selectionBox_.distance(screenCoords) < pickingRadius_)
        {
            *picking = PickingComponent(state_, selectionBox_);
            return;
        }
        picking = null;
    }
}


/// Handles entity selection (player selecting units).
final class SelectionProcess
{
private:
    // Game log.
    Logger log_;
    import platform.inputdevice;
    //  Mouse input access (for deselecting with left click).
    const(Mouse) mouse_;

    // Should any selected entities be deselected during this frame?
    bool deselect_;

public:
    alias FutureComponent = SelectionComponent;
    /** Construct a SelectionProcess.
     *
     * Params:
     *
     * mouse = Mouse input access (for deselecting with left click).
     * log   = Game log.
     */
    this(const(Mouse) mouse, Logger log) @safe pure nothrow @nogc
    {
        mouse_ = mouse;
        log_   = log;
    }

    /// Determine if we should deselect current selection.
    void preProcess() nothrow
    {
        // If LMB is pressed, deselect current selection.
        deselect_ = mouse_.clicked(Mouse.Button.Left);
    }

    /// Select a picked entity (if really picked, not just hovered).
    void process(ref const PickingComponent pick, ref SelectionComponent* select)
        nothrow
    {
        if(pick.state == PickingComponent.State.Picked)
        {
            *select = SelectionComponent();
            return;
        }
        select = null;
    }

    /// Keep an entity selected or deselect it depending on mouse input this frame.
    void process(ref const SelectionComponent past, ref SelectionComponent* future)
        nothrow
    {
        if(deselect_)
        {
            future = null;
            return;
        }
        *future = past;
    }

    /// Handle an entity that is both picked/hovered and selected.
    void process(ref const PickingComponent pick,
                 ref const SelectionComponent selectPast,
                 ref SelectionComponent* selectFuture)
        nothrow
    {
        // If a selected entity is picked again, just 're-select' it.
        // If it's not picked, check if we need to deselect it.
        (pick.state == PickingComponent.State.Picked) ? process(pick, selectFuture)
                                                      : process(selectPast, selectFuture);
    }
}


/// Process that assigns commands (e.g. move to point) to individual entities.
final class CommandProcess
{
private:
    // Game log.
    Logger log_;

    import platform.inputdevice;
    // Access for mouse input.
    const(Mouse) mouse_;
    // Camera to transform mouse coords to world space.
    const(Camera) camera_;

    // If true, there is no command for selected units this frame.
    bool noCommandForSelected_ = true;

    // Command we're about to give to selected entities.
    CommandComponent commandForSelected_;

    // If an entity with a MoveTo command is at least this close to its target, there's
    // no need to continue moving.
    enum closeEnough = 67.0f;

public:
    alias FutureComponent = CommandComponent;

    /** Construct a CommandProcess.
     *
     * Params:
     *
     * mouse  = Access to mouse input.
     * camera = Camera to transform mouse coords to world space.
     * log    = Game log.
     */
    this(const(Mouse) mouse, const(Camera) camera, Logger log) @safe pure nothrow @nogc
    {
        log_    = log;
        mouse_  = mouse;
        camera_ = camera;
    }

    /// Determine which commands to give this frame.
    void preProcess() nothrow
    {
        noCommandForSelected_ = true;
        // Right click means 'move to'
        if(mouse_.clicked(Mouse.Button.Right))
        {
            import gl3n_extra.plane;
            // For now we assume the map is one big flat plane.
            const mapPlane = planeFromPointNormal(vec3(0, 0, 0), vec3(0, 0, 1));

            // Create a line in world space from a point on the screen.
            const linePoint1 = camera_.screenToWorld(vec3(mouse_.x, mouse_.y, 0.0f));
            const linePoint2 = camera_.screenToWorld(vec3(mouse_.x, mouse_.y, -100.0f));
            const lineVector = linePoint2 - linePoint1;

            // Intersect the line with the map to find the point to move to.
            vec3 mapPoint;
            if(mapPlane.intersectsLine(linePoint1, lineVector, mapPoint))
            {
                noCommandForSelected_      = false;
                commandForSelected_.type   = CommandComponent.Type.MoveTo;
                commandForSelected_.moveTo = mapPoint;
            }

        }
    }

    /** Add a command component to an entity that doesn't have one.
     *
     * We only give movement commands to entities that have engines.
     */
    void process(ref const PositionComponent pos,
                 ref const SelectionComponent select,
                 ref const EngineComponent engine,
                 ref CommandComponent* command) nothrow
    {
        if(noCommandForSelected_)
        {
            command = null;
            return;
        }
        *command = commandForSelected_;
    }

    /// Update (or cancel) command of an entity that already has a command assigned.
    void process(ref const PositionComponent pos,
                 ref const CommandComponent commandPast,
                 ref CommandComponent* commandFuture) nothrow
    {
        with(CommandComponent.Type) final switch(commandPast.type)
        {
            case MoveTo:
                if(distance(commandPast.moveTo, vec3(pos.x, pos.y, pos.z)) < closeEnough)
                {
                    commandFuture = null;
                    break;
                }
                *commandFuture = commandPast;
                break;
        }
    }

    /// Handle an entity that is both selected and has a command already.
    void process(ref const PositionComponent pos,
                 ref const SelectionComponent select,
                 ref const EngineComponent engine,
                 ref const CommandComponent commandPast,
                 ref CommandComponent* commandFuture) nothrow
    {
        noCommandForSelected_ ? process(pos, commandPast, commandFuture)
                              : process(pos, select, engine, commandFuture);
    }
}

import tharsis.defaults.copyprocess;
/// Until a need to modify engines at runtime comes up, this can be a simple CopyProcess.
alias EngineProcess = CopyProcess!EngineComponent;

/// Updates DynamicComponents of entities (velocity for now).
final class DynamicProcess
{
private:
    // Game log.
    Logger log_;

public:
    alias FutureComponent = DynamicComponent;

    /** Construct a DynamicProcess.
     *
     * Params:
     *
     * log = The game log.
     */
    this(Logger log) @safe pure nothrow @nogc
    {
        log_ = log;
    }

    /** Update dynamics of entities with an engine.
     *
     * CommandComponent is used to tell the engine what to do (this will change once
     * there is a PathingProcess between here and CommandProcess)
     *
     * PositionComponent is needed to determine how we need to use the engine to get
     * to the command's target position. This may change too once PathingProcess exists.
     */
    void process(ref const DynamicComponent dynamicPast,
                 ref const EngineComponent engine,
                 ref const CommandComponent command,
                 ref const PositionComponent pos,
                 out DynamicComponent dynamicFuture)
        nothrow
    {
        // By default, don't change the component.
        dynamicFuture = dynamicPast;
        with(CommandComponent.Type) final switch(command.type)
        {
            case MoveTo:
                // Current position.
                const vec3 p      = vec3(pos.x, pos.y, pos.z);
                const vec3 target = command.moveTo;
                // Vector from current position to target.
                const vec3 toTarget = target - p;
                const vec3 velocity = vec3(dynamicPast.velocityX,
                                           dynamicPast.velocityY,
                                           dynamicPast.velocityZ);
                const vec3 currentDir = velocity.normalized;
                // Direction we want to go in.
                const vec3 wantedDir  = toTarget.normalized;

                // Direction to apply the acceleration in. We want to cancel the current
                // direction and replace it with wanted direction.
                const vec3 accelDir = (wantedDir - currentDir * 0.5).normalized;
                const vec3 accel = engine.acceleration * accelDir;

                vec3 futureVelocity = velocity + accel;
                if(futureVelocity.length >= engine.maxSpeed)
                {
                    futureVelocity.setLength(engine.maxSpeed);
                }

                dynamicFuture = DynamicComponent(futureVelocity.x,
                                                 futureVelocity.y,
                                                 futureVelocity.z);
                return;
        }
    }

    /// Keep dynamic components of entities that are not being accelerated by anything.
    void process(ref const DynamicComponent dynamicPast,
                 out DynamicComponent dynamicFuture)
        nothrow
    {
        dynamicFuture = dynamicPast;
    }

    /// Decelerate entities with that have an engine but no command to move anywhere.
    void process(ref const DynamicComponent dynamicPast,
                 ref const EngineComponent engine,
                 ref const PositionComponent pos,
                 out DynamicComponent dynamicFuture)
        nothrow
    {
        vec3 velocity = vec3(dynamicPast.velocityX,
                             dynamicPast.velocityY,
                             dynamicPast.velocityZ);
        if(velocity.length == 0.0f)
        {
            dynamicFuture = dynamicPast;
            return;
        }

        import std.algorithm;
        velocity.setLength(max(0.0f, velocity.length - engine.acceleration));
        dynamicFuture = DynamicComponent(velocity.x, velocity.y, velocity.z);
    }
}


/// Applies DynamicComponents to PositionComponents, updating entity positions.
final class PositionProcess
{
private:
    // Game log.
    Logger log_;

    import time.gametime;
    // Game time for access to time step.
    const(GameTime) gameTime_;

public:
    alias FutureComponent = PositionComponent;

    /** Construct a PositionProcess.
     *
     * Params:
     *
     * gameTime = Game time for access to time step.
     * log      = The game log.
     */
    this(const(GameTime) gameTime, Logger log) @safe pure nothrow @nogc
    {
        gameTime_ = gameTime;
        log_      = log;
    }

    /// Update position of an entity with a dynamic component.
    void process(ref const PositionComponent posPast,
                 ref const DynamicComponent dynamic,
                 out PositionComponent posFuture) nothrow
    {
        const timeStep = gameTime_.timeStep;
        posFuture.x = posPast.x + timeStep * dynamic.velocityX;
        posFuture.y = posPast.y + timeStep * dynamic.velocityY;
        posFuture.z = posPast.z + timeStep * dynamic.velocityZ;
    }

    /// Keep position of an entity that has no DynamicComponent.
    void process(ref const PositionComponent posPast, out PositionComponent posFuture)
        nothrow
    {
        posFuture = posPast;
    }
}


/** Implements weapon logic and updates weapon components.
 *
 * Projectile spawning is actually handled by SpawnerAttachProcess, which attaches 
 * spawner components to spawn projectiles and WeaponizedSpawnerProcess which spawns
 * them when a WeaponMultiComponent has negative $(D secsWithBurst).
 */
final class WeaponProcess 
{
private:
    // Game log.
    Logger log_;

    import time.gametime;
    // Game time for access to time step.
    const GameTime gameTime_;

    import entity.resources;
    // Weapon resource manager.
    WeaponManager weaponMgr_;

public:
    alias FutureComponent = WeaponMultiComponent;

    /** Construct a WeaponProcess.
     *
     * Params:
     *
     * gameTime      = Game time for access to time step.
     * weaponManager = Weapon resource manager.
     * log           = The game log.
     */
    this(const GameTime gameTime, WeaponManager weaponManager, Logger log)
        @safe pure nothrow @nogc
    {
        gameTime_  = gameTime;
        weaponMgr_ = weaponManager;
        log_       = log;
    }

    void process(const WeaponMultiComponent[] weaponsPast,
                 ref WeaponMultiComponent[] weaponsFuture) nothrow
    {
        const timeStep    = gameTime_.timeStep;
        const weaponCount = weaponsPast.length;
        weaponsFuture     = weaponsFuture[0 .. weaponCount];

        weaponsFuture[] = weaponsPast[];
        foreach(ref weapon; weaponsFuture)
        {
            import tharsis.entity.resourcemanager;

            const handle = weapon.weapon;
            const state  = weaponMgr_.state(handle);
            // If the weapon is not loaded yet, load it and don't update weapon logic.
            if(state == ResourceState.New) { weaponMgr_.requestLoad(handle); }
            if(state != ResourceState.Loaded) { continue; }

            // First check if we've reached time to fire, then update secsTillBurst.
            // If secsTillBurst will become lower than 0, SpawnerProcess 
            // will notice in the next frame and spawn projectiles.
            const burstPeriod = weaponMgr_.resource(handle).burstPeriod;
            if(weapon.secsTillBurst <= 0.0f)
            {
                weapon.secsTillBurst += burstPeriod;
            }
            weapon.secsTillBurst -= timeStep;

        }
    }
}
