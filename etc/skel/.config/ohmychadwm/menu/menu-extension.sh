#!/usr/bin/env bash
# ~/.config/ohmychadwm/menu/menu-extension.sh
#
# ohmychadwm-menu sources this file automatically. You can:
#   - Override any existing function (your version replaces the built-in one)
#   - Add new functions and call them from overridden menus
#   - Use all the built-in helpers: pick(), menu(), present_terminal(), install(),
#     aur_install(), edit_in_editor(), notify-send, etc.
#
# Menus are built with pick: each row is a key and a label, and pick prints the key
# of the chosen row. Dispatch on the key, never on the label: labels are translated.
#
# Example — uncomment to add a "Reload sxhkd" row to the System menu:
#
# show_system_menu() {
#     case $(pick "System" \
#             lock     "Lock" \
#             logout   "Logout" \
#             sxhkd    "Reload sxhkd" \
#             reboot   "Reboot" \
#             shutdown "Shutdown") in
#         lock)     _lock_screen ;;
#         logout)   _logout_chadwm ;;
#         sxhkd)    pkill -USR1 sxhkd ;;
#         reboot)   systemctl reboot ;;
#         shutdown) systemctl poweroff ;;
#         *)        return 1 ;;
#     esac
# }
