//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Main event loop of the game.
module game.mainloop;

import std.exception;
import std.experimental.logger;

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
 * entitySystem    = EntitySystem holding all the Processes in the game.
 * videoDevice     = The video device used for graphics and windowing operations.
 *                   May be null if we're running headless.
 * inputDevice     = Device used for user input.
 * time            = Game time subsystem.
 * cameraControl   = Handles camera control by the user.
 * threadProfilers = Profilers used to profile game and Tharsis execution in individual threads.
 * log             = Log to write... log messages to.
 */
bool mainLoop(ref EntitySystem entitySystem,
              VideoDevice video,
              InputDevice input,
              GameTime time,
              CameraControl cameraControl,
              Profiler[] threadProfilers,
              Logger log) @trusted
{
    entitySystem.spawnEntityASAP("game_data/level1.yaml");
    import tharsis.prof;
    // Profiler used to calculate how much of the allocated time step we're spending.
    auto loadProfiler = new Profiler(new ubyte[4096]);
    auto mainThreadProfiler = threadProfilers[0];

    auto sender = new DespikerSender(threadProfilers);
    ulong frameIdx = 0;
    for(;;) if(time.timeToUpdate())
    {
        scope(exit) { ++frameIdx; }

        auto frame = Zone(mainThreadProfiler, "frame");
        loadProfiler.reset();
        {
            auto frameLoad = Zone(loadProfiler, "frameLoad");
            input.update();
            cameraControl.update();
            if(input.quit || input.keyboard.key(Key.Escape)) { return true; }

            // Clear the back buffer.
            if(video !is null)
            {
                import derelict.opengl3.gl3;
                glClearColor(0.01, 0.01, 0.04, 1.0);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            }

            entitySystem.frame();
        }

        time.finishedUpdate();

        {
            auto diagTools = Zone(mainThreadProfiler, "diagTools");

            string summary;
            {
                auto summarize = Zone(mainThreadProfiler, "summarizeLoad");
                summary = summarizeLoad(loadProfiler, time, entitySystem.diagnostics);
            }

            recordDiagnostics(entitySystem.diagnostics, mainThreadProfiler);

            // Update the window title every 30th frame
            if(frameIdx % 30 == 0 && video !is null)
            {
                auto setTitle = Zone(mainThreadProfiler, "video.windowTitle()");
                video.windowTitle = summary;
            }

            // F2 prints basic load info (useful in fullscreen or recorded demos).
            if(input.keyboard.pressed(Key.F2)) { log.info(summary).assumeWontThrow; }
            // F3 toggles recording.
            if(input.keyboard.pressed(Key.F3)) { toggleRecording(input, log); }

            try if(input.keyboard.pressed(Key.F4) && !sender.sending)
            {
                // TODO: configurable despiker path 2014-10-06
                // TODO: When publishing, include despiker binary+font in tharsis-game dir.
                sender.startDespiker("../tharsis-despiker/despiker");
            }
            catch(DespikerSenderException e)
            {
                log.error("Failed to start despiker: " ~ e.msg);
            }
        }

        // Must finish all zones before updating the sender.
        destroy(frame);
        sender.update();
    }

    assert(false, "This should never be reached");
}


private:
import tharsis.entity.entitymanager;

/** Summarize performance load (time spent by each thread in the frame, etc) into a string.
 *
 * Params:
 *
 * loadProfiler = Profiler used in mainLoop() to measure the total time spent in a frame
 *                must have only one zone ("frameLoad").
 * diagnostics  = Entity manager diagnostics (to get time spent in individual threads).
 * time         = Game time subsystem.
 */
string summarizeLoad(const Profiler loadProfiler,
                     const GameTime time,
                     ref const DefaultEntityManager.Diagnostics diagnostics) @trusted nothrow
{
    // loadProfiler only has one zone: frameLoad.
    const frameLoadResult = loadProfiler.profileData.zoneRange.front;
    // 'load' is how much of the time step is used, in percent..

    double load(ulong hnsecs) @safe nothrow @nogc
    {
        return 100 * hnsecs / (time.timeStep * 1000_000_0);
    }

    import std.string;
    import std.algorithm;

    // Load for the frame overall.
    const loadTotal = load(frameLoadResult.duration);
    // Load for each individual core (without the % sign or decimal point).
    string loadPerCore = diagnostics.threads[0 .. diagnostics.threadCount]
                                    .map!(t => "%03.0f".format(load(t.processesDuration)))
                                    .join(",")
                                    .assumeWontThrow;

    const usedMs = frameLoadResult.duration / 10000.0;
    const stepMs = time.timeStep * 1000;

    return "enties: %.5d | load: %05.1f%% (%s) | t-used: %05.1fms | t-step: %.1fms"
           .format(diagnostics.pastEntityCount, loadTotal, loadPerCore, usedMs, stepMs)
           .assumeWontThrow;
}

/** Toggle recording on or off.
 *
 * Toggling recording off also starts replaying the finished recording.
 *
 * Params:
 *
 * input = The input device to record.
 * log   = Game log.
 */
void toggleRecording(InputDevice input, Logger log) @safe nothrow
{
    auto recorder = input.recorder;
    if(recorder.state == RecordingState.NotRecording)
    {
        recorder.startRecording();
        return;
    }

    recorder.stopRecording();
    import std.typecons;
    // Replay the recording that was just recorded.
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



/** Records various diagnostics variables with a profiler.
 *
 * Params:
 *
 * diagnostics = Tharsis entity manager diagnostics.
 * profiler    = Profiler to record the diagnostics.
 */
void recordDiagnostics(Diagnostics)(ref const(Diagnostics) diagnostics, Profiler profiler)
    @safe nothrow
{
    void var(string name, T)(T value) { profiler.variableEvent!name(value); }

    with(diagnostics)
    {
        var!"entityCount"(cast(uint)pastEntityCount);
        var!"procDurTotal_ms"(processDurationTotal.hns2ms);
        var!"compMemAll_kiB"(pastMemoryAllocatedTotal.B2kiB);
        var!"compMemUsed_kiB"(pastMemoryUsedTotal.B2kiB);
    }
    with(diagnostics.scheduler)
    {
        var!"sched_isApproximate"(cast(uint)approximate);
        var!"sched_estFrameTime_ms"(estimatedFrameTime.hns2msF);
    }
    with(diagnostics.scheduler.timeEstimator)
    {
        var!"sched_timest_totalError_ms"(totalProcessError.hns2msF);
        var!"sched_timest_totalUnderest_ms"(totalProcessUnderestimate.hns2msF);
        var!"sched_timest_maxUnderest_ms"(maxProcessUnderestimate.hns2msF);
        var!"sched_timest_avgErrorRatio_%"(averageProcessErrorRatio.ratio2pc);
        var!"sched_timest_avgUnderestRatio_%"(averageProcessUnderestimateRatio.ratio2pc);
        var!"sched_timest_maxUnderestRatio_%"(maxProcessUnderestimateRatio.ratio2pc);
    }
}

@trusted nothrow:

// Functions for conversions in recordDiagnostics().
import std.algorithm: min;
uint hns2ms(T)(T hns)        { assert(hns >= 0); return cast(uint)min(hns / 10_000, uint.max); }
float hns2msF(T)(T hns)      { return hns / 10_000.0f; }
float ratio2pc(double ratio) { return ratio * 100.0f; }
uint B2kiB(size_t b)         { return cast(uint)(b / 1024); }
