//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Components used by entities in the game.
module entity.components;

import tharsis.entity.componenttypeinfo;

import gl3n_extra.linalg;



/// Component storing the position (and only the position) of an entity.
struct PositionComponent
{
    /// X/Y/Z coordinates of the entity.
    @("relative") vec3 coords = vec3(0, 0, 0);

    alias coords this;

    // No user-specified prealloc here, to ensure it's tested

    enum ushort ComponentTypeID = userComponentTypeID!1;
}

/// Temporary visual component, specifying the color of an entity.
struct VisualComponent
{
    import gl3n_extra.color;
    /// RGBA color.
    vec4ub color = rgba!"FFFFFFFF";

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
 * This is for simple, mid-level commands an entity may receive, such as 'move to',
 * 'attack', etc.
 */
struct CommandComponent
{
    /// Command type.
    enum Type
    {
        // Move to coordinates.
        MoveTo,
        // TODO: This will be used for static artillery, turrets, and will eventually
        //       include firing at moving targets. 2014-08-26
        // Fire at a target without moving towards to it.
        StaticFireAt
    }

    /// Command type.
    Type type;

    union
    {
        import gl3n_extra.linalg;
        /// Coordinates to move to if type == Type.MoveTo
        vec3 moveTo;
        /// Coordinates to fire at if type == Type.StaticFireAt
        vec3 staticFireAt;
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
    float acceleration = 0.0f;
    /// Max speed the entity can be accelerated to by this engine (in any direction).
    float maxSpeed = 0.0f;

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Quite a few entities have engines.
    enum minPreallocPerEntity = 0.5;

    enum ushort ComponentTypeID = userComponentTypeID!6;
}


/// Represents physical movement of an entity (for now just its velocity).
struct DynamicComponent
{
    /// Velocity of the entity.
    @("relative") vec3 velocity = vec3(0, 0, 0);


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

    /** True if the weapon has failed to load and we've already logged *this* individual
     * weapon component.
     *
     * See WeaponProcess.
     */
    bool loggedLoadFailed = false;

    /// Time until next weapon burst. If lower than 0, it's time to fire/spawn the projectiles.
    float secsTillBurst = 0.0f;

    import gl3n_extra.linalg;
    /** Direction the weapon is firing in. 
     *
     * Zero vector means 'default', i.e. the DynamicComponent of the projectile specified
     * in the weapon will be used without changing the direction.
     */
    vec3 firingDirection = vec3(0.0f, 0.0f, 0.0f);

    /// Small for testing. Will increase.
    enum minPrealloc = 64;

    /// Many entities have no or 1 weapon. A few have 2, very few have more.
    enum minPreallocPerEntity = 0.5;

    /// No more than 32 WeaponMultiComponents per entity.
    enum maxComponentsPerEntity = 32;

    enum ushort ComponentTypeID = userComponentTypeID!8;
}
