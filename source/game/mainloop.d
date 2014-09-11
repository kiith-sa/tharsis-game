//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Main event loop of the game.
module game.mainloop;

import std.exception;
import std.logger;

import game.camera;
import entity.entitysystem;
import platform.inputdevice;
import platform.videodevice;
import time.gametime;


/// Main event loop of the game.
///
/// Params:
///
/// entitySystem  = EntitySystem holding all the Processes in the game.
/// videoDevice   = The video device used for graphics and windowing operations.
/// inputDevice   = Device used for user input.
/// time          = Game time subsystem.
/// cameraControl = Handles camera control by the user.
/// log           = Log to write... log messages to.
bool mainLoop(ref EntitySystem entitySystem,
              VideoDevice video,
              InputDevice input,
              GameTime time,
              CameraControl cameraControl,
              Logger log) @trusted nothrow
{
    entitySystem.spawnEntityASAP("game_data/level1.yaml");
    import tharsis.prof;
    import std.typecons;
    auto profiler = new Profiler(new ubyte[4096]);

    for(;;)
    {
        // TODO: measure time taken by an update (iteration of this while loop)
        // Instead of an FPS display, have a 'Load' display, where 100% is timeStep
        // and 0% is 0. 2014-08-16
        while(time.timeToUpdate())
        {
            profiler.reset();
            {
                auto fullUpdate = Zone(profiler, "fullUpdate");
                input.update();
                cameraControl.update();
                if(input.quit || input.keyboard.key(Key.Escape)) { return true; }

                import derelict.opengl3.gl3;
                // Clear the back buffer with a red background (parameters are R, G, B, A)
                glClearColor(0.01, 0.01, 0.04, 1.0);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                entitySystem.frame();
                // Log GL errors, if any.
                video.gl.runtimeCheck();
            }

            // Swap the back buffer to the front, showing it in the window.
            // Outside of fullUpdate because VSync could break our profiling.
            video.swapBuffers();

            time.finishedUpdate();

            if(input.keyboard.pressed(Key.F2)) foreach(zone; profiler.profileData.zoneRange)
            {
                log.infof("%s took %s hnsecs (%s %% of time step) from %s to %s",
                          zone.info, zone.duration,
                          zone.duration / (time.timeStep * 1000_000_0) * 100,
                          zone.startTime, zone.endTime)
                    .assumeWontThrow;
            }

            if(input.keyboard.pressed(Key.F3))
            {
                auto recorder = input.recorder;
                if(recorder.state == RecordingState.Recording)
                {
                    recorder.stopRecording();
                    input.replay(recorder.mouseRecording);
                    input.replay(recorder.keyboardRecording);

                    // TODO: Replace this with something better, and use VFS 2014-09-08
                    // Just a quick-and-dirty hack to record input for demos.
                    import io.yaml;
                    try
                    {
                        Dumper("mouse_keyboard.yaml").dump(recorder.recordingAsYAML);
                    }
                    catch(Exception e)
                    {
                        log.warning("Failed to dump input recording").assumeWontThrow;
                    }
                }
                else
                {
                    recorder.startRecording();
                }
            }
        }
    }

    assert(false, "This should never be reached");
}
