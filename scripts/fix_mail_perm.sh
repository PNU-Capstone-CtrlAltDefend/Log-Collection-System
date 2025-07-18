#!/bin/bash
inotifywait -m -e create /opt/mail/Maildir/new | while read path action file; do
    chmod 644 "$path$file"
done
