//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Components used by entities in the game.
module entity.components;

import tharsis.entity.componenttypeinfo;


/// Component storing the position (and only the position) of an entity.
struct PositionComponent
{
    // TODO: (PREREQ: NONE) 2014-08-10
    // vec3 (need to make it work with Tharsis - probably need custom
    // construction in D:YAML) - somehow add that constructor in defaults so it's
    // reusable by users of tharsis-full
    /// X/Y/Z coordinates of the entity.
    @("relative") float x;
    @("relative") float y;
    @("relative") float z;

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Pretty much everything has a position.
    enum minPreallocPerEntity = 1.0;

    enum ushort ComponentTypeID = userComponentTypeID!1;
}

/// Temporary visual component, specifying the color of an entity.
struct VisualComponent
{
    /// R/G/B/A color channels.
    ubyte r, g, b, a;

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Most stuff has some kind of visuals.
    enum minPreallocPerEntity = 0.8;

    enum ushort ComponentTypeID = userComponentTypeID!2;
}


/// Added to entities that are picked by the mouse (clicked or hovered over).
struct PickingComponent
{
    /// Picking 'state'; is the entity picked or just hovered over by the mouse?
    enum State: ubyte
    {
        MouseOver,
        Picked
    }

    /// Picking 'state'.
    State state;

    import gl3n_extra.box;
    /** Area picked by the mouse on the screen.
     *
     * If the mouse is dragged, this is a rectangle, otherwise it's a single point.
     */
    box2i box;

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// We usually don't pick many entities.
    enum minPreallocPerEntity = 0.1;

    enum ushort ComponentTypeID = userComponentTypeID!3;
}


/// Added to entities that are selected.
struct SelectionComponent
{
    // Empty for now.

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// We usually don't select many entities.
    enum minPreallocPerEntity = 0.1;

    enum ushort ComponentTypeID = userComponentTypeID!4;
}


/** Added to entities to give them a command to execute
 *
 * This is for simple, low-level commands an entity may receive, such as 'move to',
 * 'attack', etc.
 */
struct CommandComponent
{
    /// Command type.
    enum Type
    {
        // Move to coordinates.
        MoveTo
    }

    /// Command type.
    Type type;

    union
    {
        import gl3n_extra.linalg;
        /// Coordinates to move to if type == Type.MoveTo
        vec3 moveTo;
    }


    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Not that many entities receive commands.
    enum minPreallocPerEntity = 0.1;

    enum ushort ComponentTypeID = userComponentTypeID!5;
}


/// Accelerates and decelerates entities.
struct EngineComponent
{
    /// Acceleration of the engine.
    float acceleration;
    /// Max speed the entity can be accelerated to by this engine (in any direction).
    float maxSpeed;

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Quite a few entities have engines.
    enum minPreallocPerEntity = 0.5;

    enum ushort ComponentTypeID = userComponentTypeID!6;
}


/// Represents physical movement of an entity (for now just its velocity).
struct DynamicComponent
{
    // XXX really need vec3 support in Source...
    /// Velocity of the entity.
    @("relative") float velocityX;
    /// Ditto.
    @("relative") float velocityY;
    /// Ditto.
    @("relative") float velocityZ;


    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Most entities are capable of movement.
    enum minPreallocPerEntity = 0.7;

    enum ushort ComponentTypeID = userComponentTypeID!7;
}


import tharsis.defaults.components;
/** Minimum spawner triggerID for weapons.
 *
 * Any spawner components with a triggerID greater or equal to this are considered to
 * be projectile. There is one trigger ID per weapon (we could use 32 instead of 1024,
 * we're only using so much to have room for more weapons if ever needed).
 *
 * WeaponizedSpawnerProcess removes any spawner components with weapon trigger IDs 
 * matching weapons not in the entity (e.g. after a weapon is removed (should weapon
 * removing be added in future)).
 */
enum minWeaponTriggerID = SpawnerMultiComponent.triggerID.max - 1024;

/// Represents a single weapon of an entity.
struct WeaponMultiComponent
{
    import tharsis.entity.resourcemanager;
    import entity.resources;

    /// Handle to the resource storing the weapon itself.
    ResourceHandle!WeaponResource weapon;

    /// Time until next weapon burst. If lower than 0, it's time to fire/spawn the projectiles.
    float secsTillBurst = 0.0f;

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Most entities have 1 weapon. Some have 0, some have 2, very few have more.
    enum minPreallocPerEntity = 1.0;

    /// No more than 32 WeaponMultiComponents per entity.
    enum maxComponentsPerEntity = 32;

    enum ushort ComponentTypeID = userComponentTypeID!8;
}
