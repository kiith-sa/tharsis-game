//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module entity.renderprocess;


import std.exception;
import std.logger;
import std.typecons;

import derelict.opengl3.gl3;

import gfmod.opengl.matrixstack;
import gfmod.opengl.opengl;
import gfmod.opengl.program;
import gfmod.opengl.vertexarray;

import gl3n_extra.color;
import gl3n_extra.linalg;

import entity.components;
import game.camera;
import platform.inputdevice;
import platform.videodevice;


/// Handles rendering of VisualComponents.
final class RenderProcess
{
private:
    // A simple 3D vertex.
    struct Vertex
    {
        // Position of the vertex.
        vec3 position;

        // Color of the vertex.
        Color color;

        // Shortcut constructor.
        this(float x, float y, float z) @safe pure nothrow @nogc { position = vec3(x, y, z); }

        // Constructor from coords and a color.
        this(float x, float y, float z, Color c) @safe pure nothrow @nogc
        {
            position = vec3(x, y, z);
            color    = c;
        }
    }

    // Source of the shader used for drawing.
    enum shaderSrc =
      q{#version 130

        #if VERTEX_SHADER

        uniform mat4 projection;
        uniform mat4 modelView;
        in vec3 position;
        in vec4 color;

        smooth out vec4 fsColor;

        void main()
        {
            gl_Position = projection * modelView * vec4(position, 1.0);
            fsColor = color;
        }

        #elif FRAGMENT_SHADER

        smooth in vec4 fsColor;

        out vec4 resultColor;

        void main()
        {
            resultColor = fsColor;
        }

        #endif};

    // The game log.
    Logger log_;

    // The video device (screen + GL).
    VideoDevice video_;

    // Access to keyboard input.
    const Keyboard keyboard_;

    // 2D isometric camera used for projection and view matrices.
    const Camera camera_;

    // OpenGL wrapper.
    OpenGL gl_;

    // GLSL program used for drawing, compiled from shaderSrc.
    GLProgram program_;

    // Specification of uniform variables that should be in program_.
    struct UniformsSpec
    {
        mat4 projection;
        mat4 modelView;
    }

    import gfmod.opengl.uniform;
    // Provides access to uniform variables in program_.
    GLUniforms!UniformsSpec uniforms_;

    // VertexArray storing the map grid.
    VertexArray!Vertex grid_;

    // Number of vertices in grid_ to draw the bottom level of the map with (for
    // visual reference)
    size_t bottomLevelVertices_ = 6;

    // VertexArray of the axis thingy (showing axes in different colors).
    VertexArray!Vertex axisThingy_;

    // Entity draws are accumulated here and then drawn together.
    VertexArray!Vertex entitiesBatch_;

    // Bars over selected entities are accumulated here and then drawn together.
    VertexArray!Vertex selectionBatch_;

    // Size of a map cell on the screen (the 3rd coord maps world Z to screen Y).
    enum cellSizeScreen_ = vec3u(96, 48, 24);
    // Size of a map cell in world space.
    enum cellSizeWorld_  = vec3d(67.882251, 67.882251, 33.9411255);

    // Map grid width and height in cells.
    size_t gridW_, gridH_;

public:
    /** Construct a RenderProcess.
     *
     * Note that the RenderProcess must be destroyed manually when no longer used.
     *
     * Params:
     *
     * video    = The video device.
     * keyboard = Access to keyboard input.
     * camera   = Isometric camera.
     * log      = Game log.
     */
    this(VideoDevice video, const Keyboard keyboard, const Camera camera, Logger log)
        @trusted nothrow
    {
        log_      = log;
        video_    = video;
        keyboard_ = keyboard;
        camera_   = camera;
        gl_       = video_.gl;

        gridW_ = 64;
        gridH_ = 64;

        try
        {
            program_ = new GLProgram(gl_, shaderSrc);
            uniforms_ = GLUniforms!UniformsSpec(program_);
        }
        catch(OpenGLException e)
        {
            log_.error(e).assumeWontThrow;
            log_.error("Failed to construct the main GLSL program "
                       "or to load uniforms from the program. "
                       "Will run without drawing graphics.").assumeWontThrow;
            program_ = null;
        }
        catch(Throwable e)
        {
            log_.error(e).assumeWontThrow;
            assert(false, "Unexpected exception in mainLoop()");
        }

        auto vaoSpace = new Vertex[2 * gridW_ * (gridH_ + 1) +
                                   2 * gridH_ * (gridW_ + 1) +
                                   bottomLevelVertices_];
        grid_ = new VertexArray!Vertex(gl_, vaoSpace);

        double x = 0.0;
        double y = 0.0;
        const white = rgb!"FFFFFF";
        foreach(xCell; 0 .. gridW_ + 1)
        {
            y = 0.0;
            foreach(yCell; 0 .. gridH_)
            {
                grid_.put(Vertex(x, y, 0, white));
                grid_.put(Vertex(x, y + cellSizeWorld_.y, 0, white));
                y += cellSizeWorld_.y;
            }
            x += cellSizeWorld_.x;
        }
        x = y = 0.0;
        foreach(yCell; 0 .. gridH_ + 1)
        {
            x = 0.0;
            foreach(xCell; 0 .. gridW_)
            {
                grid_.put(Vertex(x, y, 0, white));
                grid_.put(Vertex(x + cellSizeWorld_.x, y, 0, white));
                x += cellSizeWorld_.x;
            }
            y += cellSizeWorld_.y;
        }
        const bottomColor = rgb!"101008";
        grid_.put(Vertex(0, 0, -10, bottomColor));
        grid_.put(Vertex(cellSizeWorld_.x * gridW_, 0, -10, bottomColor));
        grid_.put(Vertex(cellSizeWorld_.x * gridW_, cellSizeWorld_.y * gridH_, -10, bottomColor));
        grid_.put(Vertex(cellSizeWorld_.x * gridW_, cellSizeWorld_.y * gridH_, -10, bottomColor));
        grid_.put(Vertex(0, cellSizeWorld_.y * gridH_, -10, bottomColor));
        grid_.put(Vertex(0, 0, -10, bottomColor));
        grid_.lock();


        axisThingy_ = new VertexArray!Vertex(gl_, new Vertex[6]);
        // X (red)
        axisThingy_.put(Vertex(10,  10,  10,  rgb!"FFFFFF"));
        axisThingy_.put(Vertex(110, 10,  10,  rgb!"FF0000"));
        // Y (green)
        axisThingy_.put(Vertex(10,  10,  10,  rgb!"FFFFFF"));
        axisThingy_.put(Vertex(10,  110, 10,  rgb!"00FF00"));
        // Z (blue)
        axisThingy_.put(Vertex(10,  10,  10,  rgb!"FFFFFF"));
        axisThingy_.put(Vertex(10,  10,  110, rgb!"0000FF"));
        axisThingy_.lock();

        entitiesBatch_  = new VertexArray!Vertex(gl_, new Vertex[10000]);
        selectionBatch_ = new VertexArray!Vertex(gl_, new Vertex[10000]);
    }

    /// Destroy the RenderProcess along with any rendering data.
    ~this()
    {
        if(program_ !is null) { program_.__dtor(); }
        selectionBatch_.__dtor();
        entitiesBatch_.__dtor();
        axisThingy_.__dtor();
        grid_.__dtor();
    }

    /// Draw anything that should be drawn before any entities.
    void preProcess() nothrow
    {
        // This will still be called even if the program construction fails.
        if(program_ is null) { return; }

        scope(exit) { gl_.runtimeCheck(); }

        glEnable(GL_DEPTH_TEST);

        uniforms_.projection = camera_.projection;
        uniforms_.modelView  = camera_.view;
        program_.use();

        scope(exit) { program_.unuse(); }

        if(grid_.bind(program_))
        {
            grid_.draw(PrimitiveType.Lines, 0, grid_.length - bottomLevelVertices_);
            grid_.draw(PrimitiveType.Triangles, grid_.length - bottomLevelVertices_,
                          bottomLevelVertices_);
            grid_.release();
        }
        else { logVArrayBindError("grid_"); }

        if(axisThingy_.bind(program_))
        {
            axisThingy_.draw(PrimitiveType.Lines, 0, axisThingy_.length);
            axisThingy_.release();
        }
        else { logVArrayBindError("axisThingy_"); }
    }

    /// Draw an entity with specified position and visual.
    void process(ref const PositionComponent pos,
                 ref const VisualComponent vis) @safe nothrow
    {
        static positions =
        [
            vec3( 20, -20, -20),
            vec3(-20,  20, -20),
            vec3(-20, -20,  20),

            vec3( 20,  20,  20),
            vec3(-20,  20, -20),
            vec3(-20, -20,  20),

            vec3( 20,  20,  20),
            vec3( 20, -20, -20),
            vec3(-20,  20, -20),

            vec3( 20,  20,  20),
            vec3( 20, -20, -20),
            vec3(-20, -20,  20)
        ];

        // Draw and empty the batch if we've run out of space.
        if(entitiesBatch_.capacity - entitiesBatch_.length < positions.length)
        {
            uniforms_.projection = camera_.projection;
            uniforms_.modelView  = camera_.view;
            drawBatch(entitiesBatch_, PrimitiveType.Triangles);
        }

        foreach(i, v; positions)
        {
            entitiesBatch_.put(Vertex(v.x + pos.x, v.y + pos.y, v.z + pos.z,
                                      Color(vis.r, vis.g, vis.b, vis.a)));
        }
    }

    /// Draw a selected entity.
    void process(ref const PositionComponent pos,
                 ref const VisualComponent vis,
                 ref const SelectionComponent select) @safe nothrow
    {
        // Draw and empty the batch if we've run out of space.
        if(selectionBatch_.capacity - selectionBatch_.length < 2)
        {
            uniforms_.projection = camera_.projection;
            uniforms_.modelView  = mat4.identity;
            drawBatch(selectionBatch_, PrimitiveType.Lines);
        }

        // Transform to 2D space, but not screen space.
        vec2 coords = vec2(camera_.view * vec4(pos.x, pos.y, pos.z, 0));
        // Z is really far in front so it's in front of all depth-buffered draws.
        selectionBatch_.put(Vertex(coords.x - 32.0f, coords.y + 24.0f, 1000.0f, rgb!"00FF00"));
        selectionBatch_.put(Vertex(coords.x + 32.0f, coords.y + 24.0f, 1000.0f, rgb!"00FF00"));

        process(pos, vis);
    }

    /// Draw all batched entities that have not yet been drawn.
    void postProcess() nothrow
    {
        uniforms_.projection = camera_.projection;
        uniforms_.modelView  = camera_.view;
        if(!entitiesBatch_.empty) { drawBatch(entitiesBatch_, PrimitiveType.Triangles); }
        uniforms_.modelView  = mat4.identity;
        if(!selectionBatch_.empty) { drawBatch(selectionBatch_, PrimitiveType.Lines); }
        glDisable(GL_DEPTH_TEST);
    }

private:

    /// Draw all entities batched so far.
    void drawBatch(VertexArray!Vertex batch, PrimitiveType type) @safe nothrow
    {
        scope(exit) { gl_.runtimeCheck(); }

        program_.use();
        scope(exit) { program_.unuse(); }

        batch.lock();
        scope(exit)
        {
            batch.unlock();
            batch.clear();
        }

        if(batch.bind(program_))
        {
            batch.draw(type, 0, batch.length);
            batch.release();
        }
        else { logVArrayBindError("some batch"); }
    }

    // Log an error after failing to bind VAO with specified name.
    void logVArrayBindError(string name) @safe nothrow
    {
        log_.error("Failed to bind VertexArray \"%s\"; probably missing vertex "
                   " attribute in a GLSL program. Will not draw.").assumeWontThrow;
    }
}
