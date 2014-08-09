module gfmod.opengl.matrixstack;

import /*gfmod.core.memory,*/
       gfm.math.vector,
       gfm.math.matrix;

/// A matrix stack designed to replace fixed-pipeline matrix stacks.
/// This stack always expose both the top element and its inverse.
final class MatrixStack(size_t R, T) if (R == 3 || R == 4)
{
    public
    {
        alias Matrix!(T, R, R) matrix_t; /// Type of matrices in the stack. Can be 3x3 or 4x4.

        /// Creates a matrix stack.
        /// The stack is initialized with one element, an identity matrix.
        this(size_t depth = 32) nothrow
        {
            assert(depth > 0);
            size_t memNeeded = matrix_t.sizeof * depth * 2;
            //XXX TEMP - WILL RECEIVE DATA AS PARAM
            void* data = new void[memNeeded * 2]; // alignedMalloc(memNeeded * 2, 64);
            _matrices = cast(matrix_t*)data;
            _invMatrices = cast(matrix_t*)(data + memNeeded);
            _top = 0;
            _depth = depth;
            loadIdentity();
        }

        ~this()
        {
            close();
        }

        /// Releases the matrix stack memory.
        void close()
        {
            if (_matrices !is null)
            {
                //alignedFree(_matrices);
                _matrices = null;
            }
        }

        /// Replacement for $(D glLoadIdentity).
        void loadIdentity() pure nothrow
        {
            _matrices[_top] = mat4d.identity();
            _invMatrices[_top] = mat4d.identity();
        }

        /// Replacement for $(D glPushMatrix).
        void push() pure nothrow
        {
            if(_top + 1 >= _depth)
                assert(false, "Matrix stack is full");

            _matrices[_top + 1] = _matrices[_top];
            _invMatrices[_top + 1] = _invMatrices[_top];
            ++_top;
        }

        /// Replacement for $(D glPopMatrix).
        void pop() pure nothrow
        {
            if (_top <= 0)
                assert(false, "Matrix stack is empty");

            --_top;
        }

        /// Returns: Top matrix.
        /// Replaces $(D glLoadMatrix).
        matrix_t top() pure const nothrow
        {
            return _matrices[_top];
        }

        /// Returns: Inverse of top matrix.
        matrix_t invTop() pure const nothrow
        {
            return _invMatrices[_top];
        }

        /// Sets top matrix.
        /// Replaces $(D glLoadMatrix).
        void setTop(matrix_t m) pure nothrow
        {
            _matrices[_top] = m;
            _invMatrices[_top] = m.inverse();
        }

        /// Replacement for $(D glMultMatrix).
        void mult(matrix_t m) pure nothrow
        {
            mult(m, m.inverse());
        }

        /// Replacement for $(D glMultMatrix), with provided inverse.
        void mult(matrix_t m, matrix_t invM) pure nothrow
        {
            _matrices[_top] = _matrices[_top] * m;
            _invMatrices[_top] = invM *_invMatrices[_top];
        }

        /// Replacement for $(D glTranslate).
        void translate(Vector!(T, R-1) v) pure nothrow
        {
            mult(matrix_t.translation(v), matrix_t.translation(-v));
        }

        /// Replacement for $(D glScale).
        void scale(Vector!(T, R-1) v) pure nothrow
        {
            mult(matrix_t.scaling(v), matrix_t.scaling(1 / v));
        }

        static if (R == 4)
        {
            /// Replacement for $(D glRotate).
            /// Warning: Angle is given in radians, unlike the original API.
            void rotate(T angle, Vector!(T, 3u) axis) pure nothrow
            {
                matrix_t rot = matrix_t.rotation(angle, axis);
                mult(rot, rot.transposed()); // inversing a rotation matrix is tranposing
            }

            /// Replacement for $(D gluPerspective).
            /// Warning: FOV is given in radians, unlike the original API.
            void perspective(T FOVInRadians, T aspect, T zNear, T zFar) pure nothrow
            {
                mult(matrix_t.perspective(FOVInRadians, aspect, zNear, zFar));
            }

            /// Replacement for $(D glOrtho).
            void ortho(T left, T right, T bottom, T top, T near, T far) pure nothrow
            {
                mult(matrix_t.orthographic(left, right, bottom, top, near, far));
            }

            /// Replacement for $(D gluLookAt).
            void lookAt(vec3!T eye, vec3!T target, vec3!T up) pure nothrow
            {
                mult(matrix_t.lookAt(eye, target, up));
            }
        }
    }

    private
    {
        size_t _top; // index of top matrix
        size_t _depth;
        matrix_t* _matrices;
        matrix_t* _invMatrices;
    }
}

unittest
{
    auto s = new MatrixStack!(4u, double)();
    
    s.loadIdentity();
    s.push();
    s.pop();

    s.translate(vec3d(4,5,6));
    s.scale(vec3d(0.5));
}
