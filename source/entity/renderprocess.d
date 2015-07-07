//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module entity.renderprocess;


import std.exception;
import std.experimental.logger;
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
    // Must run in thread 0 (main thread) for OpenGL to work.
    enum boundToThread = 0;
private:
    // A simple 3D vertex.
    struct Vertex
    {
        // Position of the vertex.
        vec3 position;

        // Color of the vertex.
        Color color;

    @safe pure nothrow @nogc:
        // Shortcut constructor.
        this(float x, float y, float z) { position = vec3(x, y, z); }

        // Constructor from coords and a color.
        this(float x, float y, float z, Color c)
        {
            position = vec3(x, y, z);
            color    = c;
        }

        // Constructor from position vector and a color.
        this(vec3 pos, Color c)
        {
            position = pos;
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
    // Access to mouse input.
    const Mouse mouse_;

    // 2D isometric camera used for projection and view matrices.
    const Camera camera_;

    import game.map;
    // Game map.
    const Map map_;

    // OpenGL wrapper.
    OpenGL gl_;

    // Specifies how the RenderProcess should draw.
    enum RenderMode
    {
        // Draw everything.
        Full,
        // Draw everything, but only as a point.
        Points,
        // Don't draw anything, don't even update vertex arrays.
        None
    }

    // Current render mode.
    RenderMode renderMode_ = RenderMode.Full;

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

    // VertexArray of the axis thingy (showing axes in different colors).
    VertexArray!Vertex axisThingy_;

    // Entity draws are accumulated here and then drawn together.
    VertexArray!Vertex entitiesBatch_;

    // Bars over selected entities are accumulated here and then drawn together.
    VertexArray!Vertex selectionBatch_;

    // Lines showing entity facings are accumulated here and then drawn together.
    VertexArray!Vertex facingBatch_;

    // Batch used to draw UI elements that are drawn as triangles and redrawn every frame.
    VertexArray!Vertex uiBatch_;

    // Size of a map cell on the screen (the 3rd coord maps world Z to screen Y).
    enum cellSizeScreen_ = vec3u(96, 48, 24);
    // Size of a map cell in world space.
    enum cellSizeWorld_  = vec3d(67.882251, 67.882251, 33.9411255);

    import tharsis.prof;
    // Profiler for the thread the RenderProcess runs in. Passed on every preProcess() and 
    // must not be use outside process(), preProcess() and postProcess().
    Profiler threadProfiler_;

public:
    /** Construct a RenderProcess.
     *
     * Note that the RenderProcess must be destroyed manually when no longer used.
     *
     * Params:
     *
     * video    = The video device.
     * keyboard = Access to keyboard input.
     * mouse    = Access to mouse input.
     * camera   = Isometric camera.
     * map      = Game map.
     * log      = Game log.
     */
    this(VideoDevice video, const Keyboard keyboard, const Mouse mouse, 
         const Camera camera, const Map map, Logger log)
        @trusted nothrow
    {
        log_      = log;
        video_    = video;
        keyboard_ = keyboard;
        mouse_    = mouse;
        camera_   = camera;
        gl_       = video_.gl;
        map_      = map;

        try
        {
            program_ = new GLProgram(gl_, shaderSrc);
            uniforms_ = GLUniforms!UniformsSpec(program_);
        }
        catch(OpenGLException e)
        {
            log_.error(e).assumeWontThrow;
            log_.error("Failed to construct the main GLSL program or to load uniforms "
                       "from the program. Will run without drawing graphics.")
                       .assumeWontThrow;
            program_ = null;
        }
        catch(Throwable e)
        {
            log_.error(e).assumeWontThrow;
            assert(false, "Unexpected exception in RenderProcess.this()");
        }

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

        entitiesBatch_  = new VertexArray!Vertex(gl_, new Vertex[32768]);
        selectionBatch_ = new VertexArray!Vertex(gl_, new Vertex[32768]);
        facingBatch_    = new VertexArray!Vertex(gl_, new Vertex[32768]);
        uiBatch_        = new VertexArray!Vertex(gl_, new Vertex[8192]);
    }

    /// Destroy the RenderProcess along with any rendering data.
    ~this()
    {
        if(program_ !is null) { program_.__dtor(); }
        uiBatch_.__dtor();
        selectionBatch_.__dtor();
        facingBatch_.__dtor();
        entitiesBatch_.__dtor();
        axisThingy_.__dtor();
    }

    /// Draw anything that should be drawn before any entities.
    void preProcess(Profiler threadProfiler) nothrow
    {
        threadProfiler_ = threadProfiler;
        // This will still be called even if the program construction fails.
        if(program_ is null) { return; }

        if(keyboard_.key(Key.One))   { renderMode_ = RenderMode.Full; }
        if(keyboard_.key(Key.Two))   { renderMode_ = RenderMode.Points; }
        if(keyboard_.key(Key.Three)) { renderMode_ = RenderMode.None; }

        // The rest of preProcess() is just rendering.
        if(renderMode_ == RenderMode.None) { return; }


        scope(exit) { gl_.runtimeCheck(); }

        glEnable(GL_DEPTH_TEST);

        uniforms_.projection = camera_.projection;
        uniforms_.modelView  = camera_.view;
        program_.use();

        scope(exit) { program_.unuse(); }

        const pointsOnly = renderMode_ == RenderMode.Points;
        const lines      = pointsOnly ? PrimitiveType.Points : PrimitiveType.Lines;
        const triangles  = pointsOnly ? PrimitiveType.Points : PrimitiveType.Triangles;

        {
        }

        if(axisThingy_.bind(program_))
        {
            axisThingy_.draw(lines, 0, axisThingy_.length);
            axisThingy_.release();
        }
        else { logVArrayBindError("axisThingy_"); }

        const mouse = camera_.screenToOrtho(vec2(mouse_.x, mouse_.y));
        // const mouse = vec2(mouse_.x, mouse_.y) - camera_.size * 0.5;
        uiBatch_.put(Vertex(mouse.x,      mouse.y - 20, 1000.0f, rgb!"FFFFEE"));
        uiBatch_.put(Vertex(mouse.x + 14, mouse.y - 13, 1000.0f, rgb!"FFFFEE"));
        uiBatch_.put(Vertex(mouse.x,      mouse.y,      1000.0f, rgb!"FFFFFF"));
    }

    /// Draw an entity with specified position and visual.
    void process(ref const PositionComponent pos,
                 ref const VisualComponent vis) @safe nothrow
    {
        if(renderMode_ == RenderMode.None) { return; }

        static allPositions =
        [
            // TODO: For now we just draw a triangle. Will draw something
            //       more complex later. 2014-08-27
            // vec3( 20, -20, -20), vec3(-20,  20, -20), vec3(-20, -20,  20),
            // vec3( 20,  20,  20), vec3(-20,  20, -20), vec3(-20, -20,  20),
            // vec3( 20,  20,  20), vec3( 20, -20, -20), vec3(-20,  20, -20),
            vec3( 20,  20,  20), vec3( 20, -20, -20), vec3(-20, -20,  20)
        ];

        const pointsOnly = renderMode_ == RenderMode.Points;
        auto positions = pointsOnly ? allPositions[0 .. 1] : allPositions[];

        // Draw and empty any batch if it runs out of space
        if(entitiesBatch_.capacity - entitiesBatch_.length < positions.length)
        {
            uniforms_.projection = camera_.projection;
            uniforms_.modelView  = camera_.view;
            drawBatch(entitiesBatch_, PrimitiveType.Triangles);
        }
        if(facingBatch_.capacity - facingBatch_.length < 2)
        {
            uniforms_.projection = camera_.projection;
            uniforms_.modelView  = camera_.view;
            drawBatch(entitiesBatch_, PrimitiveType.Triangles);
        }

        foreach(i, v; positions)
        {
            entitiesBatch_.put(Vertex(v + pos, vis.color));
        }
        facingBatch_.put(Vertex(pos, rgb!"F0F080"));
        facingBatch_.put(Vertex(pos + pos.facing * 50.0, rgb!"F0F080"));
    }

    /// Draw a selected entity.
    void process(ref const PositionComponent pos,
                 ref const VisualComponent vis,
                 ref const SelectableComponent select) @safe nothrow
    {
        if(renderMode_ == RenderMode.None) { return; }
        process(pos, vis);

        if(!select.isSelected) { return; }

        const pointsOnly = renderMode_ == RenderMode.Points;

        // Draw and empty the batch if we've run out of space.
        if(selectionBatch_.capacity - selectionBatch_.length < 2)
        {
            uniforms_.projection = camera_.projection;
            uniforms_.modelView  = mat4.identity;
            drawBatch(selectionBatch_, PrimitiveType.Lines);
        }

        // Transform to 2D space, but not screen space.
        vec2 coords = vec2(camera_.view * vec4(pos, 0));
        // Z is really far in front so it's in front of all depth-buffered draws.
        selectionBatch_.put(Vertex(coords.x - 32.0f, coords.y + 24.0f, 1000.0f, rgb!"00FF00"));
        selectionBatch_.put(Vertex(coords.x + 32.0f, coords.y + 24.0f, 1000.0f, rgb!"00FF00"));
    }

    /// Draw all batched entities that have not yet been drawn.
    void postProcess() nothrow
    {
        scope(exit)
        {
            glDisable(GL_DEPTH_TEST);
            auto swap = Zone(threadProfiler_, "video.swapBuffers()");
            // Swap the back buffer to the front, showing it in the window.
            // Outside of the frameLoad zone because VSync could break our profiling.
            video_.swapBuffers();
        }

        if(renderMode_ == RenderMode.None) { return; }

        uniforms_.projection = camera_.projection;
        uniforms_.modelView  = camera_.view;
        if(!entitiesBatch_.empty) { drawBatch(entitiesBatch_, PrimitiveType.Triangles); }
        if(!facingBatch_.empty)   { drawBatch(facingBatch_, PrimitiveType.Lines); }
        uniforms_.modelView  = mat4.identity;
        if(!selectionBatch_.empty) { drawBatch(selectionBatch_, PrimitiveType.Lines); }
        uniforms_.projection = camera_.ortho;
        if(!uiBatch_.empty)        { drawBatch(uiBatch_, PrimitiveType.Triangles); }

        // Log GL errors, if any.
        video_.gl.runtimeCheck();
    }

private:

    /// Draw all entities batched so far.
    void drawBatch(VertexArray!Vertex batch, PrimitiveType type) @safe nothrow
    {
        auto swap = Zone(threadProfiler_, "RenderProcess.drawBatch()");
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
            const pointsOnly = renderMode_ == RenderMode.Points;
            batch.draw(pointsOnly ? PrimitiveType.Points : type, 0, batch.length);
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
