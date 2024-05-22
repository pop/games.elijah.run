+++
title = "tweaks files"

description = "Proof of concept for runtime configuration for games"

draft = false

taxonomies.categories = [
    "tech",
]

taxonomies.tags = [
    "gamedev",
    "rust",
    "bevy"
]

date = "2024-01-01"

authors = [
  "Elijah Voigt",
]
+++

I am working with my friend Sam on a [Martian Chess][martian] clone which --despite us choosing this project _because_ it was simple and straightforward-- is turning into a whole thing.
I want it to look good, I want it to have compelling music, I want it to have good "feel".
I want it to be the kind of game we can be proud of not just because it shipped but because it feels good to play.

All of the ~~fiddling~~ tweaking required to get those elements "right" necessitates some amount of runtime configuration that can be updated during development to see changes happening in real time.

## Approach 1: In Game Settings

When I realized that Sam and I should be able to tweak the game in real-time I thought "Oh I'll add a UI and some buttons!"

If I was using an engine like Godot, Unity, or Unreal something like this would be "the" solution, but for reasons I'll get into in a later post I am not interested in using those engines.

My engine of choice, Bevy, is a code-only engine with no out-of-the-box editor to speak of -- which has pros and cons.
It's nice that the engine is simple and customizable, it is not nice that questions like this are still unsolved.
Bevy plans to add some form of UI "soon" but it's been "planned for the next release" for over a year (and ~3 releases) so I'm not holding my breath.

The investment for building a UI is pretty high and the payoff is not _definitely_ worth it, so being prudent with my time I moved on.
_Eventually_ I will build custom editor UIs for my games, but not this game.

## Approach 2: Well defined settings files

My next approach was to have settings files which de-serialized into well defined structs using the [toml][toml] crate.

For example, this struct:

```rust
#[derive(Deserialize, Default, Debug, Asset)]
struct AudioSettings {
    // Path to audio assets
    file: String,
    // Pick Up SFX Event
    pick_up_sfx: String,
    // Put Down SFX Event
    put_down_sfx: String,
    // ...
}
```

which contains all of the possibly tweaked audio settings could be modified in a file like this:

```toml
# assets/audio.toml
file = "audio/main/Martian Chess.fspro"
pick_up_sfx = "/Main/SFX/pickup"
put_down_sfx = "/Main/SFX/putdown"
```

This is really nice because it allows me to catch some access errors at compile time.

```rust
fn some_audio_system(
    handles: Res<GameHandles>, // Imagine we store asset handles in a custom resource
    audio_tweak_files: Res<Assets<AudioSettings>> // The Audio Settings asset file(s)
) {
    let audio_tweaks = audio_tweak_files
        .get(handles.audio_settings.clone())
        .expect("Fetch audio tweakfile");

    do_something(audio_tweaks.pick_up_sfx) // Use the pick-up sound effect value
}
```

This itches the "catch everything at compile time" part of my brain, but it ends up turning into a lot of what I call "paperwork programming" where you have to...

1. Create a struct to represent some configuration.
2. Possibly write de-serialize code if the data it represents cannot be auto-de-serialized (like external types).
3. Write the configuration file.
4. Write the code that accesses that configuration.

... and after that is all done you _still_ have runtime failures because the configuration file is not compiled with the program!

**TLDR** this is going in the right direction, but managing de-serialize structs gets tedious quickly.

## Approach 3: Generic Tweakfiles

The approach I finally settled on was to use [toml][toml] but instead of de-serializing to my structs I de-serialized to a generic [toml Table][table] value and fetched specific assets with a sort of hash-map key:value pattern.

Here is what my `assets/martian-chess.tweaks.toml` file looks like:

```toml
[audio]
file = "audio/main/Martian Chess.fspro"
pick_up_sfx = "/Main/SFX/pickup"
put_down_sfx = "/Main/SFX/putdown"
```

and here is my access pattern:

```rust
fn some_audio_system(
    tweaks_handle: Res<Handle<Tweaks>>,
    tweak_files: Res<Assets<Tweaks>>,
) {
    let tweaks = tweak_files.get(tweaks_handle.clone())
                            .expect("Fetch tweaks file");
    let audio_pick_up = tweaks.get::<String>("audio.pick_up_sfx")
                              .expect("Audio Pick-up SFX");
}
```

This ended up being the most useful for my game.
The `*.tweak.toml` file is loaded as a TOML Table which is essentially a nested map of keys and values.
I then use polymorphism to `.get::<T>` for any `T` that is de-serializable.
Finally I parse `audio.pick_up_sfx` into the hierarchy `audio` containing a table of key:values including `pick_up_sfx`.
If at any point that fails `.get::<T>()` returns `None` which can be handled on a case-by-case basis with defaults.

Navigating a TOML Table is sort of a pain, but with some string parsing for the `value.sub-value` and a dusting of recursion it's not too bad!

## Bonus: Nested Assets

A bit of sugar I added on top of this was when a value ends in a file extension (and that file exists) we load it automatically.
When you want that handle, you can use the `get_handle::<T: Asset>("...")` method on the `Tweaks` struct.
For example:

```rust
fn some_audio_system(
    tweaks_handle: Res<Handle<Tweaks>>,
    tweak_files: Res<Assets<Tweaks>>,
    gltfs: Res<Assets<Gltf>>,
) {
    let tweaks = tweak_files.get(tweaks_handle.clone())
                            .expect("Fetch tweaks file");
    let gltf_handle = tweaks.get_handle::<Gltf>("models.file")
                            .expect("GLTF Asset File Handle");
    let gltf_file = gltfs.get(gltf_handle.clone())
                         .expect("GLTF Assets");
    // ...
}
```

**In the weeds note**: At first I tried to load all files with Bevy's [`LoadContext.load_untyped()`][load_untyped] method.
This does not give you a handle to the asset, but to a handle to an indirect `LoadUntypedAsset` which always is always "Untyped", even when you call `.typed()` on it.

Anyway my gross-ish feeling solution was to just check the file extension and load specific types like `.glb | .gltf => .load::<Gltf>()` or `.png | .jpg => .load::<Image>()`.
This makes the code more brittle but also has the added benefit of working.

## Aside: Google Drive WTF

Up until this point I was using `git` for code version control but my collaborator and I were using Google Drive for file syncing.

When using `git` I was able to edit files and Bevy would send AssetEvents to my game, but when the game ran from the Google Drive folder these events were not sent!
I suspect Google Drive is doing something funky with file handles or inodes or some arcane Window Filesystem hack that prevents the usual filesystem notifications from working as intended.

We are using Git now.
[TortoiseGit][tortoise] is pretty accessible for the terminal-averse, making it a good fit for our team.

## Open Question: How to ship this?

One question I have is how I should ship a game with this Tweaks-file setup.

On the one hand I think this is nice for modding and letting players edit attributes of the game.
On the other hand my current implementation is really inefficient and making it performant may be more work than I am willing to do.
Hard coding the final tweak values would certainly speed up the game -- or at least that's what I expect.

I will report back once I ship a game!
In the meantime it is very useful for development so this is a must-have for future projects!

[martian]: https://en.wikipedia.org/wiki/Martian_chess
[bevy]: https://bevyengine.org/
[toml]: https://docs.rs/toml/latest/toml/
[table]: https://docs.rs/toml/latest/toml/type.Table.html
[load_untyped]: https://docs.rs/bevy/0.12.1/bevy/asset/struct.LoadContext.html#method.load_untyped
[tortoise]: https://tortoisegit.org/
