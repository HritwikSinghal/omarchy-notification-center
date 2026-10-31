.pragma library

// Text face for the panel. A proportional UI sans reads far better at small
// sizes than the theme's monospace Nerd Font, which stays for glyphs only.
// When it is not installed, fontconfig substitutes the default sans.
var text = "Adwaita Sans"

// The panel's type scale, as multiples of the shell's body size (Style.font.
// body, 12px by default) so it still follows the user's font-size setting.
// Steps of about 15%: at the default body size 20 / 16 / 15 / 14 / 13 / 12 px.
// The shell's own tokens top out at 11-14px for this kind of text, which reads
// small on a 4K screen at scale 1.
var title = 1.667    // panel heading
var summary = 1.333  // a notification's title
var body = 1.25      // a notification's body, the search query
var meta = 1.167     // app and time, group headers, footer buttons
var small = 1.083    // counts: the unread pill, group sizes
var hint = 1.0       // shortcut labels under the footer buttons

function px(bodySize, ratio) {
  return Math.round(bodySize * ratio)
}
