#!/bin/sh
# Docker overlay2 workaround: "Directory renamed before its status could be extracted"
# is a benign pseudo-error on overlay2 filesystems. Filter it out and only fail on
# real extraction errors.
_tmpf=$(mktemp)
/usr/bin/tar.real "$@" 2>"$_tmpf"
_ret=$?
cat "$_tmpf" >&2
if [ $_ret -ne 0 ]; then
  _real=$(grep -v "Directory renamed before" "$_tmpf" \
        | grep -v "Exiting with failure status due to previous errors" \
        | grep -v "^$")
  if [ -z "$_real" ]; then
    rm -f "$_tmpf"
    exit 0
  fi
fi
rm -f "$_tmpf"
exit $_ret
