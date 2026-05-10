# Remote Text Input

OpenParsec normally sends keyboard input as Parsec HID keycodes. That works for
ASCII keys, hardware keyboards, shortcuts, and host-side IME composition, but it
does not carry committed Unicode text directly.

The `Remote Text Input` setting adds fallback sequences for text committed by
the iOS software keyboard, including Chinese Zhuyin/Pinyin and Japanese IME
text.

## Modes

- `Keycodes Only`: original behavior. Unsupported Unicode text is ignored.
- `Linux Ctrl+Shift+U`: sends `Ctrl+Shift+U`, the Unicode hex value, then Enter.
- `macOS Unicode Hex`: sends code units while holding Option. The host must use
  the Unicode Hex Input keyboard layout.
- `Windows Hex Numpad`: sends `Alt` + numpad plus + Unicode hex value. The host
  must have Windows Hex Numpad input enabled.

ASCII text and toolbar keys still use normal Parsec keycodes in every mode.
