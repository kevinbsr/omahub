# Third-party notices

OmaHub contains portions of these MIT-licensed projects, some adapted and some
redistributed unchanged:

- [Omarchy](https://github.com/omacom/omarchy), including foundations from
  the original clock, media and weather shell plugins. Copyright (c) David
  Heinemeier Hansson.
- [Screen Time](https://github.com/ax1g/quickshell-screentime-plugin), used as
  the basis for the Screen page and its model, and redistributed as the engine
  in `vendor/screentime/` (unmodified). Copyright (c) 2026 agx.
- [OmaConnect](https://github.com/jitendradara12/omaconnect), used as the basis
  for the Phone page and its components, and redistributed as the engine in
  `vendor/omaconnect/` (unmodified). Copyright (c) 2026 OmaConnect
  contributors. See `kdeconnect/VENDORED.md` for the tracked revision and
  local compatibility changes.
- [Omarchy Nearby](https://github.com/jfg96/omarchy-nearby), used as the basis
  for the Nearby page and `NearbyModel.js`. Copyright (c) 2026 jfg96.
- [Android Mirror](https://github.com/ayandexyz/omarchy-android-mirror), used
  as the basis for the Phone page's device list and mirror controls, and
  redistributed as the engine in `vendor/android-mirror/` with one patch
  (`vendor/patches/android-mirror/`) declaring its backend as a service entry
  point. Copyright (c) 2026 Ayan De. See `android-mirror/VENDORED.md` for the
  tracked revision and local compatibility changes.

Each vendored tree keeps its upstream `LICENSE` file alongside the code, and
`vendor/vendor.json` records the exact commit every one of them came from.

Their MIT terms follow:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.
