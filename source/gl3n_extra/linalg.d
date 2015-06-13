//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Functionality extending gl3n.linalg
module gl3n_extra.linalg;

public import gl3n.linalg;


/// Readability shortcuts.
alias Vector!(uint, 2) vec2u;
alias Vector!(uint, 3) vec3u;
alias Vector!(uint, 4) vec4u;
alias Vector!(ubyte, 2) vec2ub;
alias Vector!(ubyte, 3) vec3ub;
alias Vector!(ubyte, 4) vec4ub;
alias Matrix!(float, 3, 2) mat32;
alias Matrix!(float, 4, 2) mat42;
alias Matrix!(float, 2, 3) mat23;
alias Matrix!(float, 4, 3) mat43;
alias Matrix!(float, 2, 4) mat24;
alias Matrix!(double, 2, 2) mat2d;
alias Matrix!(double, 3, 3) mat3d;
alias Matrix!(double, 4, 4) mat4d;
alias Matrix!(double, 3, 2) mat32d;
alias Matrix!(double, 4, 2) mat42d;
alias Matrix!(double, 2, 3) mat23d;
alias Matrix!(double, 4, 3) mat43d;
alias Matrix!(double, 2, 4) mat24d;
alias Matrix!(double, 3, 4) mat34d;

// Called setLength() because length() doesn't seem to work correctly with UFCS.
/// Set length of the vector, resizing it but preserving its direction.
void setLength(T, size_t dim)(ref Vector!(T, dim) vector, T length) @safe pure nothrow @nogc
{
    const oldLength = vector.length;
    assert(oldLength != 0.0f, "Cannot set length of a zero vector!");
    const ratio = length / oldLength;
    vector *= ratio;
}

/** Optimized multiplication of a 3D vector by a 4x4 matrix *from the left* that returns a 2D vector.
 *
 * Reduces the number of additions from 16 to 8 and the number of multiplications from
 * 16 to 6.
 */
Vector!(T, 2) matMulTo2D(T)(auto ref const Matrix!(T, 4, 4) m, const Vector!(T, 3) v)
    @safe pure nothrow @nogc
{
    // Vector!(T, 2) ret;
    // ret.clear(0);

    Vector!(T, 2) ret = void;
    ret.vector[0] = 0.0f;
    ret.vector[1] = 0.0f;
    foreach(c; TupleRange!(0, 3)) 
    {
        foreach(r; TupleRange!(0, 2)) 
        {
            ret.vector[r] += m[r][c] * v.vector[c];
        }
    }

    foreach(r; TupleRange!(0, 2)) 
    {
        ret.vector[r] += m[r][3]; // * 1.0
    }
    return ret;
}

/** Get the angle (radians) between two points on a unit sphere (unit vectors).
 */
T angleBetweenPointsOnSphere(T)(const Vector!(T, 3) a, const Vector!(T, 3) b)
    @safe pure nothrow @nogc 
out(result)
{
    assert(!result.isNaN, 
            "angleBetweenPointsOnSphere result is NaN: probably >1 or <-1 passed to acos");
}
body
{
    import std.math: acos, abs;
    assert(abs(a.magnitude_squared - 1.0) < 0.001, 
            "(a) points on sphere must be unit vectors");
    assert(abs(b.magnitude_squared - 1.0) < 0.001, 
            "(b) points on sphere must be unit vectors");
    //TODO: check if there are any edge cases where acos would return nan
    //here (is the dot product ever >1 or <-1?)
    return acos(a.dot(b));
}

/// Convert an angle in radians to degrees.
F radToDeg(F)(F a) @safe pure nothrow @nogc 
{
    import std.math: PI;
    return (a / PI) * 180.0;
}

/** Linear interpolation between facings (unit direction vectors).
 *
 * Params:
 *
 * from  = Unit vector we're interpolating from.
 * to    = Unit vector we're interpolating to.
 * ratio = Interpolation ratio; 0 means the result is `from`, 1 is `to`,
 *         0.5 is the direction halfway between `from` and `to`.
 */
Vector!(T, dim) slerp(T, int dim)(const Vector!(T, dim) from, 
                                  const Vector!(T, dim) to, const T ratio) 
    @safe pure nothrow @nogc 
{
    import std.math: abs;
    assert(abs(from.magnitude_squared - 1.0) < 0.001, 
            "(from) directions must be unit vectors");
    assert(abs(to.magnitude_squared - 1.0) < 0.001, 
            "(to) directions must be unit vectors");
    assert(ratio >= 0.0 && ratio <= 1.0, "slerp ratio out of range");
    return (from * ratio + to * (1.0 - ratio)).normalized;
}
