//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Processes operating on entities in the game.
module entity.processes;


import std.exception;
import std.logger;

import derelict.opengl3.gl3;

import gfmod.opengl.matrixstack;
import gfmod.opengl.opengl;
import gfmod.opengl.program;
import gfmod.opengl.vao;

import entity.components;
import platform.videodevice;
import gl3n_extra.color;
import gl3n_extra.linalg;


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

    // VAO storing the map grid.
    VAO!Vertex gridVAO_;

    // Number of vertices in gridVAO_ to draw the bottom level of the map with (for
    // visual reference)
    size_t bottomLevelVertices_ = 6;

    // VAO of the axis thingy (showing axes in different colors).
    VAO!Vertex axisThingy_;

    // Entity draws are accumulated here and then drawn at once.
    VAO!Vertex entitiesBatch_;

    // Projection matrix stack.
    MatrixStack!(float, 4) projection_;

    // Modelview matrix stack.
    MatrixStack!(float, 16) modelView_;


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
     * video = The video device.
     * log   = Game log.
     */
    this(VideoDevice video, Logger log) @trusted nothrow
    {
        log_   = log;
        video_ = video;
        gl_    = video_.gl;

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


        // 4 levels should be enough for projection.
        projection_ = new MatrixStack!(float, 4)();
        modelView_  = new MatrixStack!(float, 16)();
        const w = video.width;
        const h = video.height;
        projection_.ortho(-w / 2, w / 2, -h / 2, h / 2, -2000, 2000);

        import std.math;
        modelView_.rotate(PI / 2 - (PI / 6), vec3(1, 0, 0));
        modelView_.rotate(PI / 4, vec3(0, 0, 1));

        auto vaoSpace = new Vertex[2 * gridW_ * (gridH_ + 1) +
                                   2 * gridH_ * (gridW_ + 1) +
                                   bottomLevelVertices_];
        gridVAO_ = new VAO!Vertex(gl_, vaoSpace);

        double x = 0.0;
        double y = 0.0;
        const white = rgb!"FFFFFF";
        foreach(xCell; 0 .. gridW_ + 1)
        {
            y = 0.0;
            foreach(yCell; 0 .. gridH_)
            {
                gridVAO_.put(Vertex(x, y, 10, white));
                gridVAO_.put(Vertex(x, y + cellSizeWorld_.y, 10, white));
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
                gridVAO_.put(Vertex(x, y, 10, white));
                gridVAO_.put(Vertex(x + cellSizeWorld_.x, y, 10, white));
                x += cellSizeWorld_.x;
            }
            y += cellSizeWorld_.y;
        }
        const bottomColor = rgb!"101008";
        gridVAO_.put(Vertex(0, 0, -10, bottomColor));
        gridVAO_.put(Vertex(cellSizeWorld_.x * gridW_, 0, -10, bottomColor));
        gridVAO_.put(Vertex(cellSizeWorld_.x * gridW_, cellSizeWorld_.y * gridH_, -10, bottomColor));
        gridVAO_.put(Vertex(cellSizeWorld_.x * gridW_, cellSizeWorld_.y * gridH_, -10, bottomColor));
        gridVAO_.put(Vertex(0, cellSizeWorld_.y * gridH_, -10, bottomColor));
        gridVAO_.put(Vertex(0, 0, -10, bottomColor));
        gridVAO_.lock();


        axisThingy_ = new VAO!Vertex(gl_, new Vertex[6]);

        axisThingy_.put(Vertex(10,  10,  10,  rgb!"FFFFFF"));
        axisThingy_.put(Vertex(110, 10,  10,  rgb!"FF0000"));
        axisThingy_.put(Vertex(10,  10,  10,  rgb!"FFFFFF"));

        axisThingy_.put(Vertex(10,  110, 10,  rgb!"00FF00"));
        axisThingy_.put(Vertex(10,  10,  10,  rgb!"FFFFFF"));
        axisThingy_.put(Vertex(10,  10,  110, rgb!"0000FF"));
        axisThingy_.lock();
        entitiesBatch_ = new VAO!Vertex(gl_, new Vertex[10000]);
    }

    /// Destroy the RenderProcess along with any rendering data.
    ~this()
    {
        if(program_ !is null) { program_.__dtor(); }
        entitiesBatch_.__dtor();
        axisThingy_.__dtor();
        gridVAO_.__dtor();
    }

    /// Draw anything that should be drawn before any entities.
    void preProcess() nothrow
    {
        //modelView_.rotate(-0.02, vec3(0, 0, 1));
        // This will still be called even if the program construction fails.
        if(program_ is null) { return; }

        scope(exit) { gl_.runtimeCheck(); }

        glEnable(GL_DEPTH_TEST);

        uniforms_.projection = projection_.top;
        uniforms_.modelView  = modelView_.top;
        program_.use();

        scope(exit) { program_.unuse(); }

        if(gridVAO_.bind(program_))
        {
            gridVAO_.draw(PrimitiveType.Lines, 0, gridVAO_.length - bottomLevelVertices_);
            gridVAO_.draw(PrimitiveType.Triangles, gridVAO_.length - bottomLevelVertices_,
                          bottomLevelVertices_);
            gridVAO_.release();
        }
        else { logVAOBindError("gridVAO_"); }

        if(axisThingy_.bind(program_))
        {
            axisThingy_.draw(PrimitiveType.Lines, 0, axisThingy_.length);
            axisThingy_.release();
        }
        else { logVAOBindError("axisThingy_"); }
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
            drawBatch();
        }

        foreach(i, v; positions)
        {
            entitiesBatch_.put(Vertex(v.x + pos.x, v.y + pos.y, v.z + pos.z,
                                      Color(vis.r, vis.g, vis.b, vis.a)));
        }
    }

    /// Draw all batched entities that have not yet been drawn.
    void postProcess() nothrow
    {
        if(!entitiesBatch_.empty) { drawBatch(); }
        glDisable(GL_DEPTH_TEST);
    }

private:

    /// Draw all entities batched so far.
    void drawBatch() @safe nothrow
    {
        scope(exit) { gl_.runtimeCheck(); }
        uniforms_.projection = projection_.top;
        uniforms_.modelView  = modelView_.top;

        program_.use();
        scope(exit) { program_.unuse(); }

        entitiesBatch_.lock();
        scope(exit)
        {
            entitiesBatch_.unlock();
            entitiesBatch_.clear();
        }

        if(entitiesBatch_.bind(program_))
        {
            entitiesBatch_.draw(PrimitiveType.Triangles, 0, entitiesBatch_.length);
            entitiesBatch_.release();
        }
        else { logVAOBindError("entitiesBatch_"); }
    }

    // Log an error after failing to bind VAO with specified name.
    void logVAOBindError(string name) @safe nothrow
    {
        log_.error("Failed to bind VAO \"%s\"; probably missing vertex attribute in a "
                  " GLSL program. Will not draw.").assumeWontThrow;
    }
}
