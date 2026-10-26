#include "Theme.h"

#include <math.h>
#include <stdlib.h>

#include <Font.h>


static Theme sTheme;
static bool sInitialized = false;


rgb_color
MixColors(rgb_color a, rgb_color b, float amount)
{
	rgb_color color;
	color.red = (uint8)(a.red + (b.red - a.red) * amount);
	color.green = (uint8)(a.green + (b.green - a.green) * amount);
	color.blue = (uint8)(a.blue + (b.blue - a.blue) * amount);
	color.alpha = 255;
	return color;
}


static bool
IsDark(rgb_color color)
{
	return color.red * 0.299 + color.green * 0.587 + color.blue * 0.114 < 128;
}


void
Theme::Refresh()
{
	Theme& t = sTheme;
	// KIGO_SCALE enlarges everything, for screenshots.
	t.fontSize = be_plain_font->Size();
	if (const char* scale = getenv("KIGO_SCALE")) {
		if (atof(scale) > 0)
			t.fontSize *= atof(scale);
	}
	t.scale = t.fontSize / 12.0f;
	t.width = roundf(680 * t.scale);
	t.fieldHeight = roundf(58 * t.scale);
	t.rowHeight = roundf(42 * t.scale);
	t.headerHeight = roundf(26 * t.scale);
	t.footerHeight = roundf(34 * t.scale);
	t.padding = roundf(14 * t.scale);
	t.iconSize = (int32)roundf(28 * t.scale);
	t.maxRows = 9;

	// Document colors read as "a sheet above the desktop", like Spotlight.
	t.background = ui_color(B_DOCUMENT_BACKGROUND_COLOR);
	t.text = ui_color(B_DOCUMENT_TEXT_COLOR);
	bool dark = IsDark(t.background);
	t.footerBackground = tint_color(t.background, dark ? B_LIGHTEN_1_TINT
		: B_DARKEN_1_TINT);
	if (dark)
		t.footerBackground = MixColors(t.background, t.text, 0.05f);
	t.border = MixColors(t.background, t.text, dark ? 0.28f : 0.32f);
	t.separator = MixColors(t.background, t.text, 0.10f);
	t.dimText = MixColors(t.background, t.text, 0.58f);
	t.faintText = MixColors(t.background, t.text, 0.40f);
	t.accent = ui_color(B_KEYBOARD_NAVIGATION_COLOR);
	t.selection = MixColors(t.background, t.accent, dark ? 0.32f : 0.17f);
	t.keycap = MixColors(t.footerBackground, t.text, 0.10f);
	t.warning = MixColors(t.text, make_color(230, 70, 50), 0.85f);
	sInitialized = true;
}


const Theme&
Theme::Get()
{
	if (!sInitialized)
		Refresh();
	return sTheme;
}
