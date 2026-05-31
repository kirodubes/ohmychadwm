/* See LICENSE file for copyright and license details. */

/* interval between updates (in ms) */
const unsigned int interval = 1000;

/* text to show if no value can be retrieved */
static const char unknown_str[] = "n/a";

/* maximum output string length */
#define MAXLEN 2048

/*
 * function            description                     argument (example)
 *
 * battery_perc        battery percentage              battery name (BAT0)
 *                                                     NULL on OpenBSD/FreeBSD
 * battery_remaining   battery remaining HH:MM         battery name (BAT0)
 *                                                     NULL on OpenBSD/FreeBSD
 * battery_state       battery charging state          battery name (BAT0)
 *                                                     NULL on OpenBSD/FreeBSD
 * cat                 read arbitrary file             path
 * cpu_freq            cpu frequency in MHz            NULL
 * cpu_perc            cpu usage in percent            NULL
 * datetime            date and time                   format string (%F %T)
 * disk_free           free disk space in GB           mountpoint path (/)
 * disk_perc           disk usage in percent           mountpoint path (/)
 * disk_total          total disk space in GB          mountpoint path (/)
 * disk_used           used disk space in GB           mountpoint path (/)
 * entropy             available entropy               NULL
 * gid                 GID of current user             NULL
 * hostname            hostname                        NULL
 * ipv4                IPv4 address                    interface name (eth0)
 * ipv6                IPv6 address                    interface name (eth0)
 * kernel_release      `uname -r`                      NULL
 * keyboard_indicators caps/num lock indicators        format string (c?n?)
 *                                                     see keyboard_indicators.c
 * keymap              layout (variant) of current     NULL
 *                     keymap
 * load_avg            load average                    NULL
 * netspeed_rx         receive network speed           interface name (wlan0)
 * netspeed_tx         transfer network speed          interface name (wlan0)
 * num_files           number of files in a directory  path
 *                                                     (/home/foo/Inbox/cur)
 * ram_free            free memory in GB               NULL
 * ram_perc            memory usage in percent         NULL
 * ram_total           total memory size in GB         NULL
 * ram_used            used memory in GB               NULL
 * run_command         custom shell command            command (echo foo)
 * swap_free           free swap in GB                 NULL
 * swap_perc           swap usage in percent           NULL
 * swap_total          total swap size in GB           NULL
 * swap_used           used swap in GB                 NULL
 * temp                temperature in degree celsius   sensor file
 *                                                     (/sys/class/thermal/...)
 *                                                     NULL on OpenBSD
 *                                                     thermal zone on FreeBSD
 *                                                     (tz0, tz1, etc.)
 * uid                 UID of current user             NULL
 * up                  interface is running            interface name (eth0)
 * uptime              system uptime                   NULL
 * username            username of current user        NULL
 * vol_perc            OSS/ALSA volume in percent      mixer file (/dev/mixer)
 *                                                     NULL on OpenBSD/FreeBSD
 * wifi_essid          WiFi ESSID                      interface name (wlan0)
 * wifi_perc           WiFi signal in percent          interface name (wlan0)
 */
/*
 * Each active entry below adds one block to the bar (right side, left to right).
 *
 * Format:  { function, fmt_with_icon, argument }
 *
 *   fmt_with_icon  — the icon/prefix shown before the value (%s = value).
 *                    Use Nerd Font glyphs here (copy from nerdfonts.com/cheat-sheet).
 *   argument       — passed to the function (e.g. interface name, mountpoint, format).
 *
 * To enable a block: remove the leading //
 * To disable a block: add    //
 * After any change run:  cd ~/.config/ohmychadwm/slstatus && ./rebuild.sh
 */
static const struct arg args[] = {
    /* function          fmt (icon + value)     argument               */

    /* Network */
    //{ netspeed_rx,   "  %s  ",   "enp3s0"            },  /* download speed  */
    //{ netspeed_tx,   "  %s  ",   "enp3s0"            },  /* upload speed    */

    /* CPU & memory */
    { cpu_perc,      "  %s%%  ", NULL                },  /* CPU usage       */
    //{ ram_used,      "  %s  ",   NULL                },  /* RAM used (GB)   */
    //{ ram_perc,      "  %s%%  ", NULL                },  /* RAM %           */

    /* Disk */
    //{ disk_free,     "  %s  ",   "/"                 },  /* free on /       */
    //{ disk_used,     "  %s  ",   "/"                 },  /* used on /       */

    /* System */
    //{ load_avg,      "  %s  ",   NULL                },  /* load average    */
    //{ uptime,        "  %s  ",   NULL                },  /* uptime          */
    //{ kernel_release,"  %s  ",   NULL                },  /* kernel version  */

    /* Date & time — always shown last (rightmost) */
    { datetime,         "  %s",    "%H:%M  %d %m %y"   },
};
