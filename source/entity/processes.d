//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Processes operating on entities in the game.
module entity.processes;


import std.exception;
import std.logger;

import gfmod.opengl.matrixstack;
import gfmod.opengl.opengl;
import gfmod.opengl.program;
import gfmod.opengl.vao;

import gl3n.linalg;

import entity.components;
import platform.videodevice;



/// Handles rendering of VisualComponents.
class RenderProcess
{
private:
    // A simple 3D vertex.
    struct Vertex
    {
        // Position of the vertex.
        vec3 position;

        // Shortcut constructor.
        this(float x, float y, float z) @safe pure nothrow @nogc { position = vec3(x, y, z); }
    }

    // Source of the shader used for drawing.
    enum shaderSrc =
      q{#version 130

        #if VERTEX_SHADER

        uniform mat4 projection;
        in vec3 position;

        void main()
        {
            gl_Position = projection * vec4(position, 1.0);
        }

        #elif FRAGMENT_SHADER

        out vec4 color;
        void main()
        {
            color = vec4(0,1,1,1);
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
    }

    import gfmod.opengl.uniform;
    // Provides access to uniform variables in program_.
    GLUniforms!UniformsSpec uniforms_;

    // VAO storing the map grid.
    VAO!Vertex gridVAO_;


    // Projection matrix stack.
    MatrixStack!(4, float) projection_;

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
        projection_ = new MatrixStack!(4, float)(4);
        const w = video.width;
        const h = video.height;
        projection_.ortho(-w / 2, w / 2, -h / 2, h / 2, -1, 2000);

        auto vaoSpace = new Vertex[3];
        gridVAO_ = new VAO!Vertex(gl_, vaoSpace);

        gridVAO_.put(Vertex(-100, -100,  10));
        gridVAO_.put(Vertex( 100, -100,  10));
        gridVAO_.put(Vertex( 0,    100,  10));
        gridVAO_.lock();
    }

    /// Destroy the RenderProcess along with any rendering data.
    ~this()
    {
        if(program_ !is null) { program_.__dtor(); }
        gridVAO_.__dtor();
    }

    /// Draw anything that should be drawn before any entities.
    void preProcess() nothrow
    {
        // This will still be called even if the program construction fails.
        if(program_ is null) { return; }

        uniforms_.projection = projection_.top;
        program_.use();

        scope(exit) { program_.unuse(); }

        if(!gridVAO_.bind(program_))
        {
            log_.error("Failed to bind VAO; probably missing vertex attribute "
                       " in a GLSL program. Will not draw.").assumeWontThrow;
            return;
        }
        scope(exit) { gridVAO_.release(); }
        gl_.runtimeCheck();

        gridVAO_.draw(PrimitiveType.Triangles, 0, 3);
    }

    /// Draw an entity with specified position and visual.
    void process(ref const PositionComponent position,
                 ref const VisualComponent visual) @safe nothrow
    {
        // TODO: Do this once we have a grid. 2014-08-12
    }
}
