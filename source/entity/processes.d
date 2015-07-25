//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Processes operating on entities in the game.
module entity.processes;


import std.exception;
import std.experimental.logger;
import std.stdio;

import gl3n_extra.linalg;

import entity.components;
import game.camera;
import game.map;

import entity.entitysystem;

public import entity.commandprocess;
public import entity.renderprocess;
public import entity.weaponizedspawnerprocess;

// TODO: Low-frequency components such as picking, selection and command should possibly
// be replaced by some other mechanism. Look at the EntityX entity system and its
// events.
// 2014-08-20



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
        const screenCoords = camera_.worldToScreen(pos);

        // If there is a PickingComponent from the previous frame, remove it.
        if(selectionBox_.squaredDistance(screenCoords) < pickingRadius_ * pickingRadius_)
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
    alias FutureComponent = SelectableComponent;
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

    // TODO In future, SelectionProcess will use other mechanisms besides picking
    // (e.g. keyboard shortcuts like T in RA2 and maybe pentadactyl-style keyboard
    // selection) 2014-08-19


    /// Keep an entity selected or deselect it depending on mouse input this frame.
    void process(ref const SelectableComponent past, out SelectableComponent future)
        nothrow
    {
        future = past;
        if(deselect_)
        {
            future.isSelected = false;
        }
    }

    /// Handle an entity that is both picked/hovered and selected.
    void process(ref const PickingComponent pick,
                 ref const SelectableComponent selectPast,
                 out SelectableComponent selectFuture)
        nothrow
    {
        if(pick.state == PickingComponent.State.Picked)
        {
            selectFuture = selectPast;
            selectFuture.isSelected = true;
        }
        else
        {
            process(selectPast, selectFuture);
        }
    }
}



import tharsis.defaults;
/// Until a need to modify engines at runtime comes up, this can be a simple CopyProcess.
alias EngineProcess = CopyProcess!EngineComponent;

/// Updates DynamicComponents of entities (velocity for now).
final class DynamicProcess
{
private:
    import time.gametime;
    // Game time, for time step.
    const GameTime time_;

    // Game map.
    const(Map) map_;

    // Game log.
    Logger log_;

public:
    alias FutureComponent = DynamicComponent;

    /** Construct a DynamicProcess.
     *
     * Params:
     *
     * time = Game time, for time step.
     * map  = Game map.
     * log  = The game log.
     */
    this(const(GameTime) time, const(Map) map, Logger log) @safe pure nothrow @nogc
    {
        time_ = time;
        map_  = map;
        log_  = log;
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
        dynamicFuture.rotTarget = vec3(0, 0, 0);

        const timeStep = time_.timeStep;

        with(CommandComponent.Type) final switch(command.type)
        {
            case MoveTo:
                /* Old code for 'no rotation locomotor' where engine can be applied to
                 * any direction, so rotation is not necessary for movement (but add
                 * rotation so the object faces the target at least)
                const vec3 target = command.moveTo;
                // Vector from current position to target.
                const vec3 toTarget = target - pos;
                const vec3 currentDir = dynamicPast.velocity.normalized;
                // Direction we want to go in.
                const vec3 wantedDir  = toTarget.normalized;

                // Direction to apply the acceleration in. We want to cancel the current
                // direction and replace it with wanted direction.
                const vec3 accelDir = (wantedDir - currentDir * 0.5).normalized;
                const vec3 accel = engine.acceleration * accelDir * timeStep;

                vec3 futureVelocity = dynamicPast.velocity + accel;
                if(futureVelocity.length >= engine.maxSpeed)
                {
                    futureVelocity.setLength(engine.maxSpeed);
                }

                dynamicFuture = DynamicComponent(futureVelocity);
                */


                const vec3 target = command.moveTo;
                // Vector from current position to target.
                const vec3 toTarget = target - pos;
                const vec3 pastVelocity = dynamicPast.velocity;
                // Direction we want to go in.
                const vec3 wantedDir = toTarget.normalized;
                const speed = pastVelocity.length;
                vec3 velocity;

                // Determines whether we're accelerating or decelerating
                // const int accelDir = 1;
                const int accelDir = 
                    // if we're so close that the distance taken while decelerating is 
                    // more than distance to target, decelerate
                    (speed / engine.acceleration) * 
                    (speed / 2) >= toTarget.length ? -1 : 
                    // otherwise, accelerate (we will still clamp velocity to maxSpeed)
                    1;

                final switch(engine.movementType)
                {
                    case MovementType.Flying:
                        const vec3 accel = 
                            engine.acceleration * (accelDir * pos.facing) * timeStep;
                        velocity = dynamicPast.velocity + accel;
                        break;
                    case MovementType.Infantry:
                    case MovementType.Vehicle:
                        break;
                }

                if(velocity.length >= engine.maxSpeed)
                {
                    velocity.setLength(engine.maxSpeed);
                }
                dynamicFuture = DynamicComponent(velocity, engine.rotSpeed, wantedDir);
                break;
            case StaticFireAt:
                break;
        }
    }

    /// Keep dynamic components of entities that are not being accelerated by anything.
    mixin(preserveComponentsMixin);

    /// Decelerate entities with that have an engine but no command to move anywhere.
    void process(ref const DynamicComponent dynamicPast,
                 ref const EngineComponent engine,
                 ref const PositionComponent pos,
                 out DynamicComponent dynamicFuture)
        nothrow
    {
        vec3 velocity = dynamicPast.velocity;
        if(velocity.length == 0.0f)
        {
            dynamicFuture = dynamicPast;
            dynamicFuture.rotTarget = vec3(0, 0, 0);
            return;
        }

        import std.algorithm;
        const timeStep = time_.timeStep;
        velocity.setLength(max(0.0f, velocity.length - engine.acceleration * timeStep));
        dynamicFuture = DynamicComponent(velocity);
        dynamicFuture.rotTarget = vec3(0, 0, 0);
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
    // Game map.
    const(Map) map_;

public:
    alias FutureComponent = PositionComponent;

    /** Construct a PositionProcess.
     *
     * Params:
     *
     * gameTime = Game time for access to time step.
     * map      = Game map.
     * log      = The game log.
     */
    this(const(GameTime) gameTime, const(Map) map, Logger log) @safe pure nothrow @nogc
    {
        gameTime_ = gameTime;
        map_      = map;
        log_      = log;
    }

    /// Update position of an entity with a dynamic component.
    void process(ref const PositionComponent posPast,
                 ref const DynamicComponent dynamic,
                 out PositionComponent posFuture) nothrow
    {
        import std.math: abs;
        assert(abs(posPast.facing.magnitude_squared - 1.0) < 0.001, 
               "(past) PositionComponent.facing must be a unit vector");
        scope(exit)
        {
            assert(abs(posFuture.facing.magnitude_squared - 1.0) < 0.001, 
                   "(future) PositionComponent.facing must be a unit vector");
        }

        const timeStep = gameTime_.timeStep;
        vec3 newFacing = posPast.facing;
        // a zero rotTarget gvector means we're not rotating
        if(dynamic.rotTarget.magnitude_squared >= 0.00001)
        {
            assert(abs(dynamic.rotTarget.magnitude_squared - 1.0) < 0.001 ,
                   "rotTarget must be a unit vector");

            const rotDistanceDeg = radToDeg(angleBetweenPointsOnSphere(posPast.facing, dynamic.rotTarget));
            // How much of the rot distance can we move in the second.
            // e.g. if speed is 45degpersec and distance is 90 deg, we'll be able to cover 
            // 0.5 of the distance in a second.
            const rotRatioInSecond = dynamic.rotSpeed / rotDistanceDeg;
            // The actual rot ratio for this frame - and we don't want to move more than
            // the entire distance so we clamp to 1.0
            const rotRatio = min(1.0, rotRatioInSecond * timeStep);

            newFacing = slerp(posPast.facing, dynamic.rotTarget, rotRatio);
        }
        auto newPos = posPast + timeStep * dynamic.velocity;

        newPos = map_.bumpToSurface(newPos);
        Cell cell = void;
        if(map_.cell(cell, newPos.worldToCellCoords))
        {
            // Align rotation to cell surface.
            const normal = map_.tile(cell.tileIndex).normal;
            newFacing = newFacing.decompose(normal).component.normalized;
        }

        posFuture = PositionComponent(newPos, newFacing);
    }

    /// Keep position of an entity that has no DynamicComponent.
    mixin(preserveComponentsMixin);
}


import tharsis.entity;
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

    /// Update weapons of one entity.
    void process(ref const EntityContext context,
                 ref const PositionComponent pos,
                 ref const CommandComponent command,
                 immutable WeaponMultiComponent[] weaponsPast,
                 ref WeaponMultiComponent[] weaponsFuture) nothrow
    {
        const timeStep    = gameTime_.timeStep;
        const weaponCount = weaponsPast.length;
        weaponsFuture     = weaponsFuture[0 .. weaponCount];

        weaponsFuture[] = weaponsPast[];
        outer: foreach(w, ref weapon; weaponsFuture)
        {
            const handle = weapon.weapon;
            const state  = weaponMgr_.state(handle);
            // If the weapon is not loaded yet, load it and don't update weapon logic.
            if(state == ResourceState.New) { weaponMgr_.requestLoad(handle); }
            if(state == ResourceState.LoadFailed && !weapon.loggedLoadFailed)
            {
                import std.stdio;
                writefln("Ignoring weapon %s of entity %s as it failed to load", 
                         w, context.entity.id).assumeWontThrow;
                weapon.loggedLoadFailed = true;
            }
            if(state != ResourceState.Loaded) { continue; }

            // Only check command type after ensuring the weapons are loaded.

            // Only using final switch to ensure we don't miss any new commands.
            with(CommandComponent.Type) final switch(command.type)
            {
                case MoveTo:
                    continue outer;
                case StaticFireAt:
                    weapon.firingDirection = (command.staticFireAt - pos).normalized;
                    break;
            }

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

    /// Don't just preserve the weapons, use the opportunity to load them too.
    mixin(preserveComponentsMixin!"processWeapon");

private:
    /// Reads a WeaponMultiComponent and requests to load its weapon if not loaded/loading yet.
    void processWeapon(ref WeaponMultiComponent weapon) nothrow
    {
        const handle = weapon.weapon;
        const state  = weaponMgr_.state(handle);
        if(state == ResourceState.New) { weaponMgr_.requestLoad(handle); }
    }
}


/** Attaches spawner components to entities.
 *
 * Currently only attaches spawner components used to spawn weapon projectiles.
 */
final class SpawnerAttachProcess
{
private:
    // Game log.
    Logger log_;

    import time.gametime;
    // Game time for access to time step.
    const(GameTime) gameTime_;

    import entity.resources;
    // Weapon resource manager.
    WeaponManager weaponMgr_;

public:
    alias FutureComponent = SpawnerMultiComponent;

    /** Construct a SpawnerAttachProcess.
     *
     * Params:
     *
     * gameTime      = Game time for access to time step.
     * weaponManager = Weapon resource manager.
     * log           = The game log.
     */
    this(const(GameTime) gameTime, WeaponManager weaponManager, Logger log)
        @safe pure nothrow @nogc
    {
        gameTime_  = gameTime;
        weaponMgr_ = weaponManager;
        log_       = log;
    }

    /** Add projectile spawners to an entity that has no spawners yet.
     *
     * Also called by the 3rd process() overload to readd the projectile spawners
     * on every new frames.
     */
    void process(const WeaponMultiComponent[] weapons,
                 ref SpawnerMultiComponent[] spawners) nothrow
    {
        size_t spawnerCount = 0;
        foreach(size_t weaponIdx, ref weapon; weapons)
        {
            const handle = weapon.weapon;
            const state  = weaponMgr_.state(handle);
            if(state == ResourceState.New)    { weaponMgr_.requestLoad(handle); }
            if(state != ResourceState.Loaded) { continue; }

            foreach(ref projectileSpawner; weaponMgr_.resource(handle).projectiles)
            {
                spawners[spawnerCount] = projectileSpawner;
                // Trigger ID must correspond to the weapon so SpawnerProcess knows it
                // should spawn when the weapon fires. Without this, trigger ID of the
                // weapon would have to be set in projectile spawner components in a
                // weapon resource, which would require any entities using the weapon to
                // always have that weapon at the same index among weapon components.
                const weaponTriggerID = cast(ushort)(minWeaponTriggerID + weaponIdx);
                spawners[spawnerCount].triggerID = weaponTriggerID;
                ++spawnerCount;
            }
        }

        spawners = spawners[0 .. spawnerCount];
    }

    /** The entity has no weapon, so no need to add components; just preserve them.
     *
     * Does not preserve spawner components used to spawn weapon projectiles (in case
     * this is called after weapons are removed). Also called by the 3rd process()
     * overload to preserve non-projectile spawners.
     */
    void process(const SpawnerMultiComponent[] spawnersPast,
                 ref SpawnerMultiComponent[] spawnersFuture) nothrow
    {
        size_t count = 0;
        // Spawners spawning weapon projectiles are not carried over; if this process()
        // is called, we either have no weapon or it's called by a caller process() that
        // will add spawners for those projectiles.
        foreach(ref spawner; spawnersPast) if(spawner.triggerID < minWeaponTriggerID)
        {
            spawnersFuture[count++] = spawner;
        }
        spawnersFuture = spawnersFuture[0 .. count];
    }

    /** The entity has both weapons and spawners.
     *
     * Preserves non-weapon spawners and re-adds weapon projectile spawners for whatever
     * weapons the entity has $(D right now).
     */
    void process(const SpawnerMultiComponent[] spawnersPast,
                 const WeaponMultiComponent[] weapons,
                 ref SpawnerMultiComponent[] spawnersFuture) nothrow
    {
        alias Spawner = SpawnerMultiComponent;

        // Copy any spawner components not originated from weapons to spawnersFuture.
        Spawner[] spawnersNoWeap = spawnersFuture;
        process(spawnersPast, spawnersNoWeap);
        // Add spawner components for weapon projectiles of weapons this entity
        // currently has. If we add support for weapon changing in future, this will
        // still work correctly.
        Spawner[] spawnersWeap = spawnersFuture[spawnersNoWeap.length .. $];
        process(weapons, spawnersWeap);
        spawnersFuture = spawnersFuture[0 .. spawnersNoWeap.length + spawnersWeap.length];
    }
}

/// If a timed trigger with this ID triggers, we kill the entity.
enum killTriggerID = ushort.max;

/** Determines whether an entity should live or die in the next frame.
 */
class LifeProcess
{
public:
    alias LifeComponent FutureComponent;

    /// Looks for the "kill" triggerID and kills the entity if triggered.
    void process(ref const LifeComponent lifePast,
                 immutable TimedTriggerMultiComponent[] triggers,
                 out LifeComponent lifeFuture) nothrow
    {
        lifeFuture = lifePast;
        import std.stdio;
        // Look for the kill trigger and kill the entity if triggered.
        foreach(ref trigger; triggers)
        {
            if(trigger.triggerID == killTriggerID && trigger.timeLeft <= 0.0f) 
            {
                lifeFuture.alive = false;
                return;
            }
        }

    }

    /// If no timed triggers, just let the entity live (for now).
    void process(ref const LifeComponent lifePast, out LifeComponent lifeFuture) nothrow
    {
        lifeFuture = lifePast;
    }
}
