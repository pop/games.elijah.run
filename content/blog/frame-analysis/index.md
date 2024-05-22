+++
title = "frame analysis"

description = "A fun adventure "

draft = true

taxonomies.categories = [
    "tech",
]

taxonomies.tags = [
    "gamedev",
    "rust",
    "bevy"
]

date = "2024-05-22"

authors = [
  "Elijah Voigt",
]
+++

Toward the end of development on [Martian Chess](http://localhost:8080/games#martian-chess) I got a message from my collaborator that made me sweat:

> [11:07 PM] **Also, I crashed again!**
> ![I crashed again](crashed-again.png)

Sam was playing a daily build and after ~5-10 minutes the game crashed with the above terminal output.
This had been happening for the last few days and was concerning because -- believe it or not, the game was not _supposed_ to crash!

I could tell from the screenshot that this was in the [wgpu](https://wgpu.rs/) part of the stack meaning it was related to the rendering.
I could also tell from the "Not enough memory left" that this was related to going over our resource budget.
And by budget I mean "we used all of it".

Sam was running on a laptop which we determined had ~2GB of GPU memory -- far less than my desktop's 8GB likely explaining why I had not experienced the issue.
Usually I would reproduce the issue directly, getting my system to crash like Sam's, but with different hardware that was out of the question.
I would need to _profile_ the game, determine how much memory we were using, and get that number to go down... somehow.
Let's get started!

# Finding Smoke

I am not a graphics expert.
I have a passing familiarity with shaders, and I think I know how a GPU works at a high level, but I have never had to actually troubleshoot rendering issues or performance problems.
But hey... everybody started somewhere.

After a quick search I found and installed [GPUProfiler](https://github.com/JeremyMain/GPUProfiler/releases).
Despite being closed-source I am pretty happy with this for getting a high-level overview of resource utilization over time.
Windows has similar GPU memory metrics in the task manager but GPUProfiler is _a little more granular_.

I set GPUProfiler to monitor my system and started playing the game.
I quickly determined that the game used ~800MB of memory just at baseline, and an _additional_ ~700MB of memory when a specific visual effect started up.

![Graph showing GPU resources up 1.5GB from baseline](problem-graph.png)

For reference this is the visual effect:

![Side-by-side showing lights visual effect](the-effect.png)

Instead of writing custom shaders or something the effect is achieved with four spot-lights arranged in a square, making the effect somewhat "physical".

I felt confident calling it that the problem was with this lighting effect.
Great, job well done, let's pack it in boys.

# Digging Deeper

Sadly I couldn't just "not do the lighting effect".
Now that we knew the issue was with lighting I needed some visibility into how the scene was rendered to determine if there was a knob or two that I could turn to improve the effect's performance.

After a quick Google search I installed some _allegedly_ useful GPU profilers to no avail:
* NVidia Visual Profiler: I could not get this to work for the life of me.
* Radeon GPU Profiler: Did not work because I have Nvidia hardware.
* There was a Windows tool I also could not get to work.

Sadly it took a full day to triage the above and not one of them was useful.
I couldn't even get them to _start_ profiling, so analysis was out of the question.

At this point I was getting frustrated and I tried a few last-ditch efforts -- basically just throwing stuff at the wall.
* Reduce the number of lights? Looked worse and didn't reduce frambuffer usage.
* Bevy tweaks like draw distance and turning off effects like Boom? Nope.
* Compress my texture assets? Surprisingly little impact on framebuffer usage.

Sadly this shotgun approach did nothing for the performance of the game and in some cases even made things worse!

Two nights in a row I worked until midnight banging my head against this problem and I was starting to panic.
I knew engines like Unity and Unreal had loads of documentation but Bevy didn't have _anything_ about this.
Maybe I was shit out of luck and needed to start from scratch.

I was at the end of my rope... and then I remembered [Acerola](https://www.patreon.com/acerola_t)!

# Acerola to the Rescue

Acerola produces amazing Real-Time Graphics educational content on YouTube; it's a blend of fun, engaging, informative, and "this guy knows his shit".
He regularly breaks down real-time graphics effects from videogames, for example [Lethal Company](https://youtu.be/Z_-am00EXIc).

Acerola usually does a frame-dump and analysis using [Nvidia Nsight Graphics](https://developer.nvidia.com/nsight-graphics).
After reviewing a few videos I was confident I could use this to profile and determine my performance bottleneck.

# Finding Fire

Installing and setting up Nsight Graphics was so much easier than the other tools I tried earlier in the week.
1. Sign some Nvidia EULAs.
2. Download the free (as in pizza) binary.
3. Tell it how to run your program.
4. Play the game for a while.
5. Capture a frame.

It dumps every single API call made to the GPU and accounts for every piece of memory on the GPU when the frame was rendered.

Pretty quickly the problem became apparent:

[![Why is that using so much memory??](problem.png)](problem.png)

I compared two frames, one before and one after the lighting effect.
The "Device Memory" showed that the with-lighting frame had a 600MB _something_ that wasn't there before.
Interestingly 600MB correlated was about the same size as the jump in framebuffer usage that we saw with GPUProfiler, so this was almost certainly the problem, but how do I fix it?

Digging deeper, that 600mb memory item was a grid of 36 image textures each of which was basically black.
36 was pretty close to the number of spot-lights in the game which for this frame was 4x7 28.
Were these textures some sort of light depth map?

The images were 2048x2048 which was crazy big, seeing as our game was only running at 640x480.
I did the dumbest thing I could think of and just searched the Bevy codebase for '2048' to see what showed up.

[![Searching 2048 on the Bevy Github Repository](search-results.png)](search-results.png)

Low and behold the [PointLightShadowMap](https://docs.rs/bevy/latest/bevy/pbr/struct.PointLightShadowMap.html) defaults to a 'size' of 2048.
Now usually I wouldn't just blindly assume that the first result was the answer, but like... come on.

I checked [where this value was used for SpotLights](https://github.com/bevyengine/bevy/blob/a785e3c20dce1dfe822084f00be02641382a1a35/crates/bevy_pbr/src/render/light.rs#L451-L453) and found it used in the calculation `Light.shadow_normal_bias = PointLightShadowMap.size * PointLight.shadow_normal_bias` so if I set the former to `256` and the latter to `1.0` we should see those textures update from  a size of `2048x2048` to a size of `256x256`.
I updated the `PointLightShadowMap` to `size: 256` and the [shadow_depth_bias](https://docs.rs/bevy/latest/bevy/pbr/struct.PointLight.html) to `1.0` and ran another profile:

[![It worked!](solution.png)](solution.png)

Look at that -- it worked!
Not only was the texture the expected size of `256x256` but the memory impact was just 11MB!

GPUProfiler confirmed that this was the solution:

[![No sweat!](solution-graph.png)](solution-graph.png)

For fun I tried bumping the shadow map resolution to `512x512` and it was _still_ no sweat!

[![Shadow maps? What shadow maps!](solution-graph2.png)](solution-graph2.png)

![Happy Dance](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExc2YydHBhYXI3Y2xoMGhqZ2ZwenR3bWFrODhteGdoYXFyeHNsYWZtMCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/dkGhBWE3SyzXW/giphy.gif)

# The game is saved

*Phew* what a relief.

Let's review the week:
* Day 0: Oh bother. The game keeps crashing on Sam's compe.
* Day 1: I'm not sure what a Frame-buffer is but we're using a lot of it.
* Day 2: Wow these profiling tools suck. And I doomed?
* Day 3: Thank you Acerola, you're my hero!
* Day 4: Hey look at that, I can profile my game! I'm like Neo in the Matrix!

It was stressful, but the game is in much better shape now than it was at the start.
More importantly, I have begun building the important skill of GPU profiling!
Now I can open the black box of rendering and enforce a _real_ resource budget!

Thank you for reading.
If you are interested in Martian Chess, feel free to download a copy at [pop.itch.io/martian-chess](https://pop.itch.io/martian-chess).
If you like it and want to throw me and Sam a few dollars we would be honored.