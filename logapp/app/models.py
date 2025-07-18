from sqlalchemy import Column, Integer, Text
from app.db import Base

class RawLog(Base):
    __tablename__ = "raw_logs"

    id = Column(Integer, primary_key=True, index=True)
    log = Column(Text)

