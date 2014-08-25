//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Resources used by the game and their resource managers.
module entity.resources;

import tharsis.entity.descriptors;
import tharsis.entity.resourcemanager;
import tharsis.util.interfaces;
import tharsis.util.mallocarray;
import tharsis.util.pagedarray;
import tharsis.util.qualifierhacks;
import tharsis.util.typecons;


/// Resource representing a weapon
struct WeaponResource
{
    alias Descriptor = DefaultDescriptor!WeaponResource;

    /// Maximum number of projectiles a weapon can spawn in a single burst.
    enum maxProjectiles = 128;

    /// No default construction.
    @disable this();

    /// Construct a new (not loaded) WeaponResource with specified descriptor.
    this(ref Descriptor descriptor) @safe pure nothrow @nogc
    {
        this.descriptor = descriptor;
    }

    // Data can be public as we use this through immutable.

    /// Time between successive bursts of projectiles.
    float burstPeriod;

    import tharsis.defaults.components;
    /// Spawner components to spawn projectiles in a burst.
    SpawnerMultiComponent[] projectiles;

    /// Descriptor of the weapon (file name or YAMLSource).
    Descriptor descriptor;

    /// Current state of the resource,
    ResourceState state = ResourceState.New;
}


/// Resource manager managing weapons.
final class WeaponManager: MallocResourceManager!WeaponResource
{
private:
    // Memory used by loaded (immutable) weapons in resources_ to store projectile
    // spawner components.
    PartiallyMutablePagedBuffer projectileData_;

    import tharsis.defaults.yamlsource;
    // Loader to load weapons from YAML.
    YAMLSource.Loader yamlLoader_;

    import tharsis.entity.componenttypemanager;
    // Component type manager to load spawner components - weapon projectiles - with.
    AbstractComponentTypeManager compTypeMgr_;

    import tharsis.entity.entitymanager;
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
        void loadResource(ref WeaponResource resource, ref string errorLog) @trusted nothrow
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

            // Loading fails unless it succeeds.
            resource.state = ResourceState.LoadFailed;
            YAMLSource burstPeriodSrc;
            if(!source.getMappingValue("burstPeriod", burstPeriodSrc))
            {
                errorLog_ ~= "While loading a weapon, couldn't find 'burstPeriod'\n"
                            ~ source.errorLog;
                return;
            }
            if(!burstPeriodSrc.readTo(resource.burstPeriod))
            {
                errorLog_ ~= "While loading a weapon, 'burstPeriod' had unexpected type\n"
                            ~ burstPeriodSrc.errorLog;
                return;
            }

            YAMLSource allProjectilesSrc;
            if(!source.getMappingValue("projectiles", allProjectilesSrc))
            {
                errorLog_ ~= "While loading a weapon, couldn't find 'projectiles'\n"
                            ~ source.errorLog;
                return;
            }

            YAMLSource projSrc;
            resource.projectiles = cast(Projectile[])storage;
            size_t count;
            for(; allProjectilesSrc.getSequenceValue(count, projSrc); ++count)
            {
                if(count >= WeaponResource.maxProjectiles)
                {
                    errorLog_ ~= "While loading a weapon: too many projectiles";
                    return;
                }

                import tharsis.defaults.components;
                enum spawnerID = SpawnerMultiComponent.ComponentTypeID;

                import tharsis.entity.componenttypeinfo;
                const ComponentTypeInfo[] typeInfo   = compTypeMgr_.componentTypeInfo;
                const ComponentTypeInfo* spawnerInfo = &(typeInfo[spawnerID]);
                auto projectileBytes = cast(ubyte[])resource.projectiles[count .. count + 1];
                spawnerInfo.loadComponent(projectileBytes, projSrc, entityMgr_, errorLog_);
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
