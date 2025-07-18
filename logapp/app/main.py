from fastapi import FastAPI, Request, Depends
from sqlalchemy.orm import Session
from app.db import get_db, Base, engine
from app.models import RawLog
import json
import re

app = FastAPI()

Base.metadata.create_all(bind=engine)

@app.post("/log")
async def receive_log(request: Request, db: Session = Depends(get_db)):
    body = await request.body()
    try:
        text = body.decode('utf-8').strip()
        entries = re.findall(r'{.*?}', text, flags=re.DOTALL)

        for entry in entries:
            try:
                log_json = json.loads(entry)
                print("[RECEIVED LOG]", log_json)

                db_log = RawLog(log=json.dumps(log_json))
                db.add(db_log)
                db.commit()
            except json.JSONDecodeError as je:
                print("[ERROR: decode]", je)
            except Exception as e:
                print("[ERROR: insert]", e)
    except Exception as e:
        print("[ERROR: request]", e)

    return {"status": "ok"}
