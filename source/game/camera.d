//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// 2D isometric camera.
module game.camera;


import gl3n_extra.linalg;
import gfmod.opengl.matrixstack;

import platform.inputdevice;


/** Controls the camera according to user input.
 *
 * Note that the camera should only be changed between frames, when Tharsis processes
 * are not running, as many processes have (const) access to camera.
 */
final class CameraControl
{
private:
    import time.gametime;
    // Game time (for time step).
    const(GameTime) time_;

    // Access to user input.
    const(InputDevice) input_;

    import std.experimental.logger;
    // Game log.
    Logger log_;

    // Isometric camera.
    Camera camera_;

    // Time in seconds the 'fast scroll' button (RMB by default) has been pressed for so far.
    double fastScrollPressedDuration_ = 0.0;

    // TODO: Params such as borderSize_, scrollSpeed_, zoomSpeedBase_,
    //                      fastScrollTriggerTime_, fastScrollSpeed_ should be loaded
    //       from YAML 2014-08-21
    /* Size of the border for moving the camera.
     *
     * (If the cursor is within this border, the camera is moved)
     */
    size_t borderSize_ = 24;

    // Camera movement speed in pixels per second.
    double scrollSpeed_ = 1024.0;

    // Base for zooming speed (zooming is exponential, this is base for that exponent).
    double zoomSpeedBase_ = 512.0;

    // Time the 'fast scroll trigger' (RMB by default) must be held for fast scroll to kick in.
    double fastScrollTriggerTime_ = 0.12;

    // Speed of fast scrolling
    double fastScrollSpeed_ = 8192.0;

public:
    /** Construct a CameraControl.
     *
     * Params:
     *
     * time   = Game time (for time step).
     * input  = Access to user input.
     * camera = Isometric camera.
     * log    = Game log.
     */
    this(const(GameTime) time, const(InputDevice) input, Camera camera, Logger log)
        @safe pure nothrow @nogc
    {
        time_   = time;
        input_  = input;
        camera_ = camera;
        log_    = log;
    }

    /// Update the camera based on user input.
    void update() @safe nothrow
    {
        import std.exception;
        vec2 center    = camera_.center;
        const zoom     = camera_.zoom;
        auto mouse     = input_.mouse;
        auto keyboard  = input_.keyboard;
        const timeStep = time_.timeStep;
        const scrollSpeed = (scrollSpeed_ / zoom) * timeStep;
        const rightBorder = camera_.width_ - borderSize_;
        const topBorder   = camera_.height_ - borderSize_;

        // Conventional scrolling by moving mouse to window border.
        if(mouse.x < borderSize_ || keyboard.key(Key.A)) { center.x -= scrollSpeed; }
        if(mouse.x > rightBorder || keyboard.key(Key.D)) { center.x += scrollSpeed; }
        if(mouse.y < borderSize_ || keyboard.key(Key.S)) { center.y -= scrollSpeed; }
        if(mouse.y > topBorder   || keyboard.key(Key.W)) { center.y += scrollSpeed; }

        // Fast scrolling by dragging RMB.
        fastScrollPressedDuration_ = mouse.button(Mouse.Button.Right)
                                   ? fastScrollPressedDuration_ + timeStep : 0.0;
        if(fastScrollPressedDuration_ >= fastScrollTriggerTime_)
        {
            const fastScrollSpeed = (fastScrollSpeed_ / zoom) * timeStep;
            import std.math;
            center += vec2(mouse.xMovement.sgn * fastScrollSpeed,
                           mouse.yMovement.sgn * fastScrollSpeed);
        }

        // Apply the new camera position.
        camera_.center = center;

        // Zooming.
        const wheelMovement = mouse.wheelYMovement;
        camera_.zoom = zoom * (zoomSpeedBase_ ^^ (timeStep * wheelMovement));

        // TODO: Make zooming work like other RTS'ses: Wheel movement will trigger a
        //       gradual speed up-slow down zoom effect that will last multiple frames
        //       and end up at a discrete zoom level (e.g. 1.5 times the old zoom). 2014-08-21

        // TODO: Zoom towards the mouse cursor. This will require world coords of the
        //       cursor, or rather, of the entity/tile under the cursor. We can get that 
        //       through a const deleg that will ask PickingProcess, SpatialSystem or
        //       whatever will handle this - but without affecting that whatever. 2014-08-21
    }
}

/// 2D isometric camera.
final class Camera
{
private:
    // TODO: Pushing/popping camera state can be added when needed since we use
    //       MatrixStack 2014-08-17

    // Orthographic matrix stack (moved to position, but no zoom).
    MatrixStack!(float, 4) orthoStack_;

    // Projection matrix stack (ortho + zoom).
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
        orthoStack_      = new MatrixStack!(float, 4)();
        projectionStack_ = new MatrixStack!(float, 4)();
        viewStack_       = new MatrixStack!(float, 4)();
        updateProjection();
        updateView();
    }

@nogc:
    /** Get the current plain ortho matrix.
     *
     * Useful to transform e.g. UI elements in non-zoomed 2D space.
     */
    mat4 ortho() const { return orthoStack_.top; }

    /// Get the current projection (ortho + zoom) matrix.
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
        updateProjection();
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
        updateProjection();
    }

    /// Set camera size in pixels. Both width and height must be greater than zero.
    void size(size_t width, size_t height)
    {
        assert(width > 0 && height > 0, "Can't have camera width/height of 0");
        width_  = width;
        height_ = height;
        updateProjection();
    }

    /// Get screen coordinates (in pixels) corresponding to 3D point in world space.
    vec2 worldToScreen(vec3 world) const
    {
        const halfSize = vec2(width_ / 2, height_ / 2);
        // transform to 2D space, then subtract the center
        return zoom_ * (vec2(view * vec4(world, 1.0f)) - vec2(center)) + halfSize;
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
        return vec3(viewStack_.invTop * vec4(((screen - halfSize) * invZoom + center), 1.0f));
    }

    /// Transform a screen position to ortho (projection with no zoom) coordinates.
    vec2 screenToOrtho(vec2 screen) const
    {
        const halfSize = vec2(width_ / 2, height_ / 2);
        return (screen - halfSize) + center_;
    }

private:
    /// Update the orthographic projection matrix.
    void updateProjection()
    {
        const hWidth  = max(width_  * 0.5f, 1.0f);
        const hHeight = max(height_ * 0.5f, 1.0f);
        orthoStack_.loadIdentity();
        orthoStack_.ortho(center_.x - hWidth, center_.x + hWidth,
                          center_.y - hHeight, center_.y + hHeight, -8000, 8000);
        const invZoom = 1.0 / zoom_;
        projectionStack_.loadIdentity();
        projectionStack_.setTop(orthoStack_.top);
        projectionStack_.translate(vec3(center_, 0.0f));
        projectionStack_.scale(zoom_, zoom_, zoom_);
        projectionStack_.translate(vec3(-center_, 0.0f));
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
