//          Copyright Ferdinand Majerech 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Implementation of maps and cells.
module game.map;


import core.memory;
import std.algorithm;
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

/** One cell (3D 'cube') of the map.
 *
 * A cell represents a 'filled' volume; its base is a diamond-shaped at the bottom
 * of the layer the cell is in, while its ceiling (surface that can be walked on)
 * can have varying heights at each corner of the diamond, allowing to represent
 * slopes.
 */
struct Cell
{
    // TODO in future most of this data will be in CellType (or something),
    //      which will be indexed by Cell
    /// Height of the cell surface at its northern corner.
    ubyte heightN = 0;
    /// Height of the cell surface at its eastern corner.
    ubyte heightE = 0;
    /// Height of the cell surface at its southern corner.
    ubyte heightS = 0;
    /// Height of the cell surface at its western corner.
    ubyte heightW = 0;

    // TODO replace with an index to an external struct with 2 arrays of Vertices
    //      for RenderProcess to copy (lines and triangles) 2015-07-05
    /// Cell border color
    Color borderColor = rgb!"FFFFFF";
    /// Color of the cell surface
    Color cellColor   = rgb!"8080FF";

//  obsolete once cell graphics are represented by arrays of vertices
//     bool cliffSW = false;
//     bool cliffSE = false;
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
    /// Cell commands to be executed on the next call to `applyCellCommands()`.
    Array!CellCommand commands_;


public:
    /** Create a map with specified size
     *
     * Params:
     *
     * width  = Number of cells in each row of the map.
     * height = Number of rows in each layer of the map.
     * layers = Number of layers in the map.
     */
    this(size_t width, size_t height, size_t layers) @safe pure nothrow
    {
        cells_  = new CellState(width, height, layers);
        assert(width < ushort.max, "Map width can't be >65535 cells");
        assert(height < ushort.max, "Map height can't be >65535 cells");
        width_  = width;
        height_ = height;
        layers_ = layers;
    }

    /// Destroy the map, deallocating used memory.
    ~this()
    {
        destroy(cells_);
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

    /** Add a cell command to set cell at specified coordinates.
     *
     * `applyCellCommands` must be called to apply this command.
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
    void cellCommandSet(size_t column, size_t row, size_t layer, Cell cell)
        @trusted nothrow
    {
        assert(column < width_, "cell column out of range");
        assert(row < height_, "cell row out of range");
        assert(layer < layers_, "cell layer out of range");
        commands_.insert(CellCommand(column, row, layer, CellType.Cell, cell)).assumeWontThrow;
    }

    /** Add a cell command to delete cell at specified coordinates. Will do nothing if
     * ther is no cell.
     *
     * `applyCellCommands` must be called to apply this command.
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
    void cellCommandClear(size_t column, size_t row, size_t layer)
        @trusted nothrow
    {
        assert(column < width_, "cell column out of range");
        assert(row < height_, "cell row out of range");
        assert(layer < layers_, "cell layer out of range");
        commands_.insert(CellCommand(column, row, layer, CellType.Empty)).assumeWontThrow;
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
    void applyCellCommands()
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
    @safe nothrow
{
    foreach(x; 0 .. map.width_)
    {
        foreach(y; 0 .. map.height_)
        {
            const ubyte red = cast(ubyte)((cast(float)x / map.width_) * 255.0);
            const ubyte green = cast(ubyte)((cast(float)y / map.height_) * 255.0);
            const ubyte blue = 255;
            const ubyte alpha = 255;
            map.cellCommandSet(x, y, 0, Cell(0, 0, 0, 0, rgb!"FF0000", Color(red, green, blue, alpha)));
            // Just to have some layering
            if((x % 4 == 0) && (y % 4 == 0))
            {
                map.cellCommandSet(x, y, 1, Cell(0, 0, 0, 0, rgb!"FF0000", Color(red, green, blue, alpha)));
            }
        }
        map.applyCellCommands();
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

/** A cell command. These are added by `cellCommandXXX` methods of `Map`, and then
 * executed together by `Map.applyCellCommands.`
 */
struct CellCommand
{
    /// Column of the affected cell.
    size_t column;
    /// Row of the affected cell.
    size_t row;
    /// Layer of the affected cell.
    size_t layer;
    /// Cell type the cell should be after applying the command
    /// (`CellType.Empty to delete the cell`)
    CellType type;
    /// Cell data if `type == CellType.Cell`.
    Cell cell;
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
        GC.free(rows_.ptr);

        foreach(col; cellTypes_) { GC.free(col.ptr); }
        GC.free(cellTypes_.ptr);
    }

    /** Delete cell at specified coordinates, if any.
     *
     * Does nothing if there is no cell at given coordinates.
     */
    void deleteCell(size_t x, size_t y) @system nothrow //pure @nogc
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
    void setCell(size_t x, size_t y, ref const Cell cell) @system nothrow //pure @nogc
    {
        (){
        CellRow* row = &(rows_[y]);
        final switch(cellTypes_[x][y])
        {
            case CellType.Empty:
                // Fast path when appending a cell (during map creation)
                if(!row.cells.empty && row.cells.back.column < x)
                {
                    row.cells.insert(CellRow.IndexedCell(cast(ushort)x, cell));
                    break;
                }
                // Inserting a new cell into the cell row.
                row.cells.insertBefore(row.cells[].find!(c => c.column > x),
                                       CellRow.IndexedCell(cast(ushort)x, cell));
                assert(row.invariant_(), "Cell row invalid after inserting a cell");
                cellTypes_[x][y] = CellType.Cell;
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

public:
    /** Construct CellState for map with specified size.
     *
     * Params:
     *
     * width  = Width of the map in columns.
     * height = Height of the map in rows.
     * layers = Depth of the map in layers.
     *
     */
    this(size_t width, size_t height, size_t layers) @safe pure nothrow
    {
        // TODO std.allocator 2015-07-06
        layers_ = new CellLayer[layers];
        width_ = width;
        height_ = height;
        foreach(ref layer; layers_)
        {
            layer = new CellLayer(width, height);
        }
    }

    /// Destroy CellState, deallocating memory.
    ~this()
    {
        foreach(layer; layers_) { destroy(layer); }
        GC.free(layers_.ptr);
    }


    /** Get a range of all cells in the map.
     *
     * See_Also: `Map.allCells`
     */
    auto allCells() @safe pure nothrow const // @nogc
    {
        return CellRange(this);
    }
    /// Test for basic CellRange functionality.
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

    /// Apply specified CellCommand.
    void command(ref const CellCommand cmd) @trusted nothrow
    {
        auto layer = layers_[cmd.layer];
        final switch(cmd.type)
        {
            case CellType.Empty: layer.deleteCell(cmd.column, cmd.row); break;
            case CellType.Cell:  layer.setCell(cmd.column, cmd.row, cmd.cell); break;
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
    size_t layer_ = 0;
    /// Current cell row.
    size_t row_ = 0;
    /** Index of the current cell in current row.
    *
    * `size_t.max` at the beginning, incremented in each `nextCell` call, which
    * changes it to 0 in constructor.
    */
    size_t rowIdx_ = size_t.max;
    /// Reference to cell state (containing all layers).
    const(CellState) map_;

    /// Is the range empty (no more cells)?
    bool empty_;

public:
    /// Element of the range. `Cell` extended by coordinate data.
    struct CellWithCoords
    {
        /// Column the cell is on.
        size_t column;
        /// Row containing the cell.
        size_t row;
        /// Layer containing the cell.
        size_t layer;

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

        assert(min.x < max.x, "minimum column must be less than maximum column");
        assert(min.y < max.y, "minimum row must be less than maximum row");
        assert(min.z < max.z, "minimum layer must be less than maximum layer");

        minColumn_ = min.x;
        minRow_    = min.y;
        minLayer_  = min.z;
        maxColumn_ = max.x;
        maxRow_    = max.y;
        maxLayer_  = max.z;

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
