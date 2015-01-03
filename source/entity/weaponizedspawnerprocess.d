//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// A SpawnerProcess with support for weapons.
module entity.weaponizedspawnerprocess;

import std.exception;
import std.experimental.logger;

import gl3n_extra.linalg;
import tharsis.defaults;
import tharsis.entity;

import entity.components;
import entity.entitysystem;


/** A SpawnerProcess with support for weapons.
 *
 * Treats weapons as spawn conditions. Spawns spawner components matching a weapon when
 * $(D secsTillBurst) of that weapon is negative. SpawnerAttachProcess adds spawner
 * components to spawn projectiles of each weapon in an entity. $(D triggerID) of those
 * spawner components is entity.components.minWeaponTriggerID + index of the weapon that
 * fires the projectile. The index points to weapon (multi) components of the entity.
 */
final class WeaponizedSpawnerProcess: DefaultSpawnerProcess
{
private:
    // Game log.
    Logger log_;

    // Pointer to the currently processed weapon component.
    //
    // Only set while spawning a projectile entity, must be null otherwise.
    //
    // process() reads weapon components to determine when to spawn projectile entities.
    // When it spawns a projectile, we still need to override that projectile's direction
    // (DynamicComponent), since by default the direction will always be the same - as it
    // was loaded from YAML. We set the direction in spawnHook(), which is called by
    // parent SpawnerProcess code after the prototype of the spawned entity has been
    // constructed but still before spawning the entity.
    immutable(WeaponMultiComponent)* currentWeapon_ = null;

public:
    /** Construct a WeaponizedSpawnerProcess.
     *
     * Params:
     *
     * addEntity            = Delegate to add an entity.
     * prototypeManager     = Manages entity prototype resources.
     * componentTypeManager = The component type manager where all used component types
     *                        are registered.
     * log                  = The game log.
     *
     * Examples:
     * --------------------
     * // EntityManager entityManager
     * // ResourceManager!EntityPrototypeResource prototypeManager
     * // ComponentTypeManager componentTypeManager
     * // Logger log
     * auto spawner = new WeaponizedSpawnerProcess(&entityManager.addEntity, prototypeManager,
     *                                             componentTypeManager, log);
     * --------------------
     */
    this(DefaultSpawnerProcess.AddEntity addEntity,
         ResourceManager!EntityPrototypeResource prototypeManager,
         AbstractComponentTypeManager componentTypeManager,
         Logger log)
        @safe pure nothrow
    {
        log_ = log;
        super(addEntity, prototypeManager, componentTypeManager);
    }

    import std.typecons;

    override void spawnHook(ref EntityPrototype.GenericComponentRange!(No.isConst) components)
        @system nothrow
    {
        const zero = vec3(0, 0, 0);
        if(currentWeapon_ is null || currentWeapon_.firingDirection == zero) { return; }
        // This is called after the prototype is locked; we can't add any components.
        for(; !components.empty; components.popFront)
        {
            RawComponent* comp = &(components.front());
            if(comp.typeID != DynamicComponent.ComponentTypeID) { continue; }

            DynamicComponent* dynamic = &(comp.as!DynamicComponent());
            // Keep the same velocity, but redirect it in firing direction.
            const speed      = dynamic.velocity.length;
            dynamic.velocity = speed * currentWeapon_.firingDirection;
        }
    }

    /** A simple forward for SpawnerProcess process().
     *
     * Needed because user code doesn't see SpawnerProcess.process() for some reason,
     * probably a DMD bug (as of DMD 2.066).
     */
    override void process(ref const(EntityContext) context,
                          immutable SpawnerMultiComponent[] spawners,
                          immutable TimedTriggerMultiComponent[] triggers) nothrow
    {
        super.process(context, spawners, triggers);
    }

    /** Reads spawners and weapons.
     *
     * If a weapon fires ($(D weapon.secsTillBurst < 0)), spawns projectiles of that
     * weapon.
     */
    void process(ref const(EntityContext) context,
                 immutable SpawnerMultiComponent[] spawners,
                 immutable WeaponMultiComponent[] weapons) nothrow
    {
        // Find triggers matching this spawner component, and spawn if found.
        outer: foreach(ref spawner; spawners) foreach(size_t idx, ref weapon; weapons)
        {
            const weaponID = idx + minWeaponTriggerID;
            // Weapon trigger must match the spawner component's trigger ID.
            if(weaponID != spawner.triggerID) { continue; }

            // If the spawner is not fully loaded (any of its resources not in the
            // Loaded state), ignore it completely and move on to the next one. This
            // means we miss spawns when a spawner is not loaded. We may add 'delayed'
            // spawns to compensate for this in future.
            if(!spawnerReady(spawner)) { continue outer; }

            // We've not reached the time to spawn yet.
            if(weapon.secsTillBurst <= 0.0f)
            {
                currentWeapon_ = &weapon;
                spawn(context, spawner);
                currentWeapon_ = null;
            }
        }
    }

    /// Process an entity with both weapons and timed triggers.
    void process(ref const(EntityContext) context,
                 immutable SpawnerMultiComponent[] spawners,
                 immutable WeaponMultiComponent[] weapons,
                 immutable TimedTriggerMultiComponent[] triggers) nothrow
    {
        // Delegate to process() overloads handling individual triggers
        // (weapons, timed triggers ATM).
        process(context, spawners, weapons);
        process(context, spawners, triggers);
    }
}
