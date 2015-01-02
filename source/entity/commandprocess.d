//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Process that assigns commands (e.g. move to point) to individual entities.
module entity.commandprocess;


import std.exception;
import std.experimental.logger;

import gl3n_extra.linalg;

import entity.components;
import game.camera;


/// Process that assigns commands (e.g. move to point) to individual entities.
final class CommandProcess
{
private:
    // Game log.
    Logger log_;

    import platform.inputdevice;
    // Access to mouse input.
    const(Mouse) mouse_;
    // Access to keyboard input.
    const(Keyboard) keyboard_;
    // Camera to transform mouse coords to world space.
    const(Camera) camera_;

    // If true, there is no command for selected units this frame.
    bool noCommandForSelected_ = true;

    // Command we're about to give to selected entities.
    CommandComponent commandForSelected_;

    // TODO: closeEnough should be in YAML for CommandProcess 2014-08-20
    // If an entity with a MoveTo command is at least this close to its target, there's
    // no need to continue moving.
    enum closeEnough = 67.0f;

public:
    alias FutureComponent = CommandComponent;

    /** Construct a CommandProcess.
     *
     * Params:
     *
     * mouse  = Access to mouse input.
     * camera = Camera to transform mouse coords to world space.
     * log    = Game log.
     */
    this(const(Mouse) mouse, const(Keyboard) keyboard, const(Camera) camera, Logger log)
        @safe pure nothrow @nogc
    {
        log_      = log;
        mouse_    = mouse;
        keyboard_ = keyboard;
        camera_   = camera;
    }

    /// Determine which commands to give this frame.
    void preProcess() nothrow
    {
        noCommandForSelected_ = true;
        immutable mousePos = vec2(mouse_.x, mouse_.y);

        /* Get the point on the map where the mouse cursor points.
         *
         * Writes the point to mapPoint. Returns false if there is no such point, true
         * otherwise.
         */
        bool mouseOnMap(out vec3 mapPoint) @safe pure nothrow @nogc
        {
            import gl3n_extra.plane;
            // For now we assume the map is one big flat plane.
            const mapPlane = planeFromPointNormal(vec3(0, 0, 0), vec3(0, 0, 1));

            // Create a line in world space from a point on the screen.
            const linePoint1 = camera_.screenToWorld(vec3(mousePos, 0.0f));
            const linePoint2 = camera_.screenToWorld(vec3(mousePos, -100.0f));
            const lineVector = linePoint2 - linePoint1;

            // Intersect the line with the map to find the point where the mouse id.
            return mapPlane.intersectsLine(linePoint1, lineVector, mapPoint);

            // TODO: Once we have terrain, we'll need to generate the 'walkability' map
            // and intersect with that. 2014-08-21
            // TODO: Once we have a walkability map, use flow fields for pathfinding. 2014-08-19
        }

        // Right click means 'move to' by default, 'fire at without moving' if ctrl is
        // pressed (Of course this will change later as commands get more advanced).
        vec3 mapPoint;
        if(mouse_.clicked(Mouse.Button.Right) && mouseOnMap(mapPoint))
        {
            noCommandForSelected_ = false;
            if(keyboard_.key(Key.LCtrl))
            {
                commandForSelected_.type         = CommandComponent.Type.StaticFireAt;
                commandForSelected_.staticFireAt = mapPoint;
            }
            else
            {
                commandForSelected_.type   = CommandComponent.Type.MoveTo;
                commandForSelected_.moveTo = mapPoint;
            }
        }
    }

    // TODO: In future there will be other sources of commands than just mouse
    //       (AI, map scripts, waypoints, etc.) 2014-08-21
    /** Add a command component to an entity that doesn't have one.
     *
     * We only give movement commands to entities that have engines.
     */
    void process(ref const PositionComponent pos,
                 ref const SelectionComponent select,
                 ref const EngineComponent engine,
                 ref CommandComponent* command) nothrow
    {
        if(noCommandForSelected_)
        {
            command = null;
            return;
        }
        *command = commandForSelected_;
    }

    /// Update (or cancel) command of an entity that already has a command assigned.
    void process(ref const PositionComponent pos,
                 ref const CommandComponent commandPast,
                 ref CommandComponent* commandFuture) nothrow
    {
        with(CommandComponent.Type) final switch(commandPast.type)
        {
            case MoveTo:
                if(distance(commandPast.moveTo, pos) < closeEnough)
                {
                    commandFuture = null;
                    break;
                }
                *commandFuture = commandPast;
                break;
            case StaticFireAt:
                *commandFuture = commandPast;
                break;
        }
    }

    /// Handle an entity that is both selected and has a command already.
    void process(ref const PositionComponent pos,
                 ref const SelectionComponent select,
                 ref const EngineComponent engine,
                 ref const CommandComponent commandPast,
                 ref CommandComponent* commandFuture) nothrow
    {
        noCommandForSelected_ ? process(pos, commandPast, commandFuture)
                              : process(pos, select, engine, commandFuture);
    }
}
