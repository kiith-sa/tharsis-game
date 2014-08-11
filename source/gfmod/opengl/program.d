module gfmod.opengl.program;

import core.stdc.string;

import std.conv, 
       std.exception,
       std.string, 
       std.regex, 
       std.algorithm;

import derelict.opengl3.gl3;

import /*gfmod.core.log,*/
       gfmod.core.text,
       gfm.math.vector, 
       gfm.math.matrix,
       gfmod.opengl.opengl, 
       gfmod.opengl.shader, 
       gfmod.opengl.uniform,
       gfmod.opengl.uniformblock;

/// OpenGL Program wrapper.
final class GLProgram
{
    public
    {
        /// Creates an empty program.
        /// Throws: $(D OpenGLException) on error.
        this(OpenGL gl)
        {
            _gl = gl;
            _program = glCreateProgram();
            if (_program == 0)
                throw new OpenGLException("glCreateProgram failed");
            _initialized = true;
        }

        /// Creates a program from a set of compiled shaders.
        /// Throws: $(D OpenGLException) on error.
        this(OpenGL gl, GLShader[] shaders...)
        {
            this(gl);
            attach(shaders);
            link();
        }

        /**
         * Compiles N times the same GLSL source and link to a program.
         * 
         * <p>
         * The same input is compiled 1 to 5 times, each time prepended
         * with a $(D #define) specific to a shader type.
         * </p>
         * $(UL
         *    $(LI $(D VERTEX_SHADER))
         *    $(LI $(D FRAGMENT_SHADER))
         *    $(LI $(D GEOMETRY_SHADER))
         *    $(LI $(D TESS_CONTROL_SHADER))
         *    $(LI $(D TESS_EVALUATION_SHADER))
         * )
         * <p>
         * Each of these macros are alternatively set to 1 while the others are
         * set to 0. If such a macro isn't used in any preprocessor directive 
         * of your source, this shader stage is considered unused.</p>
         *
         * <p>For conformance reasons, any #version directive on the first line will stay at the top.</p>
         * 
         * Warning: <b>THIS FUNCTION REWRITES YOUR SHADER A BIT.</b>
         * Expect slightly wrong lines in GLSL compiler's error messages.
         *
         * Example of a combined shader source:
         * ---
         *      #version 110
         *      uniform vec4 color;
         *
         *      #if VERTEX_SHADER
         *
         *      void main()
         *      {
         *          gl_Vertex = ftransform();
         *      }
         *      
         *      #elif FRAGMENT_SHADER
         *      
         *      void main()
         *      {
         *          gl_FragColor = color;
         *      }
         *      
         *      #endif
         * ---
         *
         * Limitations:
         * $(UL
         *   $(LI All of #preprocessor directives should not have whitespaces before the #.)
         *   $(LI sourceLines elements should be individual lines!)
         * )
         *
         * Throws: $(D OpenGLException) on error.
         */
        this(OpenGL gl, string[] sourceLines)
        {
            _gl = gl;
            bool present[5];
            enum string[5] defines = 
            [ 
              "VERTEX_SHADER",
              "FRAGMENT_SHADER",
              "GEOMETRY_SHADER",
              "TESS_CONTROL_SHADER",
              "TESS_EVALUATION_SHADER"
            ];

            enum GLenum[5] shaderTypes =
            [ 
                GL_VERTEX_SHADER,
                GL_FRAGMENT_SHADER,
                GL_GEOMETRY_SHADER,
                GL_TESS_CONTROL_SHADER,
                GL_TESS_EVALUATION_SHADER
            ];

            // from GLSL spec: "Each number sign (#) can be preceded in its line only by 
            //                  spaces or horizontal tabs."
            enum directiveRegexp = ctRegex!(r"^[ \t]*#");
            enum versionRegexp = ctRegex!(r"^[ \t]*#[ \t]*version");

            present[] = false;
            int versionLine = -1;

            // scan source for #version and usage of shader macros in preprocessor lines
            foreach(int lineIndex, string line; sourceLines)
            {
                // if the line is a preprocessor directive
                if (match(line, directiveRegexp))
                {
                    foreach (int i, string define; defines)
                        if (!present[i] && countUntil(line, define) != -1)
                            present[i] = true;
                   
                    if (match(line, versionRegexp))
                    {
                        if (versionLine != -1)
                        {
                            string message = "Your shader program has several #version directives, you are looking for problems.";
                            debug
                                throw new OpenGLException(message);
                            else
                                gl._logger.warning(message);
                        }
                        else
                        {
                            if (lineIndex != 0)
                                gl._logger.warning("For maximum compatibility, #version directive should be the first line of your shader.");

                            versionLine = lineIndex;
                        }
                    }
                }
            }

            GLShader[] shaders;

            foreach (int i, string define; defines)
            {
                if (present[i])
                {
                    string[] newSource;

                    // add #version line
                    if (versionLine != -1)
                        newSource ~= sourceLines[versionLine];

                    // add each #define with the right value
                    foreach (int j, string define2; defines)
                        if (present[j])
                            newSource ~= format("#define %s %d\n", define2, i == j ? 1 : 0);

                    // add all lines except the #version one
                    foreach (int l, string line; sourceLines)
                        if (l != versionLine)
                            newSource ~= line;

                    shaders ~= new GLShader(_gl, shaderTypes[i], newSource);
                }
            }
            this(gl, shaders);
        }

        /// Ditto, except with lines in a single string.
        this(OpenGL gl, string wholeSource)
        {
            // split on end-of-lines
            this(gl, splitLines(wholeSource));
        }

        ~this()
        {
            close();
        }

        /// Releases the OpenGL program resource.
        void close()
        {
            if (_initialized)
            {
                glDeleteProgram(_program);
                _initialized = false;
            }
        }

        /// Attaches OpenGL shaders to this program.
        /// Throws: $(D OpenGLException) on error.
        void attach(GLShader[] compiledShaders...)
        {
            foreach(shader; compiledShaders)
            {
                glAttachShader(_program, shader._shader);
                _gl.runtimeCheck();
            }
        }

        /// Links this OpenGL program.
        /// Throws: $(D OpenGLException) on error.
        void link()
        {
            glLinkProgram(_program);
            _gl.runtimeCheck();
            GLint res;
            glGetProgramiv(_program, GL_LINK_STATUS, &res);
            if (GL_TRUE != res)
            {
                string linkLog = getLinkLog();
                if (linkLog != null)
                    _gl._logger.errorf("%s", linkLog);
                throw new OpenGLException("Cannot link program");
            }

            // When getting uniform and attribute names, add some length because of stories like this:
            // http://stackoverflow.com/questions/12555165/incorrect-value-from-glgetprogramivprogram-gl-active-uniform-max-length-outpa
            enum SAFETY_SPACE = 128;

            // get active uniforms
            {
                GLint uniformNameMaxLength;
                glGetProgramiv(_program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &uniformNameMaxLength);

                    //XXX STACK BUF
                    //XXX AND ADD A TODO TO REUSE SOURCE CODE SPACE FOR ALLOCATION
                GLchar[] buffer = new GLchar[uniformNameMaxLength + SAFETY_SPACE];

                GLint numActiveUniforms;
                glGetProgramiv(_program, GL_ACTIVE_UNIFORMS, &numActiveUniforms);

                // get uniform block indices (if > 0, it's a block uniform)
                GLuint[] uniformIndex;
                GLint[] blockIndex;
                uniformIndex.length = numActiveUniforms;
                blockIndex.length = numActiveUniforms;

                for (GLint i = 0; i < numActiveUniforms; ++i)
                    uniformIndex[i] = cast(GLuint)i;

                glGetActiveUniformsiv( _program,
                                       cast(GLint)uniformIndex.length,
                                       uniformIndex.ptr,
                                       GL_UNIFORM_BLOCK_INDEX,
                                       blockIndex.ptr);
                _gl.runtimeCheck();

                // get active uniform blocks
                getUniformBlocks(_gl, this);

                for (GLint i = 0; i < numActiveUniforms; ++i)
                {
                    if(blockIndex[i] >= 0)
                        continue;

                    GLint size;
                    GLenum type;
                    GLsizei length;
                    glGetActiveUniform(_program,
                                       cast(GLuint)i,
                                       cast(GLint)(buffer.length),
                                       &length,
                                       &size,
                                       &type,
                                       buffer.ptr);
                    _gl.runtimeCheck();

                    auto name = buffer[0 .. strlen(buffer.ptr)].dup;
                    if(!name.sanitizeASCIIInPlace())
                    {
                        _gl._logger.warning("Invalid (non-ASCII) character in GL uniform name");
                    }

                    _activeUniforms[name.assumeUnique] = new GLUniform(_gl, _program, type, name, size);
                }
            }

            // get active attributes
            {
                GLint attribNameMaxLength;
                glGetProgramiv(_program, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, &attribNameMaxLength);

                    //XXX STACK BUF
                GLchar[] buffer = new GLchar[attribNameMaxLength + SAFETY_SPACE];

                GLint numActiveAttribs;
                glGetProgramiv(_program, GL_ACTIVE_ATTRIBUTES, &numActiveAttribs);

                for (GLint i = 0; i < numActiveAttribs; ++i)
                {
                    GLint size;
                    GLenum type;
                    GLsizei length;
                    glGetActiveAttrib(_program, cast(GLuint)i, cast(GLint)(buffer.length), &length, &size, &type, buffer.ptr);                    
                    _gl.runtimeCheck();

                    auto name = buffer[0 .. strlen(buffer.ptr)].dup;
                    if(!name.sanitizeASCIIInPlace())
                    {
                        _gl._logger.warning("Invalid (non-ASCII) character in GL attribute name");
                    }

                    GLint location = glGetAttribLocation(_program, buffer.ptr);
                    _gl.runtimeCheck();

                    _activeAttributes[name.assumeUnique] = new GLAttribute(_gl, name, location, type, size);
                }
            }

        }

        /// Uses this program for following draw calls.
        /// Throws: $(D OpenGLException) on error.
        void use()
        {
            glUseProgram(_program);
            _gl.runtimeCheck();

            // upload uniform values then
            // this allow setting uniform at anytime without binding the program
            foreach(uniform; _activeUniforms)
                uniform.use();
        }

        /// Unuses this program.
        /// Throws: $(D OpenGLException) on error.
        void unuse()
        {
            foreach(uniform; _activeUniforms)
                uniform.unuse();
            glUseProgram(0);
            _gl.runtimeCheck();
        }

        /// Gets the linking report.
        /// Returns: Log output of the GLSL linker. Can return null!
        /// Throws: $(D OpenGLException) on error.
        string getLinkLog()
        {
            GLint logLength;
            glGetProgramiv(_program, GL_INFO_LOG_LENGTH, &logLength);
            if (logLength <= 0) // " If program has no information log, a value of 0 is returned."
                return null;

            char[] log = new char[logLength];
            GLint dummy;
            glGetProgramInfoLog(_program, logLength, &dummy, log.ptr);
            _gl.runtimeCheck();

            if(!log.sanitizeASCIIInPlace())
            {
                _gl._logger.warning("Invalid (non-ASCII) character in GL shader link log");
            }
            return log.assumeUnique;
        }

        /// Gets an uniform by name.
        /// Returns: A GLUniform with this name. This GLUniform might be created on demand if
        ///          the name hasn't been found. So it might be a "fake" uniform.
        /// See_also: GLUniform.
        GLUniform uniform(string name)
        {
            GLUniform* u = name in _activeUniforms;

            if (u is null)
            {
                // no such variable found, either it's really missing or the OpenGL driver discarded an unused uniform
                // create a fake disabled GLUniform to allow the show to proceed
                _gl._logger.warningf("Faking uniform variable '%s'", name);
                _activeUniforms[name] = new GLUniform(_gl, name);
                return _activeUniforms[name];
            }
            return *u;
        }

        /// Gets an attribute by name.
        /// Returns: A $(D GLAttribute) retrieved by name.
        /// Throws: $(D OpenGLException) on error.
        GLAttribute attrib(string name)
        {
            GLAttribute* a = name in _activeAttributes;
            if (a is null)
                throw new OpenGLException(format("Attribute %s is unknown", name));
            return *a;
        }

        /// Returns: Wrapped OpenGL resource handle.
        GLuint handle() pure const nothrow
        {
            return _program;
        }
    }

    private
    {
        OpenGL _gl;
        GLuint _program; // OpenGL handle
        bool _initialized;
        GLUniform[string] _activeUniforms;
        GLAttribute[string] _activeAttributes;
    }
}


/// Represent an OpenGL program attribute. Owned by a GLProgram.
/// See_also: GLProgram.
struct GLAttribute
{
    @safe pure nothrow:
    public
    {
        this(char[] name, GLint location, GLenum type, GLsizei size)
        {
            _name = name.dup;
            _location = location;
            _type = type;
            _size = size;
        }

        GLint location() const @nogc { return _location; }
    }

    private
    {
        GLint _location;
        GLenum _type;
        GLsizei _size;
        //XXX fixed-size
        string _name;
    }
}
