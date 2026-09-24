# join_videos

A single Windows batch script that joins every video in a folder into one
file — **without re-encoding**. It uses [ffmpeg](https://ffmpeg.org/)'s
stream copy mode (`-c copy`), so the join is just a fast concatenation of the
existing video/audio data, not a render. A folder of GoPro/DJI/phone clips
that would take minutes (or hours) to re-encode joins in a few seconds
instead, with no quality loss.

## Features

- **No re-encoding.** Copies the video and audio streams directly, so it's
  fast and lossless. (Requires the clips to share the same codec/resolution —
  see [Limitations](#limitations).)
- **Four ways to sort the clips**, picked interactively or passed as an
  argument:
  1. **File name**, in natural order (`clip2` sorts before `clip10`)
  2. **Recording date**, read from the video's own metadata (falls back to
     the file's modified date when a clip has none)
  3. **File modified date**
  4. **File created date**
- **Shows its work.** Before joining, it lists every clip it found — file
  name, the date/key it sorted by, size, duration, codec and resolution —
  and asks you to confirm the order before doing anything.
- **Progress and a summary.** ffmpeg's live progress is shown while it runs,
  and a final summary reports start/end time, output size, duration and the
  full path of the result.
- Handles file names with spaces, accents and apostrophes.
- Detects DJI-style extra tracks (telemetry, debug data, cover thumbnail)
  that ffmpeg can't concatenate and skips them automatically, keeping only
  the actual video, audio and subtitle streams.

## Requirements

- Windows with `cmd.exe` and PowerShell (both ship with Windows).
- [ffmpeg](https://ffmpeg.org/download.html) and `ffprobe` available on your
  `PATH`, or placed in the same folder as the script.
  ```
  winget install Gyan.FFmpeg
  ```

## Usage

1. Copy [`join_videos.bat`](join_videos.bat) into the folder containing the
   videos you want to join.
2. Double-click it (or run it from a terminal).
3. Choose how to sort the clips when prompted.
4. Review the list it prints and confirm.

It produces a file named `MERGED_<timestamp>.<ext>` in the same folder,
using the extension of the first clip in the sorted order.

### Skipping the menu

Pass the sort mode as an argument to skip the interactive prompt — handy for
a desktop shortcut:

```bat
join_videos.bat 1   REM sort by file name
join_videos.bat 2   REM sort by recording date (metadata)
join_videos.bat 3   REM sort by file modified date
join_videos.bat 4   REM sort by file created date
```

### Supported extensions

`.mp4 .mkv .mov .m4v .avi .ts .mts .m2ts .wmv .flv .webm .3gp .mpg .mpeg`

## Limitations

Stream copying only works when every clip shares the same codec, resolution
and frame rate — this is normally true for a set of clips from the same
camera or phone. If the script detects a mismatch it warns you before
joining; the result may still fail or play back incorrectly, and in that
case the clips need to be re-encoded first (out of scope for this script).

## How it works

The script is a single `.bat` file with a PowerShell block embedded at the
end (never executed by `cmd`, only read and passed to `powershell -Command`).
That block lists the folder's videos and sorts them per the chosen mode.
`cmd` then builds an [ffmpeg concat
list](https://trac.ffmpeg.org/wiki/Concatenate#demuxer) from the sorted
files and calls `ffmpeg -f concat -c copy` to produce the output.

## License

MIT
