#include "cache.h"
#include "color.h"

#define COLOR_RESET "\033[m"

static int parse_color(const char *name, int len)
{
	static const char * const color_names[] = {
		"normal", "black", "red", "green", "yellow",
		"blue", "magenta", "cyan", "white"
	};
	char *end;
	int i;
	for (i = 0; i < ARRAY_SIZE(color_names); i++) {
		const char *str = color_names[i];
		if (!strncasecmp(name, str, len) && !str[len])
			return i - 1;
	}
	i = strtol(name, &end, 10);
	if (*name && !*end && i >= -1 && i <= 255)
		return i;
	return -2;
}

static int parse_attr(const char *name, int len)
{
	static const int attr_values[] = { 1, 2, 4, 5, 7 };
	static const char * const attr_names[] = {
		"bold", "dim", "ul", "blink", "reverse"
	};
	int i;
	for (i = 0; i < ARRAY_SIZE(attr_names); i++) {
		const char *str = attr_names[i];
		if (!strncasecmp(name, str, len) && !str[len])
			return attr_values[i];
	}
	return -1;
}

void color_parse(const char *value, const char *var, char *dst)
{
	const char *ptr = value;
	int attr = -1;
	int fg = -2;
	int bg = -2;

	if (!strcasecmp(value, "reset")) {
		strcpy(dst, "\033[m");
		return;
	}

	/* [fg [bg]] [attr] */
	while (*ptr) {
		const char *word = ptr;
		int val, len = 0;

		while (word[len] && !isspace(word[len]))
			len++;

		ptr = word + len;
		while (*ptr && isspace(*ptr))
			ptr++;

		val = parse_color(word, len);
		if (val >= -1) {
			if (fg == -2) {
				fg = val;
				continue;
			}
			if (bg == -2) {
				bg = val;
				continue;
			}
			goto bad;
		}
		val = parse_attr(word, len);
		if (val < 0 || attr != -1)
			goto bad;
		attr = val;
	}

	if (attr >= 0 || fg >= 0 || bg >= 0) {
		int sep = 0;

		*dst++ = '\033';
		*dst++ = '[';
		if (attr >= 0) {
			*dst++ = '0' + attr;
			sep++;
		}
		if (fg >= 0) {
			if (sep++)
				*dst++ = ';';
			if (fg < 8) {
				*dst++ = '3';
				*dst++ = '0' + fg;
			} else {
				dst += sprintf(dst, "38;5;%d", fg);
			}
		}
		if (bg >= 0) {
			if (sep++)
				*dst++ = ';';
			if (bg < 8) {
				*dst++ = '4';
				*dst++ = '0' + bg;
			} else {
				dst += sprintf(dst, "48;5;%d", bg);
			}
		}
		*dst++ = 'm';
	}
	*dst = 0;
	return;
bad:
	die("bad config value '%s' for variable '%s'", value, var);
}

int git_config_colorbool(const char *var, const char *value)
{
	if (value) {
		if (!strcasecmp(value, "never"))
			return 0;
		if (!strcasecmp(value, "always"))
			return 1;
		if (!strcasecmp(value, "auto"))
			goto auto_color;
	}

	/* Missing or explicit false to turn off colorization */
	if (!git_config_bool(var, value))
		return 0;

	/* any normal truth value defaults to 'auto' */
 auto_color:
	if (isatty(1) || (pager_in_use && pager_use_color)) {
		char *term = getenv("TERM");
		if (term && strcmp(term, "dumb"))
			return 1;
	}
	return 0;
}

static int color_vfprintf(FILE *fp, const char *color, const char *fmt,
		va_list args, const char *trail)
{
	int r = 0;

	if (*color)
		r += fprintf(fp, "%s", color);
	r += vfprintf(fp, fmt, args);
	if (*color)
		r += fprintf(fp, "%s", COLOR_RESET);
	if (trail)
		r += fprintf(fp, "%s", trail);
	return r;
}



int color_fprintf(FILE *fp, const char *color, const char *fmt, ...)
{
	va_list args;
	int r;
	va_start(args, fmt);
	r = color_vfprintf(fp, color, fmt, args, NULL);
	va_end(args);
	return r;
}

int color_fprintf_ln(FILE *fp, const char *color, const char *fmt, ...)
{
	va_list args;
	int r;
	va_start(args, fmt);
	r = color_vfprintf(fp, color, fmt, args, "\n");
	va_end(args);
	return r;
}