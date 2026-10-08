# Third-party notices

Dice bundles ExifTool 13.50 by Phil Harvey, licensed under the same terms as Perl (Artistic License or GNU General Public License). Source and license: https://exiftool.org/ and https://github.com/exiftool/exiftool. Its unmodified Image::ExifTool modules and File::RandomAccess module are included; the command-line script removes only Homebrew-specific search paths. The system Perl interpreter is used. Dice invokes ExifTool with user configuration disabled.

Dice bundles cwebp 1.6.0 and its dependencies from Homebrew for this development preview. WebP / SharpYUV: Google, BSD license, https://github.com/webmproject/libwebp/blob/main/COPYING. libpng: PNG Reference Library license, https://github.com/pnggroup/libpng/blob/libpng16/LICENSE. libjpeg-turbo: IJG, BSD and zlib licenses, https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md. libtiff: permissive libtiff license, https://gitlab.com/libtiff/libtiff/-/blob/master/LICENSE.md. Additional transitive library licenses are copied by the packaging process into Tools/Licenses.

Apple frameworks and the system Perl runtime are provided by macOS, rather than distributed with Dice.
