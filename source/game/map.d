//          Copyright Ferdinand Majerech 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Game map.
module game.map;


import std.experimental.logger;
import std.container.array;
import std.exception: assumeWontThrow;
import std.stdio;

import game.mapinternals;
import gl3n_extra.color;
import gl3n_extra.linalg;



/*
 * On cliff cells:
 *
 * If a cell borders another cell on a different layer without a slope,
 * that border is impassable, so it is automatically a 'cliff'. But
 * the cell needs visual cliff representation to look like a cliff.
 *
 * So TODO cliff cell graphics!
 */

/// Vertex type used in map (tile) drawing.
struct MapVertex
{
    /// 3D vertex position.
    vec3 position;
    /// RGBA vertex color.
    Color color;
}

/** One cell (3D 'cube') of the map.
 *
 * A cell represents a 'filled' volume; its base is a diamond-shaped at the bottom
 * of the layer the cell is in, while its ceiling (surface that can be walked on)
 * can have varying heights (defined by Tile) at each corner of the diamond,
 * allowing to represent slopes.
 *
 * All data members shared by cells, *which may not change without changing the tile*,
 * should be in `struct Tile`. Data that may change over the cell's lifetime
 * without changing the tile (e.g. values that change gradually over time -
 * where we can't have a separate tile for every possible value), should be
 * in `Cell`.
 */
struct Cell
{
    /// Index of the tile used by this cell.
    uint tileIndex = uint.max;
}


/// Directions on the map, used to identify neighboring cells.
enum Direction: ubyte
{
    N = 0,
    E = 1,
    S = 2,
    W = 3,
    NE = 4,
    SE = 5,
    SW = 6,
    NW = 7
}
import std.typetuple;
/// Diagonal directions.
alias diagonalDirections = 
    TypeTuple!(Direction.NE, Direction.SE, Direction.SW, Direction.NW);

/// Does the given direction have an 'N' part? (N, NE and NW).
int hasN(Direction dir) @safe pure nothrow @nogc 
{
    with(Direction) { return dir == N || dir == NE || dir == NW; }
}

/// Does the given direction have an 'E' part? (E, NE and SE).
int hasE(Direction dir) @safe pure nothrow @nogc 
{
    with(Direction) { return dir == E || dir == NE || dir == SE; }
}

/// Does the given direction have an 'S' part? (S, SE and SW).
int hasS(Direction dir) @safe pure nothrow @nogc 
{
    with(Direction) { return dir == S || dir == SE || dir == SW; }
}

/// Does the given direction have an 'W' part? (W, NW and SW).
int hasW(Direction dir) @safe pure nothrow @nogc 
{
    with(Direction) { return dir == W || dir == NW || dir == SW; }
}

import std.typecons: Tuple, tuple;
/** Get the 'partial directions' of a diagonal direction, e.g. N and W for NW.
 *
 * Params:
 *
 * dir = Direction to get parts of. Must be NE, SE, SW or NW.
 */
Tuple!(Direction, Direction) partDirs(Direction dir) @safe pure nothrow @nogc 
{
    switch(dir) with(Direction)
    {
        case NE: return tuple(N, E);
        case SE: return tuple(S, E);
        case SW: return tuple(S, W);
        case NW: return tuple(N, W);
        default: assert(false, "Trying to get parts of a non-diagonal direction");
    }
}

/** A tile.
 *
 * Tiles are referred to cells; a tile specifies the shape and graphics of
 * all cells referring to the tile.
 */
struct Tile
{
    union
    {
        struct 
        {
            /// Height of the cell surface at its northern corner.
            ushort heightN;
            /// Height of the cell surface at its eastern corner.
            ushort heightE;
            /// Height of the cell surface at its southern corner.
            ushort heightS;
            /// Height of the cell surface at its western corner.
            ushort heightW;
        }
        ushort[4] heights;
    }

    // TODO: std.allocator 2015-07-11
    /** Vertices of the tile's graphics representation that will be drawn as lines.
     *
     * Vertices 0 and 1 will form the first line, vertices 2 and 3 the second line, etc.
     */
    const(MapVertex)[] lineVertices;
    /** Vertices of the tile's graphics representation that will be drawn as triangles.
     *
     * Vertices 0, 1 and 2 will form the first triangle, vertices 3, 4 and 5 the second
     * triangle, etc.
     */
    const(MapVertex)[] triangleVertices;

    /** Tile constructor.
     *
     * Params:
     *
     * heightN          = Height of the tile at its northern corner.
     * heightE          = Height of the tile at its eastern corner.
     * heightS          = Height of the tile at its southern corner.
     * heightW          = Height of the tile at its western corner.
     * lineVertices     = Vertices to draw as lines when drawing the tile.
     * triangleVertices = Vertices to draw as triangles when drawing the tile.
     */
    this(ushort heightN, ushort heightE, ushort heightS, ushort heightW,
         const(MapVertex)[] lineVertices, const(MapVertex)[] triangleVertices) @safe pure nothrow @nogc
    {
        this.heightN = heightN;
        this.heightE = heightE;
        this.heightS = heightS;
        this.heightW = heightW;
        this.lineVertices     = lineVertices;
        this.triangleVertices = triangleVertices;
    }
}

/** Stores all tiles.
 *
 * Part of `Map` API through `alias this`.
 */
class TileStorage
{
private:
    /** The set (or array, rather) of all tiles.
     *
     * Cells refer to tiles in this array by indices.
     */
    Array!Tile allTiles_;

public:
    /** Get a non-const reference to the tile array - to e.g. add new tiles.
     *
     * Note:
     *
     * *removing* any tiles is **unsafe** once any cells exist; if tiles
     * are moved to different indices the cells will refer to different tiles;
     * or even outside of the array.
     */
    ref Array!Tile editTileSet() @safe pure nothrow
    {
        return allTiles_;
    }

    /// Get a read-only range of all tiles.
    auto allTiles() @trusted nothrow const
    {
        return allTiles_[].assumeWontThrow;
    }

    /// Get tile at specified index.
    const(Tile) tile(uint idx) @trusted pure nothrow const @nogc
    {
        static const(Tile) impl(const(TileStorage) self, uint idx) @safe pure nothrow
        {
            return self.allTiles_[idx];
        }
        return (cast(const(Tile) function(const(TileStorage), uint)
                    @safe pure nothrow @nogc)&impl)(this, idx);
    }
}

/** Game map.
 *
 *
 * The map has multiple layers, enabling e.g. bridges or multi-level structures.
 *
 * ----------
 * Map layout
 * ----------
 *
 * Cell layout is *staggered* like in C&C TS/RA2. This means diamond cells form
 * a rectangular (not diamond) map. Each cell row is horizontal (east-ward) in screen
 * space (with x-y direction of (1,1), that is, the consecutive cells are placed by
 * equally increasing both the X and Y coordinates).
 * The rows are staggered and spaced vertically by *half* of cell size. This means
 * that  e.g. a 64x64 map is actually a rectangle with width 2x its height (and
 * visually it's even more more elongated due to the isometric camera). A
 * 64x128 map would be square in the game world.
 *
 */
class Map
{
private:
    /// Stores map cells in layers.
    CellState cells_;

    /// Number of cells in each row.
    size_t width_;
    /// Number of cell rows in each layer.
    size_t height_;
    /// Number of layers in the map.
    size_t layers_;

    //TODO std.allocator 2015-07-06
    import std.container.array;
    /// Cell commands to be executed on the next call to `applyCommands()`.
    Array!MapCommand commands_;

    /// The game log.
    Logger log_;

public:
    // TODO: private once the alias this vs private issue is fixed 2015-07-15
    // Tile storage and management.
    TileStorage tileStorage_;

    alias tileStorage_ this;

    /** Create a map with specified size
     *
     * Params:
     *
     * log    = Game log.
     * width  = Number of cells in each row of the map.
     * height = Number of rows in each layer of the map.
     * layers = Number of layers in the map.
     */
    this(Logger log, size_t width, size_t height, size_t layers) @safe pure nothrow
    {
        assert(width < ushort.max, "Map width can't be >65535 cells");
        assert(height < ushort.max, "Map height can't be >65535 cells");
        tileStorage_ = new TileStorage();
        cells_       = new CellState(width, height, layers, tileStorage_, log);
        log_    = log;
        width_  = width;
        height_ = height;
        layers_ = layers;
    }

    /// Destroy the map, deallocating used memory.
    ~this()
    {
        destroy(cells_);
        destroy(tileStorage_);
    }

    /// Width (number of columns) of the map.
    size_t width() @safe pure nothrow const @nogc { return width_; }
    /// Height (number of rows) of the map.
    size_t height() @safe pure nothrow const @nogc { return height_; }
    /// Depth (number of layers) of the map.
    size_t layers() @safe pure nothrow const @nogc { return layers_; }

    /** Get a range (`InputRange`) of all cells (in all rows/columns/layers) in the map.
     *
     * Range elements are `Cell` struct with the following additional members
     * (added through `alias this`):
     *
     * ```
     * size_t layer  // index of the layer the cell is on in the map
     * size_t row    // index of the row the cell is in in the map
     * size_t column // index of the column the cell is in in the row
     * ```
     */
    auto allCells() @safe pure nothrow const //@nogc
    {
        return cells_.allCells;
    }

    /** Get a range (`InputRange`) of cells in an interval of rows/layers/columns.
     *
     * See_Also: `allCells`
     *
     * Params:
     *
     * min = Minimum row (x), column (y) and layer (z), inclusive.
     * max = Maximum row (x), column (y) and layer (z), exclusive.
     *       Can be greater than map bounds (uint.max will always iterate
     *       to the last row/column/layer).
     *
     * Example:
     * --------------------
     * // Map map;
     *
     * // This will iterate over any cells in columns
     * // 1,2,3 and 4 that are in row 2 and in layers 0 and 1.
     * foreach(cell; Map.cellRange(vec3(1, 2, 0), vec3(5, 3, 2)))
     * {
     *     // do something
     * }
     * --------------------
     */
    auto cellRange(vec3u min, vec3u max) @safe pure nothrow const //@nogc
    {
        return cells_.cellRange(min, max);
    }

    /** Raise terrain at specified coordinates.
     *
     * Replaces cell at specified coordinates with a cell on a higher layer; then
     * connects to cells around the new cell and creates a foundation for the
     * cell (a 'hill') if needed.
     *
     * If no cell is found at specified coordinates, or if `layer` is already
     * the top layer, does nothing.
     *
     * Params:
     *
     * column = Column of the cell to raise.
     * row    = Row of the cell to raise.
     * layer  = Layer of the cell to raise.
     */
    void commandRaiseTerrain(uint column, uint row, uint layer)
        @trusted nothrow
    {
        assert(column < width_, "cell column out of range");
        assert(row    < height_, "cell row out of range");
        assert(layer  < layers_, "cell layer out of range");
        // Can't raise terrain that is already at the top layer
        if(layer >= layers_ - 1)
        {
            return;
        }

        commands_.insert(MapCommand(MapCommand.Type.RaiseTerrain, column, row, layer))
                 .assumeWontThrow;
    }

    /** Add a cell command to set cell at specified coordinates.
     *
     * `applyCommands` must be called to apply this command.
     *
     * Note:
     *
     * Cell commands are not synchronized, and can **only** be called from **one**
     * thread.
     *
     * Params:
     *
     * column = Column of the cell to set.
     * row    = Row of the cell to set.
     * layer  = Layer of the cell to set.
     * cell   = Cell data to set.
     */
    void commandSet(uint column, uint row, uint layer, Cell cell)
        @trusted nothrow
    {
        assert(column < width_, "cell column out of range");
        assert(row < height_, "cell row out of range");
        assert(layer < layers_, "cell layer out of range");
        commands_.insert(MapCommand(MapCommand.Type.SetCell, column, row, layer, cell))
                 .assumeWontThrow;
    }

    void commandSet(vec3u coords, Cell cell) @safe nothrow
    {
        commandSet(coords.x, coords.y, coords.z, cell);
    }

    /** Add a cell command to delete cell at specified coordinates. Will do nothing if
     * ther is no cell.
     *
     * `applyCommands` must be called to apply this command.
     *
     * Note:
     *
     * Cell commands are not synchronized, and can **only** be called from **one**
     * thread.
     *
     * Params:
     *
     * column = Column of the cell to set.
     * row    = Row of the cell to set.
     * layer  = Layer of the cell to set.
     */
    void commandClear(uint column, uint row, uint layer)
        @trusted nothrow
    {
        assert(column < width_, "cell column out of range");
        assert(row < height_, "cell row out of range");
        assert(layer < layers_, "cell layer out of range");
        commands_.insert(MapCommand(MapCommand.Type.ClearCell, column, row, layer))
                 .assumeWontThrow;
    }

    void commandClear(vec3u coords) @safe nothrow
    {
        commandClear(coords.x, coords.y, coords.z);
    }

    /** Apply (and delete) all queued cell commands.
     *
     * Can be called e.g. between game updates.
     *
     * Note:
     *
     * This code is not synchronized; make sure no cell commands are being called from
     * another thread.
     */
    void applyCommands()
        @trusted nothrow
    {
        ()
        {

        foreach(ref command; commands_)
        {
            cells_.command(command);
        }

        // make sure commands_ doesn't waste too much memory if there was a lot of
        // commands last frame.
        enum maxReservedCommands = 4096;
        commands_.clear();
        if(commands_.capacity > maxReservedCommands)
        {
            destroy(commands_);
            commands_.reserve(maxReservedCommands);
        }

        }().assumeWontThrow;
    }
}


/// Size of a map cell in world space.
enum cellSizeWorld  = vec3i(256, 256, 128);

/// Get (column/row/layer) coordinates of cell containing specified world space coords.
vec3i worldToCellCoords(vec3 world) @safe pure nothrow @nogc 
{
    import tharsis.util.math;
    assert(floor!int(-64.0 / 128.0) == -1);

    // Cell coords as they would be on a 'diamond' (square from isometric view) map
    // like e.g. Age of Empires.
    const diamondCoords = 
        vec3i(floor!int(world.x / cellSizeWorld.x),
              floor!int(world.y / cellSizeWorld.y),
              floor!int(world.z / cellSizeWorld.z));
    // X adds -X rows and X/2 columns
    // Y adds Y rows and Y/2 columns
    // Convert diamond coords to our staggered coords.
    return vec3i((diamondCoords.x + diamondCoords.y) / 2,
                 diamondCoords.y - diamondCoords.x,
                 diamondCoords.z);
}

/// Get world space coordinates of the eastern corner of cell with specified coordinates.
vec3 cellToWorldCoords(vec3i cell) @safe pure nothrow @nogc 
{
    // columns add cols diagonal Y and cols diagonal X
    // rows add (rows + 1) / 2 diagonal Y and -(rows/2) diagonal X
    const diamondCoords = vec3(cell.x - cell.y / 2, cell.x + (cell.y + 1) / 2, cell.z);
    return vec3(diamondCoords.x * cellSizeWorld.x,
                diamondCoords.y * cellSizeWorld.y,
                diamondCoords.z * cellSizeWorld.z);
}

unittest
{
    writeln("cellToWorldCoords()/worldToCellCoords() unittest");
    scope(success) { writeln("cellToWorldCoords()/worldToCellCoords() unittest SUCCESS"); }
    scope(failure) { writeln("cellToWorldCoords()/worldToCellCoords() unittest FAILURE"); }

    foreach(coords; [vec3i(0, 0, 0), vec3i(9, 0, 0), vec3i(0, 9, 0), vec3i(0, 0, 9),
                     vec3i(5, 9, 0), vec3i(9, 5, 0), vec3i(21, 34, 43)])
    {
        assert(coords.cellToWorldCoords.worldToCellCoords == coords,
               "cellToWorldCoords() must be an inverse of worldToCellCoords()");
    }
}


/** Generate a plain map for testing.
 *
 * Takes a Map and generates cells in it. Best used with an empty, newly constructed
 * map.
 *
 *
 * The generated cells will fill one layer, with colors changing based on rows/columns,
 * and also add a few cells on a higher layer (1 cell for every 4 rows and 4 columns).
 */
void generatePlainMap(Map map)
    @trusted nothrow
{
    const white  = rgb!"FFFFFF";
    const bluish = rgb!"B0B0F0";
    const xMax = cellSizeWorld.x;
    const yMax = cellSizeWorld.y;

    Tile generateTile(uint hN, uint hE, uint hS, uint hW)
    {
        const white  = rgb!"FFFFFF";
        const bluish = rgb!"B0B0F0";
        const xMax = cellSizeWorld.x;
        const yMax = cellSizeWorld.y;

        // TODO: These arrays will be allocated with Map's own Allocator instance
        // 2015-07-11
        return Tile(cast(ushort)hN, cast(ushort)hE, cast(ushort)hS, cast(ushort)hW,
                    [MapVertex(vec3(0,    0,    hW), white),
                     MapVertex(vec3(0,    yMax, hN), white),
                     MapVertex(vec3(xMax, 0,    hS), white),
                     MapVertex(vec3(xMax, yMax, hE), white),
                     MapVertex(vec3(0,    0,    hW), white),
                     MapVertex(vec3(xMax, 0,    hS), white),
                     MapVertex(vec3(0,    yMax, hN), white),
                     MapVertex(vec3(xMax, yMax, hE), white)],
                    [MapVertex(vec3(0,    0,    hW), bluish),
                     MapVertex(vec3(xMax, 0,    hS), bluish),
                     MapVertex(vec3(0,    yMax, hN), bluish),
                     MapVertex(vec3(0,    yMax, hN), bluish),
                     MapVertex(vec3(xMax, 0,    hS), bluish),
                     MapVertex(vec3(xMax, yMax, hE), bluish)]);
    }


    // flat
    map.editTileSet.insert(generateTile(0,   0,   0,   0  )).assumeWontThrow;
    const flatTileIdx = 0;
    // NW/NE/SE/SW slopes
    map.editTileSet.insert(generateTile(0,   128, 128, 0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   0,   128, 128)).assumeWontThrow;
    map.editTileSet.insert(generateTile(128, 0,   0,   128)).assumeWontThrow;
    map.editTileSet.insert(generateTile(128, 128,   0,   0)).assumeWontThrow;
    // N/E/S/W slopes (both the 'top' and 'bottom' versions)
    map.editTileSet.insert(generateTile(0,   0,   128, 0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   128, 128, 128)).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   0,   0,   128)).assumeWontThrow;
    map.editTileSet.insert(generateTile(128, 0,   128, 128)).assumeWontThrow;
    map.editTileSet.insert(generateTile(128, 0,   0,   0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(128, 128, 0,   128)).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   128, 0,   0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(128, 128, 128, 0  )).assumeWontThrow;
    // "Tents" with opposing corners raised
    map.editTileSet.insert(generateTile(128, 0,   128, 0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   128, 0,   128)).assumeWontThrow;


    foreach(uint x; 0 .. cast(uint)map.width_)
    {
        foreach(uint y; 0 .. cast(uint)map.height_)
        {
            // const ubyte red = cast(ubyte)((cast(float)x / map.width_) * 255.0);
            // const ubyte green = cast(ubyte)((cast(float)y / map.height_) * 255.0);
            // const ubyte blue = 255;
            // const ubyte alpha = 255;
            map.commandSet(x, y, 0, Cell(flatTileIdx));
            // Just to have some layering
            if((x % 16 == 0) && (y % 16 == 0))
            {
                map.commandSet(x, y, 1, Cell(flatTileIdx));
            }
        }
        map.applyCommands();
    }
}
unittest
{
    import std.stdio;
    writeln("Map/generatePlainMap() unittest");
    scope(success) { writeln("Map/generatePlainMap() unittest SUCCESS"); }
    scope(failure) { writeln("Map/generatePlainMap() unittest FAILURE"); }
    auto map = new Map(null, 256, 256, 32);
    generatePlainMap(map);
}
