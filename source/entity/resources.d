//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Resources used by the game and their resource managers.
module entity.resources;

import tharsis.defaults;
import tharsis.entity;
import tharsis.util.interfaces;
import tharsis.util.mallocarray;
import tharsis.util.pagedarray;
import tharsis.util.qualifierhacks;
import tharsis.util.typecons;


/// Data describing a weapon.
struct Weapon 
{
    /// Maximum number of projectiles a weapon can spawn in a single burst.
    enum maxProjectiles = 128;

    /// Time between successive bursts of projectiles.
    float burstPeriod;

    /// Spawner components to spawn projectiles in a burst.
    SpawnerMultiComponent[] projectiles;
}

/// Weapon resource managed by WeaponManager. Embeds a Weapon.
alias WeaponResource = DefaultResource!Weapon;


/// Resource manager managing weapons.
final class WeaponManager: MallocResourceManager!WeaponResource
{
private:
    // Memory used by loaded (immutable) weapons in resources_ to store projectile
    // spawner components.
    PartiallyMutablePagedBuffer projectileData_;

    // Loader to load weapons from YAML.
    YAMLSource.Loader yamlLoader_;

    // Component type manager to load spawner components - weapon projectiles - with.
    AbstractComponentTypeManager compTypeMgr_;

    // Entity manager for access to resource management.
    DefaultEntityManager entityMgr_;

public:
    /** WeaponManager constructor.
     *
     * Params: entityManager        = Entity manager for access to resource management.
     *         loader               = Loader to load weapons from YAML.
     *         componentTypeManager = Component type manager to load spawner
     *                                components - weapon projectiles - with.
     */
    this(DefaultEntityManager entityManager, YAMLSource.Loader yamlLoader,
         AbstractComponentTypeManager componentTypeManager)
        @trusted nothrow
    {
        yamlLoader_  = yamlLoader;
        compTypeMgr_ = componentTypeManager;
        entityMgr_   = entityManager;

        /** Load a weapon resource.
         *
         * Params: resource = Resource to load. State of the resource will be set to
         *                    Loaded if loaded successfully, LoadFailed otherwise.
         *         errorLog = A string to write any loading errors to. If there are no
         *                    errors, this is not touched.
         */
        void loadResource(ref WeaponResource resource, void delegate(string) nothrow logError)
            @trusted nothrow
        {
            YAMLSource source = resource.descriptor.source(yamlLoader_);
            if(source.isNull)
            {
                resource.state = ResourceState.LoadFailed;
                return;
            }

            alias Projectile = typeof(resource.projectiles[0]);
            const maxProjectileBytes = WeaponResource.maxProjectiles * Projectile.sizeof;
            ubyte[] storage = projectileData_.getBytesExactly(maxProjectileBytes);

            scope(exit)
            {
                import std.algorithm;
                assert([ResourceState.Loaded, ResourceState.LoadFailed].canFind(resource.state),
                       "Unexpected weapon resource state after loading");

                const loaded = resource.state == ResourceState.Loaded;
                const usedBytes = (cast(ubyte[])resource.projectiles).length;
                projectileData_.lockBytes(storage[0 .. loaded ? usedBytes : 0]);
            }

            void log(string s) nothrow { logError("While loading a weapon: " ~ s); }

            // Loading fails unless it succeeds.
            resource.state = ResourceState.LoadFailed;
            YAMLSource burstPeriodSrc;
            // Get the burstPeriodSrc subnode.
            if(!source.getMappingValue("burstPeriod", burstPeriodSrc))
            {
                log("couldn't find 'burstPeriod'\n" ~ source.errorLog);
                return;
            }
            // Read the value stored in burstPeriodSrc to burstPeriod.
            if(!burstPeriodSrc.readTo(resource.burstPeriod))
            {
                log("'burstPeriod' had unexpected type\n" ~ burstPeriodSrc.errorLog);
                return;
            }

            YAMLSource allProjectilesSrc;
            if(!source.getMappingValue("projectiles", allProjectilesSrc))
            {
                log("couldn't find 'projectiles'\n" ~ source.errorLog);
                return;
            }
            if(!allProjectilesSrc.isSequence)
            {
                log("'projectiles' must be a sequence\n");
                return;
            }

            YAMLSource projSrc;
            resource.projectiles = cast(Projectile[])storage;
            size_t count;

            foreach(ref YAMLSource projSrc; allProjectilesSrc)
            {
                if(count >= WeaponResource.maxProjectiles)
                {
                    log("too many projectiles");
                    return;
                }

                enum spawnerID = SpawnerMultiComponent.ComponentTypeID;

                const ComponentTypeInfo[] typeInfo   = compTypeMgr_.componentTypeInfo;
                const ComponentTypeInfo* spawnerInfo = &(typeInfo[spawnerID]);
                auto projectileBytes = cast(ubyte[])resource.projectiles[count .. count + 1];
                spawnerInfo.loadComponent(projectileBytes, projSrc, entityMgr_, logError);

                ++count;
            }
            resource.projectiles = resource.projectiles[0 .. count];

            resource.state = ResourceState.Loaded;
        }

        super(&loadResource);
    }

    /// Deallocate all resource arrays.
    override void clear() @trusted
    {
        super.clear();
        destroy(projectileData_);
    }
}
