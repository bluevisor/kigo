// Sizes and colors, derived from the system font size and UI colors so Kigo
// follows the user's Appearance settings (including dark themes).
#ifndef THEME_H
#define THEME_H

#include <GraphicsDefs.h>
#include <InterfaceDefs.h>

struct Theme {
	float	scale;
	float	width;
	float	fieldHeight;
	float	rowHeight;
	float	headerHeight;
	float	footerHeight;
	float	padding;
	int32	iconSize;
	int32	maxRows;

	rgb_color	background;
	rgb_color	footerBackground;
	rgb_color	border;
	rgb_color	separator;
	rgb_color	text;
	rgb_color	dimText;
	rgb_color	faintText;
	rgb_color	selection;
	rgb_color	accent;
	rgb_color	keycap;
	rgb_color	warning;

	static const Theme& Get();
	static void Refresh();
};

rgb_color MixColors(rgb_color a, rgb_color b, float amount);

#endif // THEME_H
