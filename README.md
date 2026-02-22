# LilyPond Docker

Alpine-based Docker image for [GNU LilyPond](https://lilypond.org/) with
**LilyJazz fonts** pre-installed. Includes a client script to compile scores
on a remote server over SSH.

| | |
|---|---|
| Image size | ~227 MB |
| Base | Alpine 3.21 |
| LilyPond | 2.25.17 (or 2.24.3 with Alpine 3.20) |
| Output formats | PDF, PNG, SVG, MIDI |
| Jazz fonts | LilyJazz notation + text + chords |
| LaTeX | **Not required** (optional, see below) |

## Files

```
lilypond/
  Dockerfile            # image definition
  lilyjazz-2.25.ily     # patched jazz stylesheet for LilyPond 2.25+
  lilypond-remote.sh     # client-side SSH wrapper script
```

---

## Server setup

### 1. Build the image

```bash
cd lilypond/
docker build -t lilypond .
```

To use the **stable** LilyPond branch (2.24.3) instead of the development
branch:

```bash
docker build --build-arg ALPINE_VERSION=3.20 -t lilypond .
```

### 2. Verify

```bash
docker run --rm lilypond
# → GNU LilyPond 2.25.17 (running Guile 3.0)
```

---

## Local usage (on the server directly)

### Compile a score to PDF

```bash
docker run --rm -v "$PWD":/scores lilypond myfile.ly
```

### Compile to PNG

```bash
docker run --rm -v "$PWD":/scores lilypond --png myfile.ly
```

### High-resolution PNG

```bash
docker run --rm -v "$PWD":/scores lilypond --png -dresolution=300 myfile.ly
```

### Interactive shell

```bash
docker run --rm -it -v "$PWD":/scores --entrypoint /bin/bash lilypond
```

---

## Remote usage (client/server over SSH)

The typical workflow: you edit `.ly` files on your laptop, and compile them
on a headless server that has Docker installed. The `lilypond-remote.sh`
script handles everything over SSH.

### How it works

```
 CLIENT (laptop)                          SERVER (headless)
 ──────────────                           ─────────────────
 1. tar the source dir ──── SSH ────────► extract into container
 2.                                       docker exec lilypond ...
 3. extract output     ◄─── SSH ───────── tar the PDF/PNG/MIDI
 4.                                       docker stop (container kept)
```

The container is **created once** and **reused** on subsequent runs.
It is stopped after each compilation but never removed, so restarts are
near-instant.

### Client setup

**1. Copy the script into your PATH:**

```bash
cp lilypond-remote.sh ~/.local/bin/lilypond-remote
chmod +x ~/.local/bin/lilypond-remote
```

**2. Configure your server** (pick one method):

```bash
# Option A: environment variable (add to your .bashrc / .zshrc)
export LILYPOND_SERVER="user@your-server"

# Option B: edit line 23 of the script directly
```

**3. Ensure SSH key-based login works** (no password prompt):

```bash
ssh-copy-id user@your-server
```

### Usage

```bash
# Basic PDF compilation
lilypond-remote myscore.ly

# PNG output
lilypond-remote --png myscore.ly

# High-resolution PNG + PDF
lilypond-remote --png -dresolution=300 myscore.ly
```

Output files (`.pdf`, `.png`, `.midi`, `.svg`) appear in the same
directory as the source `.ly` file.

### What happens on first run

```
[lilypond] Creating container 'lilypond'...
[lilypond] Starting container 'lilypond'...
[lilypond] Sending files...
[lilypond] Compiling myscore.ly...
Processing `myscore.ly'
...
Success: compilation successfully completed
[lilypond] Retrieving output...
[lilypond] Done → myscore.pdf
```

Subsequent runs skip the creation step and restart the existing container.

### Multi-file projects

The script sends the **entire directory** containing the `.ly` file to
the container. This means `\include` directives referencing sibling files
(custom stylesheets, shared definitions, etc.) work out of the box:

```
my-project/
  lead-sheet.ly          ← compiled file
  my-custom-macros.ily   ← sent along automatically
  chord-changes.ily      ← sent along automatically
```

```bash
lilypond-remote my-project/lead-sheet.ly
```

### Configuration reference

| Variable | Default | Description |
|---|---|---|
| `LILYPOND_SERVER` | `YOUR_SERVER` | SSH destination (`user@host`) |
| `LILYPOND_CONTAINER` | `lilypond` | Docker container name on the server |

---

## Jazz fonts

The image ships with [LilyJazz](https://github.com/OpenLilyPondFonts/lilyjazz)
fully configured. Three stylesheets are available:

| Stylesheet | Purpose |
|---|---|
| `lilyjazz.ily` | Handwritten notation font + text font |
| `jazzchords.ily` | Jazz chord symbol formatting (C7, Fmaj9, etc.) |
| `jazzextras.ily` | Utilities: start repeat bars, inline multi-measure rests |

### Minimal jazz example

```lilypond
\version "2.25.0"

\include "lilyjazz.ily"
\include "jazzchords.ily"
\include "jazzextras.ily"

\header {
  title = "Autumn Leaves"
  composer = "J. Kosma"
}

\score {
  <<
    \chords { c1:min7 f:7 bes:maj7 ees:maj7 }
    \relative c' {
      c4 d ees f | g a bes c | d c bes a | g f ees d |
    }
  >>
  \layout { }
  \midi { \tempo 4 = 160 }
}
```

### Note on LilyPond versions and jazz fonts

The upstream `lilyjazz.ily` from OpenLilyPondFonts uses the
`set-global-fonts` Scheme function, which was **removed in LilyPond 2.25**.
This image ships a patched stylesheet (`lilyjazz-2.25.ily`) that uses the
new `property-defaults.fonts.*` syntax. The patch is applied automatically
at build time based on the detected LilyPond version.

If you build with `ALPINE_VERSION=3.20` (LilyPond 2.24.3), the original
upstream stylesheet is kept as-is.

### Common jazz font pitfall

Most outdated guides only install the notation font OTFs. The
**supplementary text and chord fonts** (`lilyjazz-text.otf`,
`lilyjazz-chord.otf`) are also required. Without them, jazz chord symbols
and handwritten-style text won't render. This image installs them both in
LilyPond's font directory and system-wide via fontconfig.

---

## LaTeX

**Not required** for standard usage. LilyPond generates PDF directly
through Ghostscript -- no TeX distribution is involved.

LaTeX is only needed if you want to embed LilyPond scores inside LaTeX
documents using `lilypond-book` or `lyluatex`. To enable it, uncomment
the optional section at the bottom of the Dockerfile (adds ~200-400 MB):

```dockerfile
RUN apk add --no-cache \
    texlive \
    texlive-luatex \
    texmf-dist-latexextra \
    texmf-dist-music
```

Then use `lilypond-book` (already included in the base image):

```bash
docker run --rm -v "$PWD":/scores --entrypoint lilypond-book lilypond \
  --pdf mydocument.lytex
```

---

## Included tools

The `lilypond` Alpine package provides these commands, all available
inside the container:

| Command | Purpose |
|---|---|
| `lilypond` | Compile `.ly` files to PDF/PNG/SVG/MIDI |
| `lilypond-book` | Embed scores in LaTeX/Texinfo/HTML documents |
| `convert-ly` | Update `.ly` files to newer LilyPond syntax |
| `musicxml2ly` | Convert MusicXML to LilyPond format |
| `midi2ly` | Convert MIDI to LilyPond format |
| `abc2ly` | Convert ABC notation to LilyPond format |
| `etf2ly` | Convert Finale ETF to LilyPond format |

To use any of these via the remote script, override the entrypoint:

```bash
ssh your-server "docker start lilypond && \
  docker exec lilypond convert-ly -e myscore.ly && \
  docker stop lilypond"
```

---

## Container management

```bash
# Check container status
docker ps -a --filter name=lilypond

# Remove the container (to start fresh)
docker rm lilypond

# Rebuild the image (after Dockerfile changes)
docker build -t lilypond .

# Shell into the running container
docker exec -it lilypond /bin/bash
```
