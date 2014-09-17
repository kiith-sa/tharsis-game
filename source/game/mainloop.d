//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Main event loop of the game.
module game.mainloop;

import std.exception;
import std.logger;

import tharsis.prof;

import game.camera;
import entity.entitysystem;
import platform.inputdevice;
import platform.videodevice;
import time.gametime;



/** Main event loop of the game.
 *
 * Params:
 *
 * entitySystem       = EntitySystem holding all the Processes in the game.
 * videoDevice        = The video device used for graphics and windowing operations.
 * inputDevice        = Device used for user input.
 * time               = Game time subsystem.
 * cameraControl      = Handles camera control by the user.
 * mainThreadProfiler = Profiler used to profile game and Tharsis execution in the main thread.
 * log                = Log to write... log messages to.
 */
bool mainLoop(ref EntitySystem entitySystem,
              VideoDevice video,
              InputDevice input,
              GameTime time,
              CameraControl cameraControl,
              Profiler mainThreadProfiler,
              Logger log) @trusted nothrow
{
    entitySystem.spawnEntityASAP("game_data/level1.yaml");
    import tharsis.prof;
    import std.typecons;
    // Profiler used to calculate how much of the allocated time step we're spending.
    auto loadProfiler = new Profiler(new ubyte[4096]);

    for(;;)
    {
        while(time.timeToUpdate())
        {
            auto frameTotal = Zone(mainThreadProfiler, "frameTotal");
            loadProfiler.reset();
            {
                auto frameLoad = Zone(loadProfiler, "frameLoad");
                input.update();
                cameraControl.update();
                if(input.quit || input.keyboard.key(Key.Escape)) { return true; }

                import derelict.opengl3.gl3;
                // Clear the back buffer.
                glClearColor(0.01, 0.01, 0.04, 1.0);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                entitySystem.frame();
                // Log GL errors, if any.
                video.gl.runtimeCheck();
            }

            // Swap the back buffer to the front, showing it in the window.
            // Outside of the frameLoad zone because VSync could break our profiling.
            video.swapBuffers();

            time.finishedUpdate();

            // loadProfiler only has one zone: frameLoad.
            const frameLoadResult = loadProfiler.profileData.zoneRange.front;

            // 'load' is how much of the time step is used, in percent..
            double load(ulong hnsecs) @safe nothrow @nogc 
            {
                return 100 * hnsecs / (time.timeStep * 1000_000_0);
            }

            import std.string;
            import std.algorithm;

            import tharsis.entity.entitymanager;

            const(DefaultEntityManager.Diagnostics)* diag = &entitySystem.diagnostics();

            // Load for the frame overall.
            const loadTotal = load(frameLoadResult.duration);
            // Load for each individual core (without the % sign or decimal point).
            const string loadPerCore = 
                diag.threads[0 .. diag.threadCount]
                    .map!(t => "%03.0f".format(load(t.processesDuration)))
                    .join(",")
                    .assumeWontThrow;

            const usedMs = frameLoadResult.duration / 10000.0;
            const stepMs = time.timeStep * 1000;

            const summary = 
                "enties: %.5d | load: %05.1f%% (%s) | t-used: %05.1fms | t-step: %.1fms"
                .format(diag.pastEntityCount, loadTotal, loadPerCore, usedMs, stepMs)
                .assumeWontThrow;

            video.windowTitle = summary;

            // F2 prints basic load info.
            if(input.keyboard.pressed(Key.F2)) { log.info(summary).assumeWontThrow; }

            // F3 toggles recording.
            if(input.keyboard.pressed(Key.F3))
            {
                auto recorder = input.recorder;
                if(recorder.state == RecordingState.Recording)
                {
                    recorder.stopRecording();
                    input.replay(recorder.mouseRecording, No.blockMouse);
                    input.replay(recorder.keyboardRecording, No.blockKeyboard);

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
