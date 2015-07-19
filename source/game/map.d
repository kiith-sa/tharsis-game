//      Copyright Ferdinand Majerech 2015.

// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Implementation of maps and cells.
module game.map;


import core.memory;
import std.algorithm;
import std.experimental.logger;
import std.container.array;
import std.exception: assumeWontThrow;

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
enum cellSizeWorld  = vec3d(67.882251, 67.882251, 33.9411255);

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
        //XXX try to replace cellSizeWorld with cellSizeDiscrete completely
        const zMult = cellSizeWorld.z / cellSizeDiscrete.z;

        // TODO: These arrays will be allocated with Map's own Allocator instance
        // 2015-07-11
        return Tile(cast(ushort)hN, cast(ushort)hE, cast(ushort)hS, cast(ushort)hW,
                    [MapVertex(vec3(0,    0,    hW * zMult), white),
                     MapVertex(vec3(0,    yMax, hN * zMult), white),
                     MapVertex(vec3(xMax, 0,    hS * zMult), white),
                     MapVertex(vec3(xMax, yMax, hE * zMult), white),
                     MapVertex(vec3(0,    0,    hW * zMult), white),
                     MapVertex(vec3(xMax, 0,    hS * zMult), white),
                     MapVertex(vec3(0,    yMax, hN * zMult), white),
                     MapVertex(vec3(xMax, yMax, hE * zMult), white)],
                    [MapVertex(vec3(0,    0,    hW * zMult), bluish),
                     MapVertex(vec3(xMax, 0,    hS * zMult), bluish),
                     MapVertex(vec3(0,    yMax, hN * zMult), bluish),
                     MapVertex(vec3(0,    yMax, hN * zMult), bluish),
                     MapVertex(vec3(xMax, 0,    hS * zMult), bluish),
                     MapVertex(vec3(xMax, yMax, hE * zMult), bluish)]);
    }


    // flat
    map.editTileSet.insert(generateTile(0,   0,   0,   0  )).assumeWontThrow;
    const flatTileIdx = 0;
    // NW/NE/SE/SW slopes
    map.editTileSet.insert(generateTile(0,   127, 127, 0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   0,   127, 127)).assumeWontThrow;
    map.editTileSet.insert(generateTile(127, 0,   0,   127)).assumeWontThrow;
    map.editTileSet.insert(generateTile(127, 127,   0,   0)).assumeWontThrow;
    // N/E/S/W slopes (both the 'top' and 'bottom' versions)
    map.editTileSet.insert(generateTile(0,   0,   127, 0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   127, 127, 127)).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   0,   0,   127)).assumeWontThrow;
    map.editTileSet.insert(generateTile(127, 0,   127, 127)).assumeWontThrow;
    map.editTileSet.insert(generateTile(127, 0,   0,   0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(127, 127, 0,   127)).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   127, 0,   0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(127, 127, 127, 0  )).assumeWontThrow;
    // "Tents" with opposing corners raised
    map.editTileSet.insert(generateTile(127, 0,   127, 0  )).assumeWontThrow;
    map.editTileSet.insert(generateTile(0,   127, 0,   127)).assumeWontThrow;


    foreach(uint x; 0 .. cast(uint)map.width_)
    {
        foreach(uint y; 0 .. cast(uint)map.height_)
        {
            const ubyte red = cast(ubyte)((cast(float)x / map.width_) * 255.0);
            const ubyte green = cast(ubyte)((cast(float)y / map.height_) * 255.0);
            const ubyte blue = 255;
            const ubyte alpha = 255;
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
    auto map = new Map(256, 256, 32);
    generatePlainMap(map);
}

private:

/** A cell command. These are added by `commandXXX` methods of `Map`, and then
 * executed together by `Map.applyCommands.`
 */
struct MapCommand
{
    /// Command types.
    enum Type: ubyte
    {
        /// Set a cell at specified coordinates.
        SetCell,
        /// Delete cell at specified coordinates.
        ClearCell,
        /// Raise terrain at specified coordinates.
        RaiseTerrain
    }
    /// Type of the command.
    Type type;
    /// Column of the affected cell.
    uint column;
    /// Row of the affected cell.
    uint row;
    /// Layer of the affected cell.
    uint layer;

    union
    {
        /// Cell data if `type == CellType.Cell`.
        Cell cell;
    }
}


/** Cell "type". Currently used to differentiate between empty cells (no cell in this
 * row/column/layer) and full cells with cell data in a `Cell` instance.
 */
enum CellType: ubyte
{
    /// The cell is empty; i.e. there is no cell.
    Empty,
    /// There is a cell.
    Cell
}

// TODO use std.allocator everywhere below this point
// (except allocating CellLayer instances) and make most of this code @nogc.
// 2015-07-06

/// Row of cells in a layer of the map.
struct CellRow
{
    /** A cell indexed by the column the cell is located in.
     */
    struct IndexedCell
    {
        ushort column;
        Cell cell;
    }

    /** Cells in the row, sorted by column.
     *
     * This array does not necessarily have an item for each column, as there
     * may not be a cell in each column.
     */
    Array!IndexedCell cells;

    /// Checks if the row is valid (at least if cells are sorted by column).
    bool invariant_() @trusted nothrow
    {
        return cells[].map!(c => c.column).isSorted.assumeWontThrow;
    }
}


/** A layer of cells on the map.
 *
 * The map may consist of multiple layers with different height levels. This allows
 * things like hills, slopes, cliffs, bridges, and multi-level structures.
 *
 * `CellLayer` is a class as there are not many instances of it, but it must be
 * destroyed manually/deterministically.
 */
class CellLayer
{
private:
    /** A 2D array (width_ * height_) specifying the type of cell in each row/column in
     * the layer.
     *
     * If `cellTypes_[x][y] == CellType.Cell`, `rows_[x]` will contain a cell
     * on column `y`.  If `cellTypes_[x][y] == CellType.Empty`, `rows_[x]` will
     * contain no such cell.
     */
    CellType[][] cellTypes_;

    /// Cell rows on the layer. The length of this array is `height_`.
    CellRow[] rows_;

    /// Width of the layer (map) in columns.
    const size_t width_;
    /// Width of the layer (map) in rows.
    const size_t height_;

    /// Invariant to ensure the layer is valid.
    invariant
    {
        assert(cellTypes_.length == width_,
               "CellLayer.cellTypes_ size changed over its lifetime");
        assert(cellTypes_[0].length == height_,
               "CellLayer.cellTypes_ size changed over its lifetime");
        assert(rows_.length == height_,
               "CellLayer.rows_ size changed over its lifetime");
    }

public:
    /// Construct a CellLayer with specified size.
    this(size_t width, size_t height) @safe pure nothrow // @nogc (TODO std.allocator)
    {
        rows_ = new CellRow[height];
        cellTypes_ = new CellType[][width];
        width_ = width;
        height_ = height;
        foreach(ref col; cellTypes_)
        {
            col = new CellType[height];
        }
    }

    /// Destroy the layer, deallocating used memory.
    ~this()
    {
        foreach(ref row; rows_) { destroy(row.cells); }
    }

    /** Delete cell at specified coordinates, if any.
     *
     * Does nothing if there is no cell at given coordinates.
     */
    void deleteCell(uint x, uint y) @system nothrow //pure @nogc
    {
        (){
        if(cellTypes_[x][y] != CellType.Empty)
        {
            CellRow* row = &(rows_[y]);
            // Removing an item from a sorted array (row)
            // This shouldn't be slow as one row should never have
            // too many cells (<256 most of the time, <4096 covers even insane cases)

            // Find the cell
            const deletePos = row.cells[].countUntil!(c => c.column == x);
            assert(deletePos != -1,
                   "cell x not found in row y even though cellTypes_[x][y] is not Empty");
            // Move all cells after deleted cell back
            moveAll(row.cells[deletePos + 1 .. $],
                    row.cells[deletePos .. $ - 1]);
            // Shorten the array
            row.cells.removeBack(1);
            cellTypes_[x][y] = CellType.Empty;
        }
        }().assumeWontThrow();
    }

    /** Set cell at specified coordinates.
     *
     * Params:
     *
     * x    = Column of the cell.
     * y    = Row of the cell.
     * cell = Cell data to set.
     */
    void setCell(uint x, uint y, Cell cell) @system nothrow //pure @nogc
    {
        (){
        CellRow* row = &(rows_[y]);
        final switch(cellTypes_[x][y])
        {
            case CellType.Empty:
                scope(exit)
                {
                    assert(row.invariant_(), "Cell row invalid after inserting a cell");
                    cellTypes_[x][y] = CellType.Cell;
                }
                // Fast path when appending a cell (during map creation)
                if(!row.cells.empty && row.cells.back.column < x)
                {
                    row.cells.insert(CellRow.IndexedCell(cast(ushort)x, cell));
                    break;
                }
                // Inserting a new cell into the cell row.
                row.cells.insertBefore(row.cells[].find!(c => c.column > x),
                                       CellRow.IndexedCell(cast(ushort)x, cell));
                break;
            case CellType.Cell:
                // If there is already a cell at these coordinates, rewrite
                // cell data in the row.
                foreach(ref indexedCell; row.cells) if(indexedCell.column == x)
                {
                    indexedCell.cell = cell;
                }
                break;
        }
        }().assumeWontThrow;
    }
}

/** Stores all cells (layers, rows) in the map.
 *
 * This is the map "backend".
 */
class CellState
{
private:
    // TODO use std.allocator for this 2015-07-06
    /// All cell layers of the map.
    CellLayer[] layers_;

    /// Width of the map in columns.
    const size_t width_;

    /// Height of the map in rows.
    const size_t height_;

    /// Read-only access to tiles.
    const(TileStorage) tileStorage_;

    /// Game log.
    Logger log_;

public:
    /** Construct CellState for map with specified size.
     *
     * Params:
     *
     * width       = Width of the map in columns.
     * height      = Height of the map in rows.
     * layers      = Depth of the map in layers.
     * tileStorage = Read-only access to tiles.
     * log         = Game log.
     */
    this(size_t width, size_t height, size_t layers, const(TileStorage) tileStorage,
         Logger log)
        @safe pure nothrow
    {
        tileStorage_ = tileStorage;
        log_         = log;
        // // TODO std.allocator 2015-07-06
        layers_ = new CellLayer[layers];
        width_  = width;
        height_ = height;
        foreach(ref layer; layers_)
        {
            layer = new CellLayer(width, height);
        }
    }

    /// Destroy CellState, deallocating memory.
    ~this()
    {
        foreach(layer; layers_)
        {
            destroy(layer);
        }
    }

    /** Get a range of cells in the map in specified column/row/layer interval.
     *
     * See_Also: `Map.cellRange`
     */
    auto cellRange(vec3u min, vec3u max) @safe pure nothrow const // @nogc
    {
        return CellRange(this, min, max);
    }

    /** Get a range of all cells in the map.
     *
     * See_Also: `Map.allCells`
     */
    auto allCells() @safe pure nothrow const // @nogc
    {
        return CellRange(this);
    }


    /** Write cell at specified coordinates to `outCell`, or return false if no cell
     * exists at specified coordinates or if the coordinates point outside the map.
     *
     * Params:
     *
     * outCell = The cell will be written here if it exists.
     * column  = Column of the cell.
     * row     = Row of the cell.
     * layer   = Layer of the cell.
     *
     * Returns: true if a cell was found and written to outCell, false if no cell
     *          exists at specified coordinates and outCell was default-initialized.
     */
    bool cell(out Cell outCell, uint column, uint row, uint layer)
        @trusted nothrow const // @nogc
    {
        return () {
        if(layer >= layers_.length || row >= height_ || column >= width_)
        {
            return false;
        }
        foreach(cell; layers_[layer].rows_[row].cells[])
            if(cell.column == column)
        {
            outCell = cell.cell;
            return true;
        }
        return false;
        }().assumeWontThrow;
    }

    /// Overload of `cell` taking `vec3u` coordinates.
    bool cell(out Cell outCell, vec3u coords)
        @safe nothrow const // @nogc
    {
        return cell(outCell, coords.x, coords.y, coords.z);
    }

    import std.string: format;
    /// Tests for basic CellRange functionality.
    unittest
    {
        import std.stdio;
        writeln("Map.allCells() unittest");
        scope(success) { writeln("Map.allCells() unittest SUCCESS"); }
        scope(failure) { writeln("Map.allCells() unittest FAILURE"); }
        auto map = new Map(4, 4, 4);
        map.generatePlainMap();
        auto rng = map.allCells;
        while(!rng.empty)
        {
            rng.popFront();
        }

        import std.array;
        auto array = map.allCells.array;

        size_t cellIdx = 0;
        assert(array.length == 17, "Unexpected cell count in Map.allCells");
        // From how generatePlainMap() works,
        // The first 16 cells are in rows 0-1-2-3 of layer 0,
        // followed by 1 cell of layer 1, followed by no more cells

        foreach(row; 0 .. 4)
        {
            foreach(col; 0 .. 4)
            {
                assert(array[cellIdx].row == row,
                       "Unexpected cell order in Map.allCells");
                assert(array[cellIdx].column == col,
                       "Unexpected cell order in Map.allCells");
                assert(array[cellIdx].layer == 0,
                       "Unexpected cell layer order in Map.allCells");
                ++cellIdx;
            }
        }
        assert(array[cellIdx].row == 0, "Unexpected last cell row in Map.allCells");
        assert(array[cellIdx].column == 0, "Unexpected last cell column in Map.allCells");
        assert(array[cellIdx].layer == 1, "Unexpected last cell layer in Map.allCells");
    }
    unittest
    {
        import std.stdio;
        writeln("Map.cellRange() unittest");
        scope(success) { writeln("Map.cellRange() unittest SUCCESS"); }
        scope(failure) { writeln("Map.cellRange() unittest FAILURE"); }
        auto map = new Map(4, 4, 4);
        map.generatePlainMap();
        auto rng = map.allCells;
        while(!rng.empty)
        {
            rng.popFront();
        }

        import std.array;
        auto array = map.cellRange(vec3u(1, 1, 0), vec3u(3, 3, 1)).array;

        size_t cellIdx = 0;
        assert(array.length == 4,
               "Unexpected cell count in Map.cellRange: %s".format(array.length));

        foreach(row; 1 .. 3)
        {
            foreach(col; 1 .. 3)
            {
                assert(array[cellIdx].row == row,
                       "Unexpected cell order in Map.cellRange");
                assert(array[cellIdx].column == col,
                       "Unexpected cell order in Map.cellRange");
                assert(array[cellIdx].layer == 0,
                       "Unexpected cell layer order in Map.cellRange");
                ++cellIdx;
            }
        }
    }

    /// Apply specified MapCommand.
    void command(ref const MapCommand cmd) @trusted nothrow
    {
        auto layer = layers_[cmd.layer];
        final switch(cmd.type) with(MapCommand.Type)
        {
            case ClearCell:    layer.deleteCell(cmd.column, cmd.row);        break;
            case SetCell:      layer.setCell(cmd.column, cmd.row, cmd.cell); break;
            case RaiseTerrain: raiseTerrain(cmd.column, cmd.row, cmd.layer); break;
        }
    }
        }
    }
}

/** An `InputRange` over all cells in the map.
 *
 * The cells are in the following order (but note that layers/rows/columns that
 * contain no cells are ignored; only cells are iterated):
 *
 * ```
 * layer 0:
 *     row 0:
 *         column 0
 *         ...
 *         column max
 *     row 1: ...
 *     ...
 *     row max
 * layer 1: ...
 * ...
 * layer max
 * ```
 */
struct CellRange
{
private:
    /// Minimum column (inclusive) of cells in the range.
    uint minColumn_ = 0;
    /// Maximum column (exclusive) of cells in the range.
    uint maxColumn_ = uint.max;
    /// Minimum row (inclusive) of cells in the range.
    uint minRow_ = 0;
    /// Maximum row (exclusive) of cells in the range.
    uint maxRow_ = uint.max;
    /// Minimum layer (inclusive) of cells in the range.
    uint minLayer_ = 0;
    /// Maximum layer (exclusive) of cells in the range.
    uint maxLayer_ = uint.max;

    /// Current cell layer.
    uint layer_ = 0;
    /// Current cell row.
    uint row_ = 0;
    /** Index of the current cell in current row.
    *
    * `uint.max` at the beginning, incremented in each `nextCell` call, which
    * changes it to 0 in constructor.
    */
    uint rowIdx_ = uint.max;
    /// Reference to cell state (containing all layers).
    const(CellState) map_;

    /// Is the range empty (no more cells)?
    bool empty_;

public:
    /// Element of the range. `Cell` extended by coordinate data.
    struct CellWithCoords
    {
        /// Column the cell is on.
        uint column;
        /// Row containing the cell.
        uint row;
        /// Layer containing the cell.
        uint layer;

        /// Cell itself.
        Cell cell;
        alias cell this;
    }

    /** Construct a `CellRange` referencing specified `CellState`.
     *
     * Params:
     *
     * map = Cell state of the map this range will iterate over cells of.
     * min = Minimum column, row and layer (inclusive) of cells to iterate.
     * max = Maximum column, row and layer (exclusive) of cells to iterate.
     */
    this(const(CellState) map, vec3u min = vec3u(0, 0, 0),
                               vec3u max = vec3u(uint.max, uint.max, uint.max))
        @trusted pure nothrow //@nogc
    {
        map_ = map;

        assert(min.x <= max.x, "minimum column must be <= maximum column");
        assert(min.y <= max.y, "minimum row must be <= maximum row");
        assert(min.z <= max.z, "minimum layer must be <= maximum layer");

        minColumn_ = min.x;
        minRow_    = min.y;
        minLayer_  = min.z;
        maxColumn_ = max.x;
        maxRow_    = max.y;
        maxLayer_  = max.z;

        if(min.x == max.x || min.y == max.y || min.z == max.z ||
           minColumn_ > map_.width_ ||
           minRow_ >= map_.height_ ||
           minLayer_ >= map_.layers_.length)
        {
            empty_ = true;
            return;
        }

        skipLayers();
        skipRows();
        skipCells();
        getToCell();
    }


    /// Get the current element (cell).
    CellWithCoords front() @safe pure nothrow const
        //TODO @nogc when std.container.array.Array is @nogc or replaced. 2015-06-21
    {
        assert(!empty, "Can't get front of an empty range");
        const cell = map_.layers_[layer_].rows_[row_].cells[rowIdx_];
        return CellWithCoords(cell.column, row_, layer_, cell.cell);
    }

    /// Move to the next cell.
    void popFront() @trusted pure nothrow //@nogc
    {
        assert(!empty, "Can't pop front of an empty range");
        // Move to the next cell, and check if it's in the interval and if it
        // exists at all. If not, skip any cells/rows/layers to get to the next
        // cell in the interval.
        ++rowIdx_;
        getToCell();
    }

    /// Is the range empty (no more cells)?
    bool empty() @safe pure nothrow const @nogc { return empty_; }

private:
    /** Are we currently on an existing cell in the interval?
     * If not, there are no more cells in the range in this row.
     *
     * Any cells before the interval must be skipped before calling this.
     */
    bool haveCell() @safe pure nothrow //@nogc
    {
        const(CellRow)* rowPtr = &map_.layers_[layer_].rows_[row_];
        assert(rowIdx_ <= rowPtr.cells.length, "unexpected rowIdx_ value");
        if(rowIdx_ == rowPtr.cells.length)
        {
            // finished the row
            return false;
        }
        const column = rowPtr.cells[rowIdx_].column;
        assert(column >= minColumn_,
               "must skip all cells with column < minColumn before haveCell call");
        // if column < maxColumn_, we have a cell we can read.
        // Otherwise we've exhausted useful cells in the row.
        return column < maxColumn_;
    }

    /** Are we currently on a row in the interval? If not, need to move to the next layer.
     *
     * Any rows before the interval must be skipped before calling this.
     */
    bool haveRow() @safe pure nothrow @nogc
    {
        assert(row_ <= map_.height_, "row_ out of range");
        return row_ < map_.height_ && row_ < maxRow_;
    }

    /** Are we currently on a layer in the interval? If not, there are no more layers.
     *
     * Any layers before the interval must be skipped before calling this.
     */
    bool haveLayer() @safe pure nothrow @nogc
    {
        assert(layer_ <= map_.layers_.length, "layer_ out of range");
        return layer_ < map_.layers_.length && layer_ < maxLayer_;
    }

    /** Check if we're at a valid cell and if not, move to the first layer/row with
     * a valid cell or declare the range empty.
     *
     * Before calling `getToCell()`, any cells before the interval must be skipped.
     */
    void getToCell() @safe pure nothrow
    {
        // If we don't have a cell in the interval after skipping cells before the
        // interval (and possibly processing some cells in the interval), there are
        // no more cells in the interval so we need to move to the next row.
        while(!haveCell())
        {
            ++row_;
            while(!haveRow())
            {
                ++layer_;
                if(!haveLayer())
                {
                    empty_ = true;
                    return;
                }
                skipRows();
            }
            skipCells();
        }
    }

    /// Move to the first layer in the interval.
    void skipLayers() @safe pure nothrow @nogc { layer_ = minLayer_; }

    /// Move to the first row in the interval - in current layer.
    void skipRows() @safe pure nothrow @nogc   { row_ = minRow_; }

    /** Skip all cells before the interval - in current row.
     *
     * Note that this does not mean that the cell skipped to is in the interval;
     * it might be behind it. `haveCell` handles that.
     */
    void skipCells() @safe pure nothrow //@nogc
    {
        const(CellRow)* rowPtr = &map_.layers_[layer_].rows_[row_];
        for(rowIdx_ = 0; rowIdx_ < rowPtr.cells.length; ++rowIdx_)
        {
            if(rowPtr.cells[rowIdx_].column >= minColumn_)
            {
                break;
            }
        }
    }
}
