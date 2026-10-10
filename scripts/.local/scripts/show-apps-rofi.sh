#!/bin/bash

rofi -show drun \
    -show-icons \
    -i \
    -p "Apps" \
    -theme-str '
* { font: "JetBrainsMono Nerd Font Propo 16"; }
window { width: 500px; border-radius: 12px; }
listview { lines: 10; fixed-height: true; }
element { padding: 8px; }
element-text { margin: 0 8px; }
scrollbar { handle-width: 0px; width: 0px; }
listview { padding: 0px; margin: 0px; }
entry { placeholder: "Search..."; }
prompt { enabled: false; }
'
