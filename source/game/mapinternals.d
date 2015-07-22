//          Copyright Ferdinand Majerech 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Map implementation details.
module game.mapinternals;


import std.algorithm;
import std.experimental.logger;
import std.container.array;
import std.exception: assumeWontThrow;

import game.map;
import gl3n_extra.linalg;





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
    // TODO: std.allocator 2015-07-15
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

    /// Get coords of the **north-eastern** neighbor to specified coordinates.
    vec3u NE(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column + row % 2, row + 1, layer);
    }

    /// Get coords of the **south-eastern** neighbor to specified coordinates.
    vec3u SE(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column + row % 2, row - 1, layer);
    }

    /// Get coords of the **south-western** neighbor to specified coordinates.
    vec3u SW(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column + row % 2 - 1, row - 1, layer);
    }

    /// Get coords of the **north-western** neighbor to specified coordinates.
    vec3u NW(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column + row % 2 - 1, row + 1, layer);
    }

    /// Get coords of the **northern** neighbor to specified coordinates.
    vec3u N(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column, row + 2, layer);
    }

    /// Get coords of the **eastern** neighbor to specified coordinates.
    vec3u E(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column + 1, row, layer);
    }

    /// Get coords of the **southern** neighbor to specified coordinates.
    vec3u S(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column, row - 2, layer);
    }

    /// Get coords of the **western** neighbor to specified coordinates.
    vec3u W(uint column, uint row, uint layer) @safe nothrow const @nogc
    {
        return vec3u(column - 1, row, layer);
    }


    import std.string: format;
    /// Tests for basic CellRange functionality.
    unittest
    {
        import std.stdio;
        writeln("Map.allCells() unittest");
        scope(success) { writeln("Map.allCells() unittest SUCCESS"); }
        scope(failure) { writeln("Map.allCells() unittest FAILURE"); }
        auto map = new Map(null, 4, 4, 4);
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
        auto map = new Map(null, 4, 4, 4);
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

    /** Implementation of the RaiseTerrain command.
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
    void raiseTerrain(uint column, uint row, uint layer) @system nothrow
    {
        //////////////////////////////
        /// Nested functions first ///
        //////////////////////////////
        enum layerZ = cellSizeWorld.z;
        /* Create a cell with specified heights at specified coordinates.
         * Replaces any previously existing cell at specified coords.
         *
         * Params:
         *
         * heightN = Height the cell should have at its northern edge.
         * heightE = Height the cell should have at its eastern edge.
         * heightS = Height the cell should have at its southern edge.
         * heightW = Height the cell should have at its western edge.
         * coords  = column, row and layer to create the cell at.
         */
        void makeCell(uint heightN, uint heightE, uint heightS, uint heightW,
                      const vec3u coords) nothrow
        {
            if(min(heightN, heightE, heightS, heightW) >= layerZ)
            {
                layers_[coords.z].deleteCell(coords.x, coords.y);
                makeCell(heightN - layerZ, heightE - layerZ, heightS - layerZ, heightW - layerZ,
                        coords + vec3u(0, 0, 1));
                // Make a connection on above layer, and delete any cells below it.
                return;
            }

            // TODO: use matching terrain type instead of just first tile with matching
            //       heights (the terrain type will also refer to a fallback terrain
            //       type where we can look for tiles if not found in the terrain type)
            //       2015-07-13

            // Find a tile with matching heights, and set the cell to that tile.
            // This 'connects' the raised tile to terrain around it.
            const tileIdx =
                tileStorage_.allTiles.countUntil!
                (t => t.heightN == heightN && t.heightE == heightE && 
                      t.heightS == heightS && t.heightW == heightW).assumeWontThrow;
            if(tileIdx < 0)
            {
                log_.warningf("Failed to makeCell when raising terrain: "
                              "found no tile with heights %s %s %s %s",
                              heightS, heightN, heightE, heightW).assumeWontThrow;
                return;
            }
            layers_[coords.z].setCell(coords.x, coords.y, Cell(cast(uint)tileIdx));
        }

        // Call raiseTerrain on the cell (if any) below specified coordinates
        void raiseBelow(vec3u coords) nothrow
        {
            raiseTerrain(coords.x, coords.y, coords.z - 1);
        }

        /* Connect to a neighbor at specified coordinates.
         *
         * The neighbor may be on the layer the cell was raised to (top) or the
         * layer it was raised from (bottom).
         *
         * Params:
         *
         * direction = Direction of the neighbor from the raised cell.
         * tile      = Tile on the neighboring cell.
         * base      = Height of the raised cell (from the point of view of
         *             the layer specified by `coords.z`)
         * coords    = column, row and layer of the neigbor.
         */
        void connectNeighbor(Direction dir, Tile tile, uint base, vec3u coords) nothrow
        {
            const heightN = tile.heightN; const heightE = tile.heightE;
            const heightS = tile.heightS; const heightW = tile.heightW;
            final switch(dir) with(Direction)
            {
                case N:  makeCell(heightN, heightE, base, heightW, coords); break;
                case E:  makeCell(heightN, heightE, heightS, base, coords); break;
                case S:  makeCell(base, heightE, heightS, heightW, coords); break;
                case W:  makeCell(heightN, base, heightS, heightW, coords); break;
                case NE: makeCell(heightN, heightE, base, base, coords);    break;
                case SE: makeCell(base, heightE, heightS, base, coords);    break;
                case SW: makeCell(base, base, heightS, heightW, coords);    break;
                case NW: makeCell(heightN, base, base, heightW, coords);    break;
            }
        }

        bool tile(out Tile outTile, vec3u coords) @safe nothrow // @nogc
        {
            Cell cell;
            if(this.cell(cell, coords))
            {
                outTile = tileStorage_.tile(cell.tileIndex);
                return true;
            }
            return false;
        }

        //////////////////////////////////
        /// Actual raiseTerrain() code ///
        //////////////////////////////////

        log_.infof("raiseTerrain() %s %s %s", column, row, layer).assumeWontThrow;
        // Handled by Map.commandRaiseTerrain()
        assert(layer < layers_.length - 1, "Can't raise terrain from the top layer");

        Cell center;
        // If no cell at specified coords, ignore
        if(!cell(center, column, row, layer))
        {
            return;
        }

        // TODO: instead of using the first flat tile, we should use a flat tile
        //       of the same terrain type as the tile on the cell being raised.
        //       I.e. TODO TerrainType (group of tiles for same type of terrain) first.
        //       2015-07-13
        // For now, we just find the first flat tile and use it for the raised terrain.
        const flatTileIdx =
            tileStorage_.allTiles.countUntil!
            (t => t.heightN == 0 && t.heightE == 0 && t.heightS == 0 && t.heightW == 0)
            .assumeWontThrow;
        if(flatTileIdx < 0)
        {
            log_.warning("Failed to raise terrain: No flat tile loaded.").assumeWontThrow;
            return;
        }
        layers_[layer + 1].setCell(column, row, Cell(cast(uint)flatTileIdx));
        // Delete the original cell that was raised
        layers_[layer].deleteCell(column, row);


        //T: top, B: bottom
        bool[8] done;
        vec3u[8] coordsT;
        vec3u[8] coordsB;
        Tile[8] tileT;
        Tile[8] tileB;
        bool[8] gotT;
        bool[8] gotB;

        import std.traits: EnumMembers;
        foreach(dir; EnumMembers!Direction)
        {
            mixin(q{ coordsT[dir] = this.%s(column, row, layer + 1); }.format(dir));
            mixin(q{ coordsB[dir] = this.%s(column, row, layer); }.format(dir));
            gotT[dir] = tile(tileT[dir], coordsT[dir]);
            gotB[dir] = tile(tileB[dir], coordsB[dir]);
        }

        // First try to connect to cells (e.g. hills) at the level of the raised cell.
        foreach(dir; EnumMembers!Direction) if(gotT[dir])
        {
            connectNeighbor(dir, tileT[dir], 0, coordsT[dir]); 
            done[dir] = true; 
        }
        // The NE/SE/SW/NW directions have special cases where there is no 'top'
        // cell to connect with, and while there is a bottom cell, there is also
        // a neighboring top N/E/S/W cell which we need to connect to as well;
        // so we connect both the bottom e.g. NE cell and the top e.g. N cell.
        foreach(dir; diagonalDirections) if(!done[dir] && gotB[dir])
        {
            enum aDir = dir.partDirs[0];
            enum bDir = dir.partDirs[1];
            if(gotT[aDir] && gotT[bDir])
            {
                raiseBelow(coordsT[dir]);
                done[dir] = true;
            }
            // connect raised tile with dir and aDir from below
            else if(gotT[aDir])
            {
                makeCell(dir.hasN ? layerZ + tileT[aDir].heights[bDir] : layerZ,
                         dir.hasE ? tileB[dir].heights[bDir]           : layerZ,
                         dir.hasS ? layerZ + tileT[aDir].heights[bDir] : layerZ,
                         dir.hasW ? tileB[dir].heights[bDir]           : layerZ,
                         coordsT[dir] - vec3u(0, 0, 1));
                done[dir] = true;
            }
            // connect raised tile with dir and bDir from below
            else if(gotT[bDir])
            {
                makeCell(dir.hasN ? tileB[dir].heights[aDir]           : layerZ,
                         dir.hasE ? layerZ + tileT[bDir].heights[aDir] : layerZ,
                         dir.hasS ? tileB[dir].heights[aDir]           : layerZ,
                         dir.hasW ? layerZ + tileT[bDir].heights[aDir] : layerZ,
                         coordsT[dir] - vec3u(0, 0, 1));
                done[dir] = true;
            }
        }

        // Raise the foundation for our raised cell if there is no foundation
        if(layer > 0) 
        {
            foreach(dir; EnumMembers!Direction) if(!done[dir] && !gotB[dir]) 
            {
                raiseBelow(coordsB[dir]);
                gotB[dir]  = tile(tileB[dir],  coordsB[dir]);
            }
        }

        // Try to connect based on cells from the layer the cell was raised *from*

        // Note that if all heights are >= layerZ the connection will be made on
        // the layer above coordsN with heights subtracted by layerZ; the cell
        // is on the layer reached by the lowest point of the volume of its tile.
        foreach(dir; EnumMembers!Direction) if(!done[dir] && gotB[dir])
        {
            connectNeighbor(dir, tileB[dir], layerZ, coordsB[dir]);
            done[dir] = true;
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
