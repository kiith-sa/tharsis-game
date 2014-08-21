//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// 2D isometric camera.
module game.camera;


import gl3n_extra.linalg;
import gfmod.opengl.matrixstack;

import platform.videodevice;


/// 2D isometric camera.
final class Camera
{
private:
    // TODO: Pushing/popping camera state can be added when needed since we use
    //       MatrixStack 2014-08-17

    // Orthographic projection matrix stack.
    MatrixStack!(float, 4) projectionStack_;

    // View matrix stack.
    MatrixStack!(float, 4) viewStack_;

    // Camera width and height (2D extents of the camera). Signed to avoid issues with
    // negative values.
    long width_, height_;
    // Center of the camera (the point the camera is looking at in 2D space).
    vec2 center_;
    // Zoom of the camera (higher is closer).
    double zoom_ = 1.0f;

public:
@safe pure nothrow:
    /// Construct a Camera with specified window size.
    ///
    /// Params:
    ///
    /// width  = Camera width in pixels.
    /// height = Camera height in pixels.
    this(size_t width, size_t height)
    {
        width_  = width;
        height_ = height;
        center_ = vec2(0.0f, 0.0f);
        projectionStack_ = new MatrixStack!(float, 4)();
        viewStack_       = new MatrixStack!(float, 4)();
        updateOrtho();
        updateView();
    }

@nogc:
    /// Get the current projection matrix.
    mat4 projection() const { return projectionStack_.top; }

    /// Get the current view matrix.
    mat4 view() const { return viewStack_.top; }

    /// Get the center of the camera (the point the camera is looking at).
    vec2 center() const { return center_; }

    /// Get camera zoom.
    double zoom() @safe pure nothrow const @nogc { return zoom_; }

    /// Set the center of the camera (the point the camera is looking at).
    void center(const vec2 rhs)
    {
        center_ = rhs;
        updateOrtho();
    }

    /** Set camera zoom.
     *
     * Values over 1 result in magnified view. Values between 0 and 1 result in minified
     * (more distant) view. Must be greater than zero.
     */
    void zoom(double rhs)
    {
        assert(rhs > 0.0, "Zoom must be greater than zero");
        zoom_ = rhs;
        updateOrtho();
    }

    /// Set camera size in pixels. Both width and height must be greater than zero.
    void size(size_t width, size_t height)
    {
        assert(width > 0 && height > 0, "Can't have camera width/height of 0");
        width_  = width;
        height_ = height;
        updateOrtho();
    }

    /// Get screen coordinates (in pixels) corresponding to 3D point in world space.
    vec2 worldToScreen(vec3 world) const
    {
        const halfSize = vec2(width_ / 2, height_ / 2);
        // transform to 2D space, then subtract the center
        return zoom_ * (vec2(view * vec4(world, 1.0f)) - vec2(center) + halfSize);
    }

    /** Get world coordinates corresponding to a 3D point in screen space.
     *
     * Need full 3D not just X and Y, as a 2D point in screen space would correspond
     * to a line in world space.
     */
    vec3 screenToWorld(vec3 screen) const
    {
        const invZoom  = 1.0 / zoom_;
        const center   = vec3(center_, 0.0f);
        const halfSize = vec3(width_ / 2, height_ / 2, 0.0f);
        return vec3(viewStack_.invTop * vec4((screen * invZoom - halfSize + center), 1.0f));
    }

private:
    /// Update the orthographic projection matrix.
    void updateOrtho()
    {
        // Ensure we don't reach 0.
        const invZoom = 1.0 / zoom_;
        const hWidth  = max(width_  * 0.5f * invZoom, 1.0f);
        const hHeight = max(height_ * 0.5f * invZoom, 1.0f);
        projectionStack_.loadIdentity();
        projectionStack_.ortho(center_.x - hWidth, center_.x + hWidth,
                               center_.y - hHeight, center_.y + hHeight, -8000, 8000);
    }

    /// Update the view matrix.
    void updateView()
    {
        viewStack_.loadIdentity();
        // 60deg around X to get a view 'from a high point'
        viewStack_.rotate(PI / 2 - (PI / 6), vec3(1, 0, 0));
        // 45deg around Z to get a view 'from the corner'
        viewStack_.rotate(PI / 4, vec3(0, 0, 1));
    }
}
