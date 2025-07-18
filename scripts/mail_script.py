import os
import json
import email
from email import policy
from fluent import sender, event
from pathlib import Path
from datetime import datetime
import mimetypes

# Fluentd 설정
sender.setup('fluentd.test', host='localhost', port=24224)

# Maildir 경로
maildir_path = '/opt/mail/Maildir/new'

# 처리된 파일 기록용
processed_file = '/tmp/.parsed_eml_files'

if os.path.exists(processed_file):
    with open(processed_file, 'r') as f:
        already_parsed = set(f.read().splitlines())
else:
    already_parsed = set()

# 파일 순회
for eml_file in Path(maildir_path).glob('*'):
    if eml_file.name in already_parsed:
        continue

    try:
        with open(eml_file, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)

        def get_addresses(field):
            return [addr.strip() for addr in msg.get_all(field, []) if addr]

        def get_body():
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == 'text/plain':
                        return part.get_payload(decode=True).decode(part.get_content_charset('utf-8'))
            else:
                return msg.get_payload(decode=True).decode(msg.get_content_charset('utf-8'))
            return ''

        def has_attachment():
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_filename():
                        return True
            return False

        log = {'timestamp': datetime.now().isoformat(), 'from': msg.get('From', ''), 'to': get_addresses('To'), 'cc': get_addresses('Cc'), 'bcc': get_addresses('Bcc'), 'subject': msg.get('Subject', ''), 'content': get_body(), 'has_attachment': has_attachment(), 'email_size': eml_file.stat().st_size}

        event.Event('mail', log)

        # 처리 완료 기록
        with open(processed_file, 'a') as f:
            f.write(eml_file.name + '\n')

    except Exception as e:
        print("Error parsing mail:", e)
