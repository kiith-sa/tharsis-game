//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module entity.schedulingalgorithmtype;


/// Enumerates all scheduling algorithm 'types' we can use with THarsis.
enum SchedulingAlgorithmType
{
    /// Longest Processing Time. This is the default scheduling algorithm type (.init).
    LPT,
    /// Dumb - equal number of Processes in each thread.
    Dumb,
    /// Bruteforce - slow (SLOW) backtracking.
    BRUTE,
    /// Randomized backtracking: timelimit = 400, attempts=3
    RBt400r3,
    /// Randomized backtracking: timelimit = 800, attempts=6
    RBt800r6,
    /// Randomized backtracking: timelimit = 1600, attempts=9
    RBt1600r9,
    /// The COMBINE algorithm combining LPT and MULTIFIT. Almost as fast as LPT, better results.
    COMBINE,
    /// Different Job and Machine Sets. Better but slower than LPT, should be fast enough. Buggy.
    DJMS
}
