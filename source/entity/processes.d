//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Processes operating on entities in the game.
module entity.processes;


import std.exception;
import std.logger;

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

        in vec3 position;

        void main()
        {
            gl_Position = vec4(position, 1.0);
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

    // VAO storing the map grid.
    VAO!Vertex gridVAO_;

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
        }
        catch(OpenGLException e)
        {
            log_.error("Failed to construct the main GLSL program."
                       "Will run without drawing graphics.").assumeWontThrow;
            program_ = null;
        }
        catch(Exception e)
        {
            assert(false, "Unexpected exception in mainLoop()");
        }

        auto vaoSpace = new Vertex[3];
        gridVAO_ = new VAO!Vertex(gl_, vaoSpace);

        gridVAO_.put(Vertex(-1, -1,  0));
        gridVAO_.put(Vertex( 1, -1,  0));
        gridVAO_.put(Vertex( 0,  1,  0));
        gridVAO_.lock();
    }

    /// Destroy the RenderProcess along with any rendering data.
    ~this()
    {
        program_.__dtor();
        gridVAO_.__dtor();
    }

    /// Draw anything that should be drawn before any entities.
    void preProcess() nothrow
    {
        // This will still be called even if the program construction fails.
        if(program_ is null) { return; }

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

        //glDrawArrays(GL_TRIANGLES, 0, 3);
        gridVAO_.draw(PrimitiveType.Triangles, 0, 3);
    }

    /// Draw an entity with specified position and visual.
    void process(ref const PositionComponent position,
                 ref const VisualComponent visual) @safe nothrow
    {
        // TODO: Do this once we have a grid. 2014-08-12
    }
}
