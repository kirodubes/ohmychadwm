/* See LICENSE file for copyright and license details. */

#include <X11/XF86keysym.h>

/* layout constants — reference these in THEME_LAYOUT inside any theme file */
#define LAYOUT_DWINDLE  0   /* [\\] dwindle (default)        */
#define LAYOUT_TILE     1   /* []= tile                      */
#define LAYOUT_SPIRAL   2   /* [@] spiral                    */
#define LAYOUT_DECK     3   /* H[] deck                      */
#define LAYOUT_BSTACK   4   /* TTT bottom stack              */
#define LAYOUT_BSTACKH  5   /* === bottom stack horizontal   */
#define LAYOUT_GRID     6   /* HHH grid                      */
#define LAYOUT_NROWGRID 7   /* ### nrow grid                 */
#define LAYOUT_HORIZGRID 8  /* --- horizontal grid           */
#define LAYOUT_GAPLESS  9   /* ::: gapless grid              */
#define LAYOUT_CENTER   10  /* |M| centered master           */
#define LAYOUT_CFLOAT   11  /* >M> centered floating master  */
#define LAYOUT_FLOAT    12  /* ><> floating                  */

/* tag style constants — reference these in THEME_TAGS inside any theme file */
#define TAGS_NERD      0   /* nerd font icons (default)                        */
#define TAGS_ARABIC    1   /* 1 2 3 4 5 6 7 8 9 10                             */
#define TAGS_ROMAN     2   /* I II III IV V VI VII VIII IX X                   */
#define TAGS_POWERLINE 3   /* powerline glyphs                                 */
#define TAGS_WEBDINGS  4   /* Web Chat Edit Meld Vb Mail Video Image Files Music */
#define TAGS_JAPANESE  5   /* 一 二 三 四 五 六 七 八 九 十                      */
#define TAGS_ALPHA     6   /* A B C D E F G H I J                              */
#define TAGS_EMOJI     7   /* emoji faces/objects                               */
#define TAGS_GEOMETRIC 8   /* ● ■ ▲ ◆ ◇ ★ ✗ ✓ + ○                            */
#define TAGS_CHINESE   9   /* 壹 贰 叁 肆 伍 陆 柒 捌 玖 拾                     */
#define TAGS_PURPOSE   10  /* home chat surf media game remote code mail files misc */

// default themes
//#include "themes/catppuccin.h"
//#include "themes/dracula.h"
#include "themes/dracul.h"
//#include "themes/everforest.h"
//#include "themes/gruvchad.h"
//#include "themes/nord.h"
//#include "themes/nord-polarnight.h"
//#include "themes/nord-snowstorm.h"
//#include "themes/nord-frost.h"
//#include "themes/nord-aurora.h"
//#include "themes/onedark.h"
//#include "themes/prime.h"
//#include "themes/tokyonight.h"
//#include "themes/tundra.h"

// stellar themes
//#include "themes/jupiter.h"
//#include "themes/saturn.h"
//#include "themes/mars.h"
//#include "themes/venus.h"
//#include "themes/mercury.h"
//#include "themes/neptune.h"
//#include "themes/uranus.h"
//#include "themes/pluto.h"

// other themes
//#include "themes/kanagawa.h"
//#include "themes/monokai.h"
//#include "themes/rosepine.h"
//#include "themes/material.h"
//#include "themes/solarized.h"

// african themes (bottom bar, zero gaps)
//#include "themes/hippo.h"
//#include "themes/rhino.h"
//#include "themes/buffalo.h"

// custom themes
//#include "themes/meditation.h"
//#include "themes/venom.h"
//#include "themes/spiderwoman.h"
//#include "themes/bright.h"
//#include "themes/drwho.h"
//#include "themes/faraway.h"
//#include "themes/starwars.h"
//#include "themes/doors.h"
//#include "themes/summit.h"
//#include "themes/clonewar.h"
//#include "themes/goodnight.h"
//#include "themes/tiger.h"
//#include "themes/dragon.h"
//#include "themes/lookinto.h"

/* fallback layout settings for themes that don't define them */
#ifndef THEME_TOPBAR
#define THEME_TOPBAR 1
#endif
#ifndef THEME_GAPS
#define THEME_GAPS     5
#endif
#ifndef THEME_AUTOHIDE
#define THEME_AUTOHIDE 0
#endif
#ifndef THEME_SHOWSYSTRAY
#define THEME_SHOWSYSTRAY 1
#endif
#ifndef THEME_BORDER
#define THEME_BORDER 2
#endif
#ifndef THEME_SMARTGAPS
#define THEME_SMARTGAPS 0
#endif
#ifndef THEME_MFACT
#define THEME_MFACT 0.50
#endif
#ifndef THEME_NMASTER
#define THEME_NMASTER 1
#endif
#ifndef THEME_FONT
#define THEME_FONT "JetBrainsMono Nerd Font Mono"
#endif
#ifndef THEME_FONTSTYLE
#define THEME_FONTSTYLE "Bold"
#endif
#ifndef THEME_FONTSIZE
#define THEME_FONTSIZE 13
#endif
#ifndef THEME_ICONSIZE
#define THEME_ICONSIZE 18
#endif
#ifndef THEME_TAGS
#define THEME_TAGS TAGS_NERD
#endif
#ifndef THEME_LAYOUT
#define THEME_LAYOUT LAYOUT_DWINDLE
#endif

/* stringify helper — combines THEME_FONT + THEME_FONTSIZE at compile time */
#ifndef _STR
#define _STRINGIFY(x) #x
#define _STR(x) _STRINGIFY(x)
#endif

/* appearance */
static const unsigned int borderpx  = THEME_BORDER ; /* border pixel of windows */
static const unsigned int default_border = 0;   /* to switch back to default border after dynamic border resizing via keybinds */
static const unsigned int snap      = 32;       /* snap pixel */
static const unsigned int gappih    = THEME_GAPS ; /* horiz inner gap between windows */
static const unsigned int gappiv    = THEME_GAPS ; /* vert inner gap between windows */
static const unsigned int gappoh    = THEME_GAPS ; /* horiz outer gap between windows and screen edge */
static const unsigned int gappov    = THEME_GAPS ; /* vert outer gap between windows and screen edge */
static const int smartgaps          = THEME_SMARTGAPS ; /* 1 means no outer gap when there is only one window */
static const unsigned int systraypinning = 0;   /* 0: sloppy systray follows selected monitor, >0: pin systray to monitor X */
static const unsigned int systrayspacing = 2;   /* systray spacing */
static const unsigned int systrayiconsize = 24; /* systray icon size in px */
static const int systraypinningfailfirst = 1;   /* 1: if pinning fails,display systray on the 1st monitor,False: display systray on last monitor*/
static const int showsystray        = THEME_SHOWSYSTRAY ; /* 0 means no systray */
static const int autohidebar        = THEME_AUTOHIDE; /* seconds before bar auto-hides; 0 = disabled */
static const int showmenu           = 1;        /* 0 means no menu launcher in bar */
static const int showbar            = 1;        /* 0 means no bar */
static const int showtab            = showtab_auto;
static const int toptab             = 1;        /* 0 means bottom tab */
static const int floatbar           = 1;        /* 1 means the bar will float(don't have padding),0 means the bar have padding */
static const int topbar             = THEME_TOPBAR ; /* 0 means bottom bar */
static const int horizpadbar        = 5 ;        /* padding inside the bar */
static const int vertpadbar         = 11 ;       /* padding inside the bar */
static const int vertpadtab         = 35;
static const int horizpadtabi       = 15;
static const int horizpadtabo       = 15;
static const int scalepreview       = 4;
static const int tag_preview        = 1;        /* 1 means enable, 0 is off */
static const int colorfultag        = 1;        /* 0 means use SchemeSel for selected non vacant tag */
static const char *upvol[]   = { "/usr/bin/pactl", "set-sink-volume", "0", "+5%",     NULL };
static const char *downvol[] = { "/usr/bin/pactl", "set-sink-volume", "0", "-5%",     NULL };
static const char *mutevol[] = { "/usr/bin/pactl", "set-sink-mute",   "0", "toggle",  NULL };
static const char *light_up[] = {"/usr/bin/light", "-A", "5", NULL};
static const char *light_down[] = {"/usr/bin/light", "-U", "5", NULL};
static const int new_window_attach_on_end = 0 ; /*  1 means the new window will attach on the end; 0 means the new window will attach on the front,default is front */
#define ICONSIZE 19   /* icon size */
#define ICONSPACING 8 /* space between icon and title */

/* primary font + Nerd Font fallback for bar icons (always rendered at THEME_ICONSIZE) */
static const char *fonts[] = {
    THEME_FONT ":style=" THEME_FONTSTYLE ":size=" _STR(THEME_FONTSIZE),
    "JetBrainsMono Nerd Font Mono:style=Bold:size=" _STR(THEME_ICONSIZE),
    "Noto Sans CJK JP:size=" _STR(THEME_FONTSIZE),
};

static const char *colors[][3] = {
    /*                     fg                bg                border */
    [SchemeNorm]       = { SchemeNormfg,     SchemeNormbg,     SchemeNormbr },
    [SchemeSel]        = { SchemeSelfg,      SchemeSelbg,      SchemeSelbr },
    [SchemeTitle]      = { SchemeTitlefg,    SchemeTitlebg,    SchemeTitlebr },
    [TabSel]           = { TabSelfg,         TabSelbg,         TabSelbr },
    [TabNorm]          = { TabNormfg,        TabNormbg,        TabNormbr },
    [SchemeTag]        = { SchemeTagfg,      SchemeTagbg,      SchemeTagbr },
    [SchemeTag1]       = { SchemeTag1fg,     SchemeTag1bg,     SchemeTag1br },
    [SchemeTag2]       = { SchemeTag2fg,     SchemeTag2bg,     SchemeTag2br },
    [SchemeTag3]       = { SchemeTag3fg,     SchemeTag3bg,     SchemeTag3br },
    [SchemeTag4]       = { SchemeTag4fg,     SchemeTag4bg,     SchemeTag4br },
    [SchemeTag5]       = { SchemeTag5fg,     SchemeTag5bg,     SchemeTag5br },
    [SchemeTag6]       = { SchemeTag6fg,     SchemeTag6bg,     SchemeTag6br },
    [SchemeTag7]       = { SchemeTag7fg,     SchemeTag7bg,     SchemeTag7br },
    [SchemeTag8]       = { SchemeTag8fg,     SchemeTag8bg,     SchemeTag8br },
    [SchemeTag9]       = { SchemeTag9fg,     SchemeTag9bg,     SchemeTag9br },
    [SchemeTag10]      = { SchemeTag10fg,    SchemeTag10bg,    SchemeTag10br },
    [SchemeLayout]     = { SchemeLayoutfg,   SchemeLayoutbg,   SchemeLayoutbr },
    [SchemeBtnPrev]    = { SchemeBtnPrevfg,  SchemeBtnPrevbg,  SchemeBtnPrevbr },
    [SchemeBtnNext]    = { SchemeBtnNextfg,  SchemeBtnNextbg,  SchemeBtnNextbr },
    [SchemeBtnClose]   = { SchemeBtnClosefg, SchemeBtnClosebg, SchemeBtnClosebr },
    [SchemeLayoutFF]   = { SchemeLayoutFFfg, SchemeLayoutFFbg, SchemeLayoutFFbr },
    [SchemeLayoutEW]   = { SchemeLayoutEWfg, SchemeLayoutEWbg, SchemeLayoutEWbr },
    [SchemeLayoutDS]   = { SchemeLayoutDSfg, SchemeLayoutDSbg, SchemeLayoutDSbr },
    [SchemeLayoutTG]   = { SchemeLayoutTGfg, SchemeLayoutTGbg, SchemeLayoutTGbr },
    [SchemeLayoutMS]   = { SchemeLayoutMSfg, SchemeLayoutMSbg, SchemeLayoutMSbr },
    [SchemeLayoutPC]   = { SchemeLayoutPCfg, SchemeLayoutPCbg, SchemeLayoutPCbr },
    [SchemeLayoutVV]   = { SchemeLayoutVVfg, SchemeLayoutVVbg, SchemeLayoutVVbr },
    [SchemeLayoutOP]   = { SchemeLayoutOPfg, SchemeLayoutOPbg, SchemeLayoutOPbr },
    [SchemeMenu]       = { SchemeMenufg,     SchemeMenubg,     SchemeMenubr },
};

/* tagging — style selected via THEME_TAGS in the active theme file */
#if   THEME_TAGS == TAGS_ARABIC
static char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" };
#elif THEME_TAGS == TAGS_ROMAN
static char *tags[] = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" };
#elif THEME_TAGS == TAGS_POWERLINE
static char *tags[] = { "", "", "", "", "", "", "", "", "", "" };
#elif THEME_TAGS == TAGS_WEBDINGS
static char *tags[] = { "Web", "Chat", "Edit", "Meld", "Vb", "Mail", "Video", "Image", "Files", "Music" };
#elif THEME_TAGS == TAGS_JAPANESE
static char *tags[] = { "一", "二", "三", "四", "五", "六", "七", "八", "九", "十" };
#elif THEME_TAGS == TAGS_ALPHA
static char *tags[] = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" };
#elif THEME_TAGS == TAGS_EMOJI
static char *tags[] = { "👨‍💻", "🌐", "🖥️", "📟", "📜", "👋", "📺", "✉️", "💬", "🎮" };
#elif THEME_TAGS == TAGS_GEOMETRIC
static char *tags[] = { "●", "■", "▲", "◆", "◇", "★", "✗", "✓", "+", "○" };
#elif THEME_TAGS == TAGS_CHINESE
static char *tags[] = { "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾" };
#elif THEME_TAGS == TAGS_PURPOSE
static char *tags[] = { "home", "chat", "surf", "media", "game", "remote", "code", "mail", "files", "misc" };
#else
static char *tags[] = { "", "", "", "", "", "󰋉", "", "", "", "" };
#endif

static const char* ohmychadwm_menu[] = { "/bin/sh", "-c", "/home/erik/.config/ohmychadwm/menu/ohmychadwm-menu.sh", NULL };
static const char* firefox[] = { "firefox", NULL };
static const char* vivaldi[] = { "vivaldi", NULL };
static const char* brave[] = { "brave", "--password-store=basic", "%U", NULL };
static const char* opera[] = { "opera", NULL };
static const char* discord[] = { "discord", "open" , "discord", NULL };
static const char* telegram[] = { "Telegram", "open" , "Telegram", NULL };
static const char* mintstick[] = { "mintstick", "-m", "iso", NULL};
static const char* pavucontrol[] = { "pavucontrol", NULL };

static const Launcher launchers[] = {
    /* command     name to display */
    { ohmychadwm_menu, "󱪾" },

    //{ discord,       "ﱲ" },
    //{ firefox,       "" },
    //{ brave,         "" },
    //{ opera,         "" },
    //{ mintstick,     "虜" },
    //{ pavucontrol,   "墳" },
    //{ telegram,      "" },
    //{ vivaldi,       "" },
    { NULL, NULL }, /* sentinel — keep last, allows commenting out all entries above */
};

static const int tagschemes[] = {
    SchemeTag1, SchemeTag2, SchemeTag3, SchemeTag4, SchemeTag5, SchemeTag6, SchemeTag7, SchemeTag8, SchemeTag9, SchemeTag10
};

static const unsigned int ulinepad      = 5; /* horizontal padding between the underline and tag */
static const unsigned int ulinestroke   = 2; /* thickness / height of the underline */
static const unsigned int ulinevoffset  = 0; /* how far above the bottom of the bar the line should appear */
static const int ulineall               = 0; /* 1 to show underline on all tags, 0 for just the active ones */

static const Rule rules[] = {
    /* xprop(1):
     *	WM_CLASS(STRING) = instance, class
     *	WM_NAME(STRING) = title
     */
    /* class      instance    title       tags mask     iscentered   isfloating   monitor */
    { "Gimp",     NULL,       NULL,       0,            0,           0,           -1 },
    { "Firefox",  NULL,       NULL,       1 << 8,       0,           0,           -1 },
    { "mintstick", NULL,      NULL,       0,            0,           0,           -1 },
};

/* layout(s) */
static const float mfact     = THEME_MFACT   ;   /* factor of master area size [0.05..0.95] */
static const int nmaster     = THEME_NMASTER ; /* number of clients in master area */
static const int resizehints = 0;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */

#define FORCE_VSPLIT 1  /* nrowgrid layout: force two clients to always split vertically */
#include "functions.h"


static const Layout layouts[] = {
    /* symbol     arrange function — first entry is the startup default */
#if   THEME_LAYOUT == LAYOUT_TILE
    { "[]=",      tile },
#elif THEME_LAYOUT == LAYOUT_SPIRAL
    { "[@]",      spiral },
#elif THEME_LAYOUT == LAYOUT_DECK
    { "H[]",      deck },
#elif THEME_LAYOUT == LAYOUT_BSTACK
    { "TTT",      bstack },
#elif THEME_LAYOUT == LAYOUT_BSTACKH
    { "===",      bstackhoriz },
#elif THEME_LAYOUT == LAYOUT_GRID
    { "HHH",      grid },
#elif THEME_LAYOUT == LAYOUT_NROWGRID
    { "###",      nrowgrid },
#elif THEME_LAYOUT == LAYOUT_HORIZGRID
    { "---",      horizgrid },
#elif THEME_LAYOUT == LAYOUT_GAPLESS
    { ":::",      gaplessgrid },
#elif THEME_LAYOUT == LAYOUT_CENTER
    { "|M|",      centeredmaster },
#elif THEME_LAYOUT == LAYOUT_CFLOAT
    { ">M>",      centeredfloatingmaster },
#elif THEME_LAYOUT == LAYOUT_FLOAT
    { "><>",      NULL },
#else
    { "[\\]",     dwindle },
#endif
    { "[\\]",     dwindle },
    { "[]=",      tile },
    { "[@]",      spiral },
    { "H[]",      deck },
    { "TTT",      bstack },
    { "===",      bstackhoriz },
    { "HHH",      grid },
    { "###",      nrowgrid },
    { "---",      horizgrid },
    { ":::",      gaplessgrid },
    { "|M|",      centeredmaster },
    { ">M>",      centeredfloatingmaster },
    { "><>",      NULL },
    { NULL,       NULL },
};

/* key definitions */
#define MODKEY Mod4Mask
#define TAGKEYS(KEY,TAG) \
    { MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
    { MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
    { MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */

static const Key keys[] = {
    /* modifier                         key         function        argument */

    // brightness and audio 
    {0,             XF86XK_AudioLowerVolume,    spawn, {.v = downvol}},
	{0,             XF86XK_AudioMute, spawn,    {.v = mutevol }},
	{0,             XF86XK_AudioRaiseVolume,    spawn, {.v = upvol}},
	{0,				XF86XK_MonBrightnessUp,     spawn,	{.v = light_up}},
	{0,				XF86XK_MonBrightnessDown,   spawn,	{.v = light_down}},

    // screenshot fullscreen and cropped
    {MODKEY|ControlMask,                XK_u,       spawn,
        SHCMD("maim | xclip -selection clipboard -t image/png")},
    {MODKEY,                            XK_u,       spawn,
        SHCMD("maim --select | xclip -selection clipboard -t image/png")},

    //{ MODKEY,                           XK_c,       spawn,          SHCMD("rofi -show drun") },
    //{ MODKEY,                           XK_Return,  spawn,            SHCMD("st")},

    // toggle stuff
    { MODKEY,                           XK_b,       togglebar,      {0} },
    { MODKEY|ShiftMask,                 XK_space,   togglebar,      {0} },
    { MODKEY|ControlMask,               XK_t,       togglegaps,     {0} },
    //{ MODKEY|ShiftMask,                 XK_space,   togglefloating, {0} },
    { MODKEY,                           XK_f,       togglefullscr,  {0} },

    { MODKEY|ControlMask,               XK_w,       tabmode,        { -1 } },
    //{ MODKEY,                           XK_j,       focusstack,     {.i = +1 } },
    //{ MODKEY,                           XK_k,       focusstack,     {.i = -1 } },
    { MODKEY,                           XK_i,       incnmaster,     {.i = +1 } },
    { MODKEY,                           XK_n,       incnmaster,     {.i = -1 } },

    // shift view
    { MODKEY,                           XK_Left,    shiftview,      {.i = -1 } },
    { MODKEY,                           XK_Right,   shiftview,      {.i = +1 } },

    // change m,cfact sizes 
    { MODKEY,                           XK_h,       setmfact,       {.f = -0.05} },
    { MODKEY,                           XK_l,       setmfact,       {.f = +0.05} },
    { MODKEY|ShiftMask,                 XK_h,       setcfact,       {.f = +0.25} },
    { MODKEY|ShiftMask,                 XK_l,       setcfact,       {.f = -0.25} },
    { MODKEY|ShiftMask,                 XK_o,       setcfact,       {.f =  0.00} },


    { MODKEY|ShiftMask,                 XK_j,       movestack,      {.i = +1 } },
    { MODKEY|ShiftMask,                 XK_k,       movestack,      {.i = -1 } },
    { MODKEY|ControlMask,               XK_j,       rotatestack,    {.i = +1 } },
    { MODKEY|ControlMask,               XK_k,       rotatestack,    {.i = -1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_Return,  zoom,           {0} },
    { MODKEY|Mod1Mask,                  XK_o,       changeopacity,  {.f = +0.05} },
    { MODKEY|Mod1Mask|ShiftMask,        XK_o,       changeopacity,  {.f = -0.05} },
    { MODKEY,                           XK_Tab,     view,           {0} },

    // overall gaps
    { MODKEY|ControlMask,               XK_i,       incrgaps,       {.i = +1 } },
    { MODKEY|ControlMask,               XK_d,       incrgaps,       {.i = -1 } },

    // inner gaps
    { MODKEY|ShiftMask,                 XK_i,       incrigaps,      {.i = +1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_i,       incrigaps,      {.i = -1 } },

    // outer gaps
    { MODKEY|ControlMask,               XK_o,       incrogaps,      {.i = +1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_o,       incrogaps,      {.i = -1 } },

    // inner+outer hori, vert gaps 
    { MODKEY|ControlMask,               XK_section,           incrihgaps,     {.i = +1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_section,           incrihgaps,     {.i = -1 } },
    { MODKEY|ControlMask,               XK_egrave,            incrivgaps,     {.i = +1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_egrave,            incrivgaps,     {.i = -1 } },
    { MODKEY|ControlMask,               XK_exclam,            incrohgaps,     {.i = +1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_exclam,            incrohgaps,     {.i = -1 } },
    { MODKEY|ControlMask,               XK_ccedilla,          incrovgaps,     {.i = +1 } },
    { MODKEY|ControlMask|ShiftMask,     XK_ccedilla,          incrovgaps,     {.i = -1 } },

    { MODKEY|ControlMask|ShiftMask,     XK_d,                 defaultgaps,    {0} },
    { MODKEY|ControlMask|ShiftMask,     XK_r,                 spawn, SHCMD("$HOME/.config/ohmychadwm/chadwm/rebuild.sh") },

    // layout (preferences = no 1,3,4,8,9)
    { MODKEY|ControlMask,               XK_F1,       setlayout,      {.v = &layouts[0]} },
    { MODKEY|ControlMask,               XK_F2,       setlayout,      {.v = &layouts[1]} },
    { MODKEY|ControlMask,               XK_F3,       setlayout,      {.v = &layouts[2]} },
    { MODKEY|ControlMask,               XK_F4,       setlayout,      {.v = &layouts[3]} },
    { MODKEY|ControlMask,               XK_F5,       setlayout,      {.v = &layouts[4]} },
    { MODKEY|ControlMask,               XK_F6,       setlayout,      {.v = &layouts[5]} },
    { MODKEY|ControlMask,               XK_F7,       setlayout,      {.v = &layouts[6]} },
    { MODKEY|ControlMask,               XK_F8,       setlayout,      {.v = &layouts[7]} },
    { MODKEY|ControlMask,               XK_F9,       setlayout,      {.v = &layouts[8]} },
    { MODKEY|ControlMask,               XK_F10,      setlayout,      {.v = &layouts[9]} },
    { MODKEY|ControlMask,               XK_F11,      setlayout,      {.v = &layouts[10]} },
    { MODKEY|ControlMask,               XK_F12,      setlayout,      {.v = &layouts[11]} },

    //{ MODKEY,                           XK_space,   setlayout,      {0} },
    { MODKEY|ControlMask,               XK_p,       cyclelayout,    {.i = -1 } },
    { MODKEY|ControlMask,               XK_m,       cyclelayout,    {.i = +1 } },
    { MODKEY,                           XK_agrave,  view,           {.ui = ~0 } },
    { MODKEY|ShiftMask,                 XK_agrave,  tag,            {.ui = ~0 } },
    { MODKEY,                           XK_comma,   focusmon,       {.i = -1 } },
    { MODKEY,                           XK_semicolon,  focusmon,       {.i = +1 } },
    { MODKEY|ShiftMask,                 XK_Left,    tagmon,         {.i = -1 } },
    { MODKEY|ShiftMask,                 XK_Right,   tagmon,         {.i = +1 } },

    // change border size
    { MODKEY|ShiftMask,                 XK_minus,   setborderpx,    {.i = -1 } },
    { MODKEY|ShiftMask,                 XK_p,       setborderpx,    {.i = +1 } },
    { MODKEY|ShiftMask,                 XK_w,       setborderpx,    {.i = default_border } },

    // kill dwm
    { ControlMask|Mod1Mask,            XK_Delete,   killall,        {0} },
    { ControlMask|Mod1Mask|ShiftMask,  XK_Delete,   quit,           {0} },

    // kill window
    { MODKEY,                           XK_q,       killclient,     {0} },
    { MODKEY|ShiftMask,                 XK_q,       killclient,     {0} },
    { MODKEY|ShiftMask,                 XK_c,       killclient,     {0} },
    { MODKEY|ControlMask,               XK_q,       killall,        {0} },

    // restart
    { MODKEY|ShiftMask,                 XK_r,       restart,        {0} },
    { MODKEY|ShiftMask|ControlMask,     XK_r,       spawn,          SHCMD("alacritty -e bash -c 'cd ~/.config/ohmychadwm/chadwm && ./rebuild.sh; exec bash'") },
    // hide & restore windows
    //{ MODKEY,                           XK_i,       hidewin,        {0} },
    //{ MODKEY|ShiftMask,                 XK_i,       restorewin,     {0} },

    // qwerty keyboard

    //TAGKEYS(                            XK_1,                       0)
    //TAGKEYS(                            XK_2,                       1)
    //TAGKEYS(                            XK_3,                       2)
    //TAGKEYS(                            XK_4,                       3)
    //TAGKEYS(                            XK_5,                       4)
    //TAGKEYS(                            XK_6,                       5)
    //TAGKEYS(                            XK_7,                       6)
    //TAGKEYS(                            XK_8,                       7)
    //TAGKEYS(                            XK_9,                       8)

    // azerty keyboard (Belgium)
    TAGKEYS(                               XK_ampersand,                0)
    TAGKEYS(                               XK_eacute,                   1)
    TAGKEYS(                               XK_quotedbl,                 2)
    TAGKEYS(                               XK_apostrophe,               3)
    TAGKEYS(                               XK_parenleft,                4)
    TAGKEYS(                               XK_section,                  5)
    TAGKEYS(                               XK_egrave,                   6)
    TAGKEYS(                               XK_exclam,                   7)
    TAGKEYS(                               XK_ccedilla,                 8)

};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
    /* click                event mask      button          function        argument */
    { ClkLtSymbol,          0,              Button1,        cyclelayout,    {.i = +1 } }, // next
    { ClkLtSymbol,          0,              Button3,        cyclelayout,    {.i = -1 } }, // previous
    { ClkWinTitle,          0,              Button2,        zoom,           {0} },
    { ClkStatusText,        0,              Button2,        spawn,          SHCMD("st") },

    /* Keep movemouse? */
    /* { ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} }, */

    /* placemouse options, choose which feels more natural:
    *    0 - tiled position is relative to mouse cursor
    *    1 - tiled position is relative to window center
    *    2 - mouse pointer warps to window center
    *
    * The moveorplace uses movemouse or placemouse depending on the floating state
    * of the selected client. Set up individual keybindings for the two if you want
    * to control these separately (i.e. to retain the feature to move a tiled window
    * into a floating position).
    */
    { ClkClientWin,         MODKEY,         Button1,        moveorplace,    {.i = 0} },
    { ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
    //{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
    { ClkClientWin,         MODKEY,			Button3,        dragmfact,      {0} },
    //{ ClkClientWin,         MODKEY,    	Button3,        dragcfact,      {0} },
    { ClkRootWin,           0,              Button3,        spawn,          {.v = ohmychadwm_menu} },
    { ClkTagBar,            0,              Button1,        view,           {0} },
    { ClkTagBar,            0,              Button3,        toggleview,     {0} },
    { ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
    { ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
    { ClkTabBar,            0,              Button1,        focuswin,       {0} },
    { ClkTabBar,            0,              Button1,        focuswin,       {0} },
    { ClkTabPrev,           0,              Button1,        movestack,      { .i = -1 } },
    { ClkTabNext,           0,              Button1,        movestack,      { .i = +1 } },
    { ClkTabClose,          0,              Button1,        killclient,     {0} },
};
