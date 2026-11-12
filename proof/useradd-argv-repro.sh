#!/bin/bash
# P-negative: the suspected useradd/usermod GECOS flag injection in
# packages/omamobile-firstboot s_user does NOT exist — bash treats
# ${v:+-c "$v"} as one field: quotes from the VALUE are data, never
# operators. Records argv exactly as useradd would receive it.
# Expected: benign and hostile values both arrive as [ -c <one field> ];
# the username stays the last argument. (Finding rejected; keep as a
# regression note against any future unquoted reimplementation.)
set -u
declare -A C=()
C[FULL_NAME]='x" -o -u 0 "y'   # passes firstboot's "no : or ," check
useradd() { printf 'ARGV:'; printf ' [%s]' "$@"; echo; }
useradd -m -G wheel,audio,video,input -s /bin/bash \
  ${C[FULL_NAME]:+-c "${C[FULL_NAME]}"} alice
