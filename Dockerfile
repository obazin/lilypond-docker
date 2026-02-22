# =============================================================================
# LilyPond Docker Image — Alpine-based, with LilyJazz fonts
# =============================================================================
#
# Produces PDF/PNG/SVG/MIDI music scores from .ly files.
#
# BUILD:
#   docker build -t lilypond ./lilypond
#
#   # For LilyPond 2.24.3 (stable) instead of 2.25.x (dev):
#   docker build --build-arg ALPINE_VERSION=3.20 -t lilypond ./lilypond
#
# USAGE:
#   # Compile a score (mount current dir as /scores):
#   docker run --rm -v "$PWD":/scores lilypond myfile.ly
#
#   # Produce PNG output:
#   docker run --rm -v "$PWD":/scores lilypond --png myfile.ly
#
#   # Interactive shell:
#   docker run --rm -it -v "$PWD":/scores --entrypoint /bin/bash lilypond
#
# JAZZ EXAMPLE (in your .ly file):
#   \version "2.24.0"   % or "2.25.0" depending on your build
#   \include "lilyjazz.ily"
#   \include "jazzchords.ily"
#   \include "jazzextras.ily"
#
# LATEX:
#   NOT required. LilyPond generates PDF directly via Ghostscript.
#   LaTeX is only needed if you embed scores in LaTeX docs (lilypond-book).
#   See the optional section at the bottom of this file to enable it.
#
# =============================================================================

# Alpine 3.21 ships LilyPond 2.25.17, Alpine 3.20 ships 2.24.3 (stable)
ARG ALPINE_VERSION=3.21

FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION

# Enable community repository (LilyPond is packaged there)
RUN echo "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community" \
    >> /etc/apk/repositories

# ---------------------------------------------------------------------------
# Core packages
# ---------------------------------------------------------------------------
# lilypond       — pulls in guile, python3, cairo, pango, freetype, libpng
# ghostscript    — PostScript/PDF backend (ps2pdf)
# font-urw-base35— default text fonts (C059, Nimbus Mono PS, Nimbus Sans)
# fontconfig     — font discovery
# bash           — interactive shell convenience (ash is too limited)
# ---------------------------------------------------------------------------
RUN apk add --no-cache \
    lilypond \
    ghostscript \
    font-urw-base35 \
    fontconfig \
    bash \
    ca-certificates \
    wget

# ---------------------------------------------------------------------------
# Install LilyJazz fonts
# ---------------------------------------------------------------------------
# Sources: https://github.com/OpenLilyPondFonts/lilyjazz
#
# Notation font:  lilyjazz-{11..26}.otf, lilyjazz-brace.otf + SVG/WOFF
# Text font:      supplementary-files/lilyjazz-text/lilyjazz-text.otf
# Chord font:     supplementary-files/lilyjazz-chord/lilyjazz-chord.otf
# Stylesheets:    lilyjazz.ily, jazzchords.ily, jazzextras.ily
#
# IMPORTANT: The supplementary text+chord OTF files are the most commonly
# missed step (many outdated guides skip them). Without them, jazz chord
# symbols and handwritten text won't render.
# ---------------------------------------------------------------------------

# Patched stylesheet for LilyPond 2.25+ (set-global-fonts was removed,
# replaced by property-defaults.fonts.*). Only used when building with
# Alpine >= 3.21 / LilyPond >= 2.25.
COPY lilyjazz-2.25.ily /tmp/lilyjazz-2.25.ily

RUN set -e \
    && LP_VERSION=$(lilypond --version 2>&1 \
         | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) \
    && LP_SHARE="/usr/share/lilypond/${LP_VERSION}" \
    && TMPDIR=$(mktemp -d) \
    #
    # --- Download LilyJazz archive ---
    && wget -q "https://github.com/OpenLilyPondFonts/lilyjazz/archive/refs/heads/master.tar.gz" \
         -O "${TMPDIR}/lilyjazz.tar.gz" \
    && tar xzf "${TMPDIR}/lilyjazz.tar.gz" -C "${TMPDIR}" \
    && cd "${TMPDIR}/lilyjazz-master" \
    #
    # 1) Notation font OTFs (all optical sizes + brace)
    && cp otf/*.otf "${LP_SHARE}/fonts/otf/" \
    #
    # 2) SVG + WOFF variants (needed for SVG backend output)
    && cp svg/*.svg svg/*.woff "${LP_SHARE}/fonts/svg/" \
    #
    # 3) Stylesheets → LilyPond's include path
    && cp stylesheet/*.ily "${LP_SHARE}/ly/" \
    #
    # 4) Supplementary text + chord fonts → LilyPond's font dir
    && find supplementary-files -name '*.otf' \
         -exec cp {} "${LP_SHARE}/fonts/otf/" \; \
    #
    # 5) Also register text/chord fonts system-wide for fontconfig
    #    (LilyPond uses fontconfig for text fonts, its own index for music fonts)
    && mkdir -p /usr/share/fonts/lilyjazz \
    && find supplementary-files -name '*.otf' \
         -exec cp {} /usr/share/fonts/lilyjazz/ \; \
    #
    # 6) Patch lilyjazz.ily for LilyPond 2.25+ (set-global-fonts removed)
    && LP_MINOR=$(echo "${LP_VERSION}" | cut -d. -f2) \
    && if [ "${LP_MINOR}" -ge 25 ]; then \
         cp /tmp/lilyjazz-2.25.ily "${LP_SHARE}/ly/lilyjazz.ily"; \
       fi \
    #
    # --- Cleanup ---
    && rm -rf "${TMPDIR}" /tmp/lilyjazz-2.25.ily \
    && apk del --no-cache wget ca-certificates \
    #
    # --- Rebuild font cache ---
    && fc-cache -fv

# ---------------------------------------------------------------------------
# Non-root user & working directory
# ---------------------------------------------------------------------------
RUN addgroup -S lilypond && adduser -S lilypond -G lilypond \
    && mkdir -p /scores && chown lilypond:lilypond /scores

WORKDIR /scores
USER lilypond

ENTRYPOINT ["lilypond"]
CMD ["--version"]

# =============================================================================
# OPTIONAL: LaTeX support (lilypond-book / lyluatex)
# =============================================================================
# Uncomment the lines below BEFORE the USER directive if you need to embed
# LilyPond scores inside LaTeX documents. This adds ~200-400 MB.
#
# RUN apk add --no-cache \
#     texlive \
#     texlive-luatex \
#     texmf-dist-latexextra \
#     texmf-dist-music
#
# The lilypond-book command is already included in the lilypond package.
# Usage:  lilypond-book --pdf mydocument.lytex
#         lualatex mydocument.tex
# =============================================================================
