# Third-party notices

Dice bundles ExifTool 13.50 by Phil Harvey, licensed under the same terms as Perl (Artistic License or GNU General Public License). Source and license: https://exiftool.org/ and https://github.com/exiftool/exiftool. Its unmodified Image::ExifTool modules and File::RandomAccess module are included; the command-line script removes only Homebrew-specific search paths, and says so in a notice at its top (Artistic License §3); Dice uses ExifTool under the Artistic License. The system Perl interpreter is used. Dice invokes ExifTool with user configuration disabled.

Dice bundles cwebp and img2webp 1.6.0 and their dependencies from Homebrew for this development preview. WebP / SharpYUV: Google, BSD license, https://github.com/webmproject/libwebp/blob/main/COPYING. libpng: PNG Reference Library license, https://github.com/pnggroup/libpng/blob/libpng16/LICENSE. libjpeg-turbo: IJG, BSD and zlib licenses, https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md. libtiff: permissive libtiff license, https://gitlab.com/libtiff/libtiff/-/blob/master/LICENSE.md. xz (liblzma): BSD Zero Clause License, https://github.com/tukaani-project/xz/blob/master/COPYING. Zstandard: BSD license, https://github.com/facebook/zstd/blob/dev/LICENSE. Additional transitive library licenses are copied by the packaging process into Tools/Licenses.

Apple frameworks and the system Perl runtime are provided by macOS, rather than distributed with Dice.

Dice bundles Sparkle 2.10.0 for signed software updates, under its MIT license and included third-party notices. Source: https://github.com/sparkle-project/Sparkle. The complete license is shipped as `Contents/Resources/Sparkle-LICENSE.txt`.

Dice bundles the resvg 0.48.1 static SVG renderer (Apache-2.0 OR MIT), built from the pinned crates.io release using its lockfile. Source: https://github.com/linebender/resvg/tree/v0.48.1. License texts and dependency notices are included in `Tools/Licenses/resvg`. Dice uses unmodified upstream code; no renderer source modifications are distributed.

Dice bundles the oxipng 10.2.1 lossless PNG optimizer (MIT), built from the pinned crates.io release using its lockfile. Source: https://github.com/oxipng/oxipng/tree/v10.2.1. License texts for oxipng and its 47 dependencies (MIT, Apache-2.0, BSD, Zlib and Unlicense terms) are included in `Tools/Licenses/oxipng`, listed in `DEPENDENCIES.txt`. Dice uses unmodified upstream code.
